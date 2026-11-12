import Foundation
import IOKit.hid

enum HeadsetError: LocalizedError {
    case notConnected
    case noReply(UInt8)
    case device(UInt8, BlackShark.Status?)
    case io(IOReturn)
    case badAnswer(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: "Dongle/fone não encontrado"
        case .noReply(let c): String(format: "O fone não respondeu (0x%02X) — está ligado?", c)
        case .device(let c, let s): String(format: "O fone recusou 0x%02X (status %@)", c, String(describing: s))
        case .io(let r): String(format: "Erro de HID 0x%08X", r)
        case .badAnswer(let s): "Resposta inesperada: \(s)"
        }
    }
}

/// Conversa com o dongle via IOHIDManager no run loop principal.
/// Comandos são serializados: um por vez, aguardando a resposta correspondente.
@MainActor
final class HIDTransport {
    var onConnectionChange: ((Bool) -> Void)?
    /// Relatórios válidos que chegam sem ninguém esperando (ex.: botão no fone).
    var onUnsolicited: ((BlackShark.Reply) -> Void)?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)

    private var pending: (id: Int, command: UInt8, continuation: CheckedContinuation<[UInt8], Error>)?
    private var nextID = 0
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var isConnected: Bool { device != nil }
    var productID: Int? {
        device.flatMap { IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? Int }
    }

    func start() {
        let matches = BlackShark.productIDs.map {
            [kIOHIDVendorIDKey: BlackShark.vendorID, kIOHIDProductIDKey: $0] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.attach(dev) }
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx!).takeUnretainedValue()
            MainActor.assumeIsolated { me.detach(dev) }
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ dev: IOHIDDevice) {
        // O canal de comandos é a interface com relatórios de saída de 64 bytes.
        let maxOut = IOHIDDeviceGetProperty(dev, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
        guard maxOut >= BlackShark.reportSize, device == nil else { return }
        device = dev
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 256, { ctx, result, _, _, _, report, length in
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { me.received(bytes) }
        }, ctx)
        onConnectionChange?(true)
    }

    private func detach(_ dev: IOHIDDevice) {
        guard dev == device else { return }
        device = nil
        if let p = pending { pending = nil; p.continuation.resume(throwing: HeadsetError.notConnected) }
        onConnectionChange?(false)
    }

    private func received(_ bytes: [UInt8]) {
        guard let reply = BlackShark.parse(bytes) else { return }
        if let p = pending, p.command == reply.command {
            switch reply.status {
            case .success:
                pending = nil
                p.continuation.resume(returning: reply.data)
            case .busy, .new:
                break // aguarda a resposta definitiva
            default:
                pending = nil
                p.continuation.resume(throwing: HeadsetError.device(reply.command, reply.status))
            }
        } else if reply.status == .success {
            onUnsolicited?(reply)
        }
    }

    // MARK: - Serialização

    private func lock() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func unlock() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    /// Envia um comando e devolve os bytes de dados da resposta.
    func transact(_ command: UInt8, _ args: [UInt8] = [], timeout: Duration = .milliseconds(600)) async throws -> [UInt8] {
        await lock()
        defer { unlock() }
        guard let dev = device else { throw HeadsetError.notConnected }
        // O Synapse espaça comandos em pelo menos 10 ms.
        try? await Task.sleep(for: .milliseconds(10))

        return try await withCheckedThrowingContinuation { cont in
            nextID += 1
            let id = nextID
            pending = (id, command, cont)
            let packet = BlackShark.request(command, args)
            let r = packet.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, CFIndex(BlackShark.reportID), $0.baseAddress!, $0.count)
            }
            if r != kIOReturnSuccess {
                pending = nil
                cont.resume(throwing: HeadsetError.io(r))
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if let p = self.pending, p.id == id {
                    self.pending = nil
                    p.continuation.resume(throwing: HeadsetError.noReply(command))
                }
            }
        }
    }
}
