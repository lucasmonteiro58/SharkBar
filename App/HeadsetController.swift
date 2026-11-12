import Foundation
import SwiftUI
import WidgetKit

struct EQSlot: Identifiable, Equatable {
    let id: Int          // 0…5
    var enabled: Bool
    var active: Bool
    var order: [UInt8]   // linha crua da tabela 0x60 (6 bytes)
    var bands: [Int]     // 10 bandas em dB (-12…12)
}

@MainActor
final class HeadsetController: ObservableObject {
    @Published private(set) var snapshot = HeadsetSnapshot()
    @Published private(set) var dongleConnected = false
    @Published var sidetone: Int = 0
    @Published var autoOff: Int = 15
    @Published var micPreset: Int = 0x20
    @Published var micEQ: [Int] = Array(repeating: 0, count: 10)
    @Published var eqSlots: [EQSlot] = []
    @Published var lastError: String?
    @Published private(set) var busy = false

    private let hid = HIDTransport()
    private var pollTask: Task<Void, Never>?

    init() {
        hid.onConnectionChange = { [weak self] connected in
            guard let self else { return }
            dongleConnected = connected
            if connected {
                Task { await self.refreshAll() }
            } else {
                Task { await self.refreshStatus() }
            }
        }
        hid.onUnsolicited = { [weak self] reply in self?.apply(reply) }
        hid.start()
        CommandRouter.shared.headset = self
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                await self?.refreshStatus()
            }
        }
    }

    // MARK: - Leitura

    /// Bateria, carga, ANC e mute — leve, roda a cada 15 s. Sem resposta pelo dongle,
    /// verifica se o fone está ligado por Bluetooth.
    func refreshStatus() async {
        var viaHID = false
        if hid.isConnected {
            do {
                for cmd: BlackShark.Command in [.battery, .charging, .anc, .micMute] {
                    apply(BlackShark.Reply(command: cmd.rawValue, status: .success, data: try await hid.transact(cmd.rawValue)))
                }
                viaHID = true
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
        if viaHID {
            snapshot.connected = true
            snapshot.link = [0x0576, 0x0579].contains(hid.productID ?? 0) ? .usb : .dongle
        } else {
            let bt = BluetoothWatcher.status(matching: ["BlackShark"])
            snapshot.connected = bt.connected
            snapshot.link = bt.connected ? .bluetooth : DeviceLink.none
            if bt.connected {
                // Por Bluetooth o protocolo da Razer não está disponível.
                snapshot.battery = bt.battery
                snapshot.charging = false
                snapshot.ancMode = nil
                snapshot.ancLevel = nil
                snapshot.micMuted = nil
                lastError = nil
            }
        }
        publish()
    }

    /// Tudo, inclusive EQs — ao conectar e ao abrir a janela.
    func refreshAll() async {
        await refreshStatus()
        guard snapshot.connected, snapshot.link != .bluetooth else { return }
        do {
            sidetone = Int(try await one(.sidetone))
            autoOff = Int(try await one(.autoOff))
            micPreset = Int(try await one(.micPreset))
            let mic = try await hid.transact(BlackShark.Command.micEQ.rawValue)
            if mic.count == 10 { micEQ = mic.map(BlackShark.decodeGain) }
            var slots: [EQSlot] = []
            for s in UInt8(0)..<6 {
                let order = try await hid.transact(BlackShark.Command.eqOrder.rawValue, [s])
                let eq = try await hid.transact(BlackShark.Command.speakerEQ.rawValue, [s])
                guard order.count == 6, order[0] == s, eq.count == 11, eq[0] == s else {
                    throw HeadsetError.badAnswer("slot de EQ \(s)")
                }
                slots.append(EQSlot(id: Int(s), enabled: order[2] == 1, active: order[3] == 1,
                                    order: order, bands: eq.dropFirst().map(BlackShark.decodeGain)))
            }
            eqSlots = slots
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func one(_ cmd: BlackShark.Command) async throws -> UInt8 {
        let d = try await hid.transact(cmd.rawValue)
        guard d.count == 1 else { throw HeadsetError.badAnswer("\(cmd)") }
        return d[0]
    }

    private func apply(_ r: BlackShark.Reply) {
        switch BlackShark.Command(rawValue: r.command) {
        case .battery where r.data.count == 1 && r.data[0] <= 100: snapshot.battery = Int(r.data[0])
        case .charging where r.data.count == 1: snapshot.charging = r.data[0] == 1
        case .anc where r.data.count == 2:
            snapshot.ancMode = AncMode(rawValue: Int(r.data[0]))
            snapshot.ancLevel = Int(r.data[1])
        case .micMute where r.data.count == 1: snapshot.micMuted = r.data[0] == 1
        case .sidetone where r.data.count == 1: sidetone = Int(r.data[0])
        default: break
        }
    }

    private func publish() {
        snapshot.updated = .now
        SharedStore.save(snapshot, as: "headset")
        WidgetCenter.shared.reloadAllTimelines()
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    // MARK: - Escrita

    private func write(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true
            defer { busy = false }
            do {
                try await work()
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func setANC(_ mode: AncMode, level: Int? = nil) {
        let lvl = max(1, min(10, level ?? snapshot.ancLevel ?? 5))
        write {
            _ = try await self.hid.transact(BlackShark.Command.anc.set, [UInt8(mode.rawValue), UInt8(lvl)])
            let d = try await self.hid.transact(BlackShark.Command.anc.rawValue)
            self.apply(BlackShark.Reply(command: BlackShark.Command.anc.rawValue, status: .success, data: d))
            self.publish()
        }
    }

    func cycleANC() {
        let all = AncMode.allCases
        let cur = snapshot.ancMode ?? .off
        setANC(all[(all.firstIndex(of: cur)! + 1) % all.count])
    }

    func commitSidetone() {
        let v = UInt8(max(0, min(100, sidetone)))
        write { _ = try await self.hid.transact(BlackShark.Command.sidetone.set, [v]) }
    }

    func setAutoOff(_ minutes: Int) {
        autoOff = minutes
        write { _ = try await self.hid.transact(BlackShark.Command.autoOff.set, [UInt8(minutes)]) }
    }

    func setMicPreset(_ p: Int) {
        micPreset = p
        write {
            _ = try await self.hid.transact(BlackShark.Command.micPreset.set, [UInt8(p)])
            let mic = try await self.hid.transact(BlackShark.Command.micEQ.rawValue)
            if mic.count == 10 { self.micEQ = mic.map(BlackShark.decodeGain) }
        }
    }

    func commitMicEQ() {
        let bytes = micEQ.map(BlackShark.encodeGain)
        write { _ = try await self.hid.transact(BlackShark.Command.micEQ.set, bytes) }
    }

    /// Seleciona o slot de EQ ativo reescrevendo a tabela de ordem (sequência do Synapse).
    func activateSlot(_ id: Int) {
        guard let target = eqSlots.first(where: { $0.id == id }), target.enabled else { return }
        write {
            var orders: [[UInt8]] = []
            for s in UInt8(0)..<6 {
                var o = try await self.hid.transact(BlackShark.Command.eqOrder.rawValue, [s])
                guard o.count == 6, o[0] == s else { throw HeadsetError.badAnswer("tabela de EQ") }
                o[3] = Int(s) == id ? 1 : 0
                orders.append(o)
            }
            _ = try await self.hid.transact(BlackShark.Command.eqStage.rawValue, [1])
            var failure: Error?
            for o in orders {
                do { _ = try await self.hid.transact(BlackShark.Command.eqOrderWrite.rawValue, o) }
                catch { failure = error; break }
            }
            _ = try await self.hid.transact(BlackShark.Command.eqStage.rawValue, [2])
            if let failure { throw failure }
            for i in self.eqSlots.indices { self.eqSlots[i].active = self.eqSlots[i].id == id }
        }
    }

    /// Grava as 10 bandas de um slot (stage → bandas → ordem → commit).
    func commitSlot(_ id: Int) {
        guard let slot = eqSlots.first(where: { $0.id == id }) else { return }
        let args = [UInt8(id)] + slot.bands.map(BlackShark.encodeGain)
        write {
            let order = try await self.hid.transact(BlackShark.Command.eqOrder.rawValue, [UInt8(id)])
            guard order.count == 6, order[0] == UInt8(id) else { throw HeadsetError.badAnswer("tabela de EQ") }
            _ = try await self.hid.transact(BlackShark.Command.eqStage.rawValue, [1])
            var failure: Error?
            do {
                _ = try await self.hid.transact(BlackShark.Command.speakerEQ.set, args)
                _ = try await self.hid.transact(BlackShark.Command.eqOrderWrite.rawValue, order)
            } catch { failure = error }
            _ = try await self.hid.transact(BlackShark.Command.eqStage.rawValue, [2])
            if let failure { throw failure }
        }
    }
}
