import AppKit
import Carbon.HIToolbox
import CoreAudio
import SwiftUI
import UserNotifications

// MARK: - Notificações

@MainActor
final class Notifier {
    private var lowSent: Set<DeviceKind> = []
    private var chargedSent = false

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func post(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Avisa uma vez ao cruzar o limite; rearma ao carregar ou subir 5% acima.
    func checkLow(_ device: DeviceKind, level: Int?, charging: Bool, settings: SettingsData) {
        guard settings.lowBatteryAlert, let level else { return }
        if charging || level > settings.lowBatteryThreshold + 5 { lowSent.remove(device); return }
        if level <= settings.lowBatteryThreshold, !lowSent.contains(device) {
            lowSent.insert(device)
            post("Bateria fraca — \(device.title)", "Restam \(level)%. Hora de carregar.")
        }
    }

    func checkCharged(level: Int?, charging: Bool, settings: SettingsData) {
        guard settings.chargedAlert, let level else { return }
        if !charging || level < 95 { chargedSent = false; return }
        if level >= 100, !chargedSent {
            chargedSent = true
            post("BlackShark V3 Pro carregado", "A bateria chegou a 100%.")
        }
    }
}

// MARK: - HUD na tela (estilo volume do macOS)

@MainActor
final class HUD {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(symbol: String, title: String, detail: String? = nil) {
        let view = HUDView(symbol: symbol, title: title, detail: detail)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 220, height: 150)

        let p = panel ?? {
            let p = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            return p
        }()
        panel = p
        p.contentView = host
        if let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(CGPoint(x: screen.midX - 110, y: screen.minY + 120))
        }
        p.alphaValue = 1
        p.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; p.animator().alphaValue = 0 }, completionHandler: nil)
        }
    }
}

private struct HUDView: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            Text(title).font(.headline)
            if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(width: 200, height: 136)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(7)
    }
}

// MARK: - Mute sincronizado (entrada de áudio do Mac)

enum SystemMic {
    private static func defaultInput() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    /// Muta/desmuta a entrada padrão. Usa a propriedade de mute; se o aparelho não tiver,
    /// zera/restaura o volume de entrada.
    nonisolated(unsafe) private static var savedVolume: Float32?

    static func setMuted(_ muted: Bool) {
        guard let dev = defaultInput() else { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(dev, &addr), AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue {
            var v: UInt32 = muted ? 1 : 0
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
            return
        }
        addr.mSelector = kAudioDevicePropertyVolumeScalar
        guard AudioObjectHasProperty(dev, &addr) else { return }
        var size = UInt32(MemoryLayout<Float32>.size)
        if muted {
            var cur: Float32 = 0
            AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &cur)
            if cur > 0 { savedVolume = cur }
            var zero: Float32 = 0
            AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &zero)
        } else {
            var v = savedVolume ?? 0.75
            AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &v)
        }
    }
}

// MARK: - Atalhos globais (Carbon, sem precisar de permissão de Acessibilidade)

@MainActor
final class HotkeyCenter {
    var onAction: ((HotkeyAction) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: HotkeyAction] = [:]
    nonisolated(unsafe) private static weak var current: HotkeyCenter?
    private var handlerInstalled = false

    func register(_ hotkeys: [HotkeyAction: Hotkey]) {
        Self.current = self
        installHandler()
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll(); actions.removeAll()
        for (i, (action, key)) in hotkeys.sorted(by: { $0.key.rawValue < $1.key.rawValue }).enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x53_48_52_4B), id: UInt32(i + 1)) // 'SHRK'
            if RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
                actions[UInt32(i + 1)] = action
            }
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let c = HotkeyCenter.current, let a = c.actions[id] { c.onAction?(a) }
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Converte um NSEvent de tecla em Hotkey (para o gravador de atalhos).
    static func hotkey(from event: NSEvent) -> Hotkey? {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !f.intersection([.command, .control, .option]).isEmpty else { return nil }
        var mods: UInt32 = 0
        var text = ""
        if f.contains(.control) { mods |= UInt32(controlKey); text += "⌃" }
        if f.contains(.option) { mods |= UInt32(optionKey); text += "⌥" }
        if f.contains(.shift) { mods |= UInt32(shiftKey); text += "⇧" }
        if f.contains(.command) { mods |= UInt32(cmdKey); text += "⌘" }
        let key = (event.charactersIgnoringModifiers ?? "").uppercased()
        text += key.isEmpty ? "#\(event.keyCode)" : key
        return Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods, display: text)
    }
}
