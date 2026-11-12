import Foundation
import IOKit.hid
import SwiftUI
import WidgetKit

/// Attack Shark X6: escuta heartbeats/eventos e envia relatórios feature com ACK.
@MainActor
final class MouseController: ObservableObject {
    @Published private(set) var snapshot = MouseSnapshot()
    @Published private(set) var dongleConnected = false
    @Published var config: MouseConfig { didSet { saveConfig() } }
    /// Falso até o primeiro envio completo: o mouse pode ter outra configuração.
    @Published private(set) var synced: Bool
    @Published var lastError: String?
    @Published private(set) var busy = false

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    /// 0xFA60 = dongle 2.4 GHz; outro PID do mesmo fabricante = mouse no cabo USB.
    private var productID = 0
    private var wiredLink: DeviceLink { productID == AttackShark.productID ? .dongle : .usb }
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 512)
    private var ackWaiter: (id: UInt8, cont: CheckedContinuation<Void, Error>)?
    private var lastHeartbeat = Date.distantPast
    private var watchdog: Task<Void, Never>?
    private var writeTail: Task<Void, Never>?

    private static let configKey = "mouseConfig.v1"
    private static let syncedKey = "mouseConfig.synced"

    init() {
        let d = UserDefaults.standard
        config = d.data(forKey: Self.configKey).flatMap { try? JSONDecoder().decode(MouseConfig.self, from: $0) } ?? .factory
        synced = d.bool(forKey: Self.syncedKey)
        start()
        CommandRouter.shared.mouse = self
        publish() // não deixa o widget com o estado da execução anterior
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                let wired = self.device != nil && self.productID != AttackShark.productID
                let viaDongle = wired || (self.snapshot.link == .dongle && Date.now.timeIntervalSince(self.lastHeartbeat) < 10)
                var link: DeviceLink = viaDongle ? self.wiredLink : .none
                var battery = self.snapshot.battery
                if !viaDongle {
                    let bt = BluetoothWatcher.status(matching: ["X6", "Attack Shark"])
                    if bt.connected { link = .bluetooth; battery = bt.battery }
                }
                if link != self.snapshot.link || battery != self.snapshot.battery {
                    self.snapshot.link = link
                    self.snapshot.connected = link != .none
                    self.snapshot.battery = battery
                    self.publish()
                }
            }
        }
    }

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) { UserDefaults.standard.set(data, forKey: Self.configKey) }
    }

    // MARK: - HID

    private func start() {
        // Sem filtrar o PID: o dongle é 1d57:fa60; no cabo o X6 aparece com outro PID do mesmo fabricante.
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: AttackShark.vendorID,
            kIOHIDPrimaryUsagePageKey: AttackShark.configUsagePage,
            kIOHIDPrimaryUsageKey: AttackShark.configUsage,
        ] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<MouseController>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.attach(dev) }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<MouseController>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.detach(dev) }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ dev: IOHIDDevice) {
        let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
        // Prefere o cabo quando os dois estão presentes (o cabo também carrega o mouse).
        if device != nil, !(productID == AttackShark.productID && pid != AttackShark.productID) { return }
        device = dev
        productID = pid
        dongleConnected = true
        if pid != AttackShark.productID {
            snapshot.link = .usb
            snapshot.connected = true
            lastHeartbeat = .now
            publish()
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, buffer, 512, { ctx, _, _, _, _, report, length in
            let me = Unmanaged<MouseController>.fromOpaque(ctx!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { me.received(bytes) }
        }, ctx)
        snapshot.pollingHz = config.pollingHz
        snapshot.stage = config.activeStage
        snapshot.dpi = config.activeDPI
    }

    private func detach(_ dev: IOHIDDevice) {
        guard dev == device else { return }
        device = nil
        dongleConnected = false
        snapshot.connected = false
        snapshot.link = DeviceLink.none
        if let w = ackWaiter { ackWaiter = nil; w.cont.resume(throwing: HeadsetError.notConnected) }
        publish()
    }

    private func received(_ bytes: [UInt8]) {
        guard let event = AttackShark.parse(bytes) else { return }
        switch event {
        case .heartbeat(let battery, let online):
            if online { lastHeartbeat = .now }
            let link: DeviceLink = online ? wiredLink : snapshot.link == .bluetooth ? .bluetooth : .none
            let changed = (online && snapshot.battery != battery) || snapshot.link != link
            snapshot.link = link
            snapshot.connected = link != .none
            if online { snapshot.battery = battery }
            if changed { publish() }
        case .stageButton(let stage):
            // Botão de DPI físico no mouse.
            if config.stages.indices.contains(stage) {
                config.activeStage = stage
                snapshot.stage = stage
                snapshot.dpi = config.activeDPI
                publish()
            }
        case .ack(let id):
            if let w = ackWaiter, w.id == id { ackWaiter = nil; w.cont.resume() }
        }
    }

    /// O dongle às vezes não confirma (visto com 0x05): tenta até 3 vezes.
    private func send(_ report: [UInt8]) async throws {
        var lastError: Error = HeadsetError.noReply(report[0])
        for _ in 0..<3 {
            do { return try await sendOnce(report) }
            catch HeadsetError.noReply(let id) { lastError = HeadsetError.noReply(id) }
        }
        throw lastError
    }

    /// Envia sem esperar ACK (partes intermediárias do macro).
    private func sendRaw(_ report: [UInt8]) async throws {
        guard let dev = device else { throw HeadsetError.notConnected }
        let rc = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, CFIndex(report[0]), $0.baseAddress!, $0.count)
        }
        if rc != kIOReturnSuccess { throw HeadsetError.io(rc) }
        try? await Task.sleep(for: .milliseconds(30))
    }

    private func sendOnce(_ report: [UInt8]) async throws {
        guard let dev = device else { throw HeadsetError.notConnected }
        let id = report[0]
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ackWaiter = (id, cont)
            let rc = report.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, CFIndex(id), $0.baseAddress!, $0.count)
            }
            if rc != kIOReturnSuccess {
                ackWaiter = nil
                cont.resume(throwing: HeadsetError.io(rc))
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                if let w = self.ackWaiter, w.id == id {
                    self.ackWaiter = nil
                    w.cont.resume(throwing: HeadsetError.noReply(id))
                }
            }
        }
    }

    private enum Part { case config, lighting, polling, buttons }

    /// Enfileira escritas (uma de cada vez, cada uma esperando seu ACK).
    private func write(_ parts: [Part]) {
        let previous = writeTail
        writeTail = Task {
            await previous?.value
            busy = true
            defer { busy = false }
            do {
                for part in parts {
                    switch part {
                    case .config: try await send(AttackShark.configReport(config))
                    case .lighting: try await send(AttackShark.lightingReport(config))
                    case .polling: try await send(AttackShark.pollingReport(config.pollingHz))
                    case .buttons:
                        // Macros primeiro (relatório 0x09 em 3 partes), depois o mapa de botões.
                        for (i, action) in config.buttonActions.enumerated() where action == .macro {
                            if let macro = config.macros?[i], !macro.keys.isEmpty {
                                for part in AttackShark.macroReports(macro, group: AttackShark.buttonGroups[i]) {
                                    try await sendRaw(part)
                                }
                            }
                        }
                        try await send(AttackShark.remapReport(config.buttonActions))
                    }
                }
                if parts.contains(.polling) && parts.contains(.config) && parts.contains(.lighting) { synced = true; UserDefaults.standard.set(true, forKey: Self.syncedKey) }
                lastError = nil
            } catch {
                lastError = "Mouse: \(error.localizedDescription)"
            }
            snapshot.pollingHz = config.pollingHz
            snapshot.stage = config.activeStage
            snapshot.dpi = config.activeDPI
            publish()
        }
    }

    // MARK: - Ações

    func sendAll() { write([.config, .lighting, .polling, .buttons]) }
    func applyButtons() { write([.buttons]) }
    /// DPI, cores, lift-off, angle, ripple. Reenvia a iluminação para o LED repintar.
    func applyConfig() { write([.config, .lighting]) }
    func applyLighting() { write([.lighting]) }

    func setStage(_ i: Int) {
        guard config.stages.indices.contains(i), config.stages[i].enabled else { return }
        config.activeStage = i
        applyConfig()
    }

    func setPolling(_ hz: Int) {
        config.pollingHz = hz
        write([.polling])
    }

    func resetToFactory() {
        config = .factory
        sendAll()
    }

    private func publish() {
        snapshot.updated = .now
        snapshot.stageDPIs = config.stages.map { $0.enabled ? $0.dpi : nil }
        snapshot.synced = synced
        snapshot.stage = config.activeStage
        snapshot.dpi = config.activeDPI
        snapshot.pollingHz = config.pollingHz
        SharedStore.save(snapshot, as: "mouse")
        WidgetCenter.shared.reloadAllTimelines()
        if #available(macOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
    }

    func nextStage() {
        let enabled = config.stages.indices.filter { config.stages[$0].enabled }
        guard !enabled.isEmpty else { return }
        let pos = enabled.firstIndex(of: config.activeStage) ?? -1
        setStage(enabled[(pos + 1) % enabled.count])
    }
}
