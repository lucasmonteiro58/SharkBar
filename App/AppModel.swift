import AppKit
import Combine
import SwiftUI

/// Liga aparelhos, perfis, avisos, HUD, atalhos e automações.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let headset: HeadsetController
    let mouse: MouseController
    let settings: AppSettings
    let profiles: ProfileStore
    let eqLibrary: EQLibrary
    let history: BatteryHistory
    let loginItem: LoginItem

    private let notifier = Notifier()
    private let hud = HUD()
    private let hotkeys = HotkeyCenter()
    private let appWatcher = AppWatcher()
    private var bag: Set<AnyCancellable> = []
    private var lastHeadset = HeadsetSnapshot()
    private var lastMouse = MouseSnapshot()
    /// Perfil aplicado por regra de app (para voltar ao sair).
    private var ruleApplied = false

    /// Abre a janela principal (sharkbar://open — o SwiftUI cria a janela se ainda não existir).
    func openWindow(_ page: Page? = nil) {
        if let page { NavigationState.shared.page = page }
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.canBecomeMain }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            NSWorkspace.shared.open(URL(string: "sharkbar://open")!)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private init() {
        LegacyMigration.run()
        headset = HeadsetController()
        mouse = MouseController()
        settings = AppSettings()
        profiles = ProfileStore()
        eqLibrary = EQLibrary()
        history = BatteryHistory()
        loginItem = LoginItem()

        notifier.requestPermission()

        // O estado é atualizado campo a campo (estágio, depois DPI…); sem esperar ele assentar,
        // o HUD mostrava o valor anterior. 120 ms depois da última mudança, já está completo.
        headset.$snapshot.dropFirst().debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] s in self?.headsetChanged(s) }.store(in: &bag)
        mouse.$snapshot.dropFirst().debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] s in self?.mouseChanged(s) }.store(in: &bag)

        hotkeys.onAction = { [weak self] in self?.perform($0) }
        hotkeys.register(settings.data.hotkeys)
        settings.$data.map(\.hotkeys).removeDuplicates().dropFirst()
            .sink { [weak self] in self?.hotkeys.register($0) }.store(in: &bag)

        appWatcher.onApp = { [weak self] in self?.appActivated($0) }
        appWatcher.start()

        // Repassa mudanças dos filhos para quem observa o AppModel.
        for pub in [headset.objectWillChange, mouse.objectWillChange, settings.objectWillChange,
                    profiles.objectWillChange, history.objectWillChange] {
            pub.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
    }

    // MARK: - Reações a mudanças

    private func headsetChanged(_ s: HeadsetSnapshot) {
        let old = lastHeadset
        lastHeadset = s
        let set = settings.data
        if s.connected && s.link != .bluetooth {
            history.record(.headset, level: s.battery, charging: s.charging)
        }
        notifier.checkLow(.headset, level: s.connected ? s.battery : nil, charging: s.charging, settings: set)
        notifier.checkCharged(level: s.battery, charging: s.charging, settings: set)

        if let m = s.micMuted, let was = old.micMuted, m != was {
            if set.muteSync { SystemMic.setMuted(m) }
            if set.showHUD {
                hud.show(symbol: m ? "mic.slash.fill" : "mic.fill", title: m ? "Microfone mutado" : "Microfone ativo")
            }
        } else if let m = s.micMuted, old.micMuted == nil, set.muteSync {
            SystemMic.setMuted(m)
        }
        if set.showHUD, let mode = s.ancMode, let was = old.ancMode, mode != was {
            hud.show(symbol: mode.symbol, title: mode.title, detail: mode == .off ? nil : "Nível \(s.ancLevel ?? 0)")
        }
    }

    private func mouseChanged(_ m: MouseSnapshot) {
        let old = lastMouse
        lastMouse = m
        if m.connected && m.link == .dongle {
            history.record(.mouse, level: m.battery, charging: false)
        }
        notifier.checkLow(.mouse, level: m.connected ? m.battery : nil, charging: false, settings: settings.data)
        if settings.data.showHUD, let st = m.stage, let was = old.stage, st != was, let dpi = m.dpi {
            hud.show(symbol: "scope", title: "\(dpi) DPI", detail: "Estágio \(st + 1)")
        }
    }

    // MARK: - Ações

    func perform(_ action: HotkeyAction) {
        switch action {
        case .cycleAudioMode: headset.cycleANC()
        case .toggleNoiseCancelling: headset.setANC(headset.snapshot.ancMode == .anc ? .off : .anc)
        case .nextDPI: if mouse.synced { mouse.nextStage() }
        case .nextProfile: nextProfile()
        case .openWindow: openWindow()
        }
    }

    func apply(_ p: Profile, announce: Bool = true) {
        if let mode = p.ancMode { headset.setANC(mode, level: p.ancLevel) }
        if let s = p.sidetone { headset.setSidetone(s) }
        if let e = p.eqSlot { headset.activateSlot(e) }
        if let st = p.dpiStage, mouse.synced { mouse.setStage(st) }
        if let hz = p.pollingHz { mouse.setPolling(hz) }
        profiles.data.activeID = p.id
        if announce && settings.data.showHUD { hud.show(symbol: p.symbol, title: p.name, detail: "Perfil aplicado") }
    }

    func nextProfile() {
        if let p = profiles.next(after: profiles.data.activeID) { apply(p) }
    }

    /// Perfil com o estado atual dos aparelhos.
    func profileFromCurrent(name: String) -> Profile {
        let s = headset.snapshot
        return Profile(name: name, symbol: "star",
                       ancMode: s.ancMode, ancLevel: s.ancLevel,
                       sidetone: s.connected ? headset.sidetone : nil,
                       eqSlot: headset.eqSlots.first(where: \.active)?.id,
                       dpiStage: mouse.config.activeStage, pollingHz: mouse.config.pollingHz)
    }

    private func appActivated(_ bundleID: String) {
        guard settings.data.perAppProfiles, bundleID != Bundle.main.bundleIdentifier else { return }
        if let rule = profiles.data.rules.first(where: { $0.bundleID == bundleID }),
           let p = profiles.profiles.first(where: { $0.id == rule.profileID }) {
            if profiles.data.activeID != p.id { apply(p) }
            ruleApplied = true
        } else if ruleApplied {
            ruleApplied = false
            if let fid = profiles.data.fallbackID, let p = profiles.profiles.first(where: { $0.id == fid }),
               profiles.data.activeID != p.id {
                apply(p)
            }
        }
    }
}
