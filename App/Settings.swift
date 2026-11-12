import Carbon.HIToolbox
import Foundation

enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case full, iconsOnly, headsetOnly, mouseOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .full: "Ícones e porcentagens"
        case .iconsOnly: "Só ícones"
        case .headsetOnly: "Só o fone"
        case .mouseOnly: "Só o mouse"
        }
    }
}

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case cycleAudioMode, toggleNoiseCancelling, nextDPI, nextProfile, openWindow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cycleAudioMode: "Alternar modo de áudio (Off → ANC → Ambiente)"
        case .toggleNoiseCancelling: "Ligar/desligar cancelamento de ruído"
        case .nextDPI: "Próximo estágio de DPI"
        case .nextProfile: "Próximo perfil"
        case .openWindow: "Abrir o SharkBar"
        }
    }
}

/// Atalho global (código de tecla + modificadores no formato Carbon).
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}

struct SettingsData: Codable, Equatable {
    var lowBatteryAlert = true
    var lowBatteryThreshold = 20
    var chargedAlert = true
    var showHUD = true
    var muteSync = false
    var menuBarStyle: MenuBarStyle = .full
    var perAppProfiles = true
    var hotkeys: [HotkeyAction: Hotkey] = [
        .cycleAudioMode: Hotkey(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥A"),
        .nextDPI: Hotkey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥D"),
        .nextProfile: Hotkey(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥P"),
    ]
}

/// Preferências do usuário, salvas em UserDefaults como JSON.
@MainActor
final class AppSettings: ObservableObject {
    @Published var data: SettingsData { didSet { save() } }
    private static let key = "settings.v1"

    init() {
        data = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(SettingsData.self, from: $0) } ?? SettingsData()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { UserDefaults.standard.set(d, forKey: Self.key) }
    }
}

/// Copia as configurações da época em que o app se chamava "Fone".
enum LegacyMigration {
    static func run() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migrated.fone"), let old = UserDefaults(suiteName: Brand.legacyBundleID) else { return }
        for key in ["mouseConfig.v1", "mouseConfig.synced"] {
            if let v = old.object(forKey: key), d.object(forKey: key) == nil { d.set(v, forKey: key) }
        }
        d.set(true, forKey: "migrated.fone")
    }
}
