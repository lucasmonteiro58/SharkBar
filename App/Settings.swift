import Carbon.HIToolbox
import Foundation

/// Quais aparelhos aparecem na barra.
enum MenuBarStyle: String, Codable, CaseIterable, Identifiable {
    case full, iconsOnly, headsetOnly, mouseOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .full, .iconsOnly: "Fone e mouse"
        case .headsetOnly: "Só o fone"
        case .mouseOnly: "Só o mouse"
        }
    }
    /// `.iconsOnly` é legado (= os dois, sem porcentagem).
    static var choices: [MenuBarStyle] { [.full, .headsetOnly, .mouseOnly] }
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

/// Como a bateria aparece: sempre um símbolo só por aparelho, com o nível embutido.
enum BatteryStyle: String, CaseIterable, Identifiable, Codable {
    case ring, fill, pill, number
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ring: "Anel"
        case .fill: "Ícone preenchido"
        case .pill: "Pílula"
        case .number: "Ícone + número"
        }
    }
    var subtitle: String {
        switch self {
        case .ring: "O ícone fica dentro de um anel que fecha conforme a carga"
        case .fill: "O próprio desenho do aparelho enche de baixo para cima"
        case .pill: "Cápsula preenchida pela carga, com o ícone dentro"
        case .number: "Ícone e a porcentagem ao lado"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Estilos antigos: "capsule" (pilha) e "bars" viram pílula e anel.
        self = BatteryStyle(rawValue: raw) ?? (raw == "capsule" ? .pill : .ring)
    }
}

enum BarColorMode: String, Codable, CaseIterable, Identifiable {
    case monochrome, byLevel, perDevice, accent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .monochrome: "Monocromático"
        case .byLevel: "Pelo nível"
        case .perDevice: "Por aparelho"
        case .accent: "Verde-água"
        }
    }
}

/// O que vai dentro do símbolo de cada aparelho.
enum BarIconMode: String, CaseIterable, Identifiable, Codable {
    case device, initials
    var id: String { rawValue }
    var title: String { self == .device ? "Desenho do aparelho" : "Siglas (BS / X6)" }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = raw == "initials" ? .initials : .device   // "fin"/"none" antigos → desenho
    }
}

/// Aparência do item na barra de menu.
struct MenuBarLook: Codable, Equatable {
    var battery: BatteryStyle = .ring
    var color: BarColorMode = .monochrome
    var icons: BarIconMode = .device
    var headsetSymbol = "headphones"
    var mouseSymbol = "computermouse"
    var headsetColor = RGB(r: 64, g: 158, b: 255)
    var mouseColor = RGB(r: 158, g: 115, b: 255)
    /// Porcentagem ao lado do símbolo (no estilo "Ícone + número" ela sempre aparece).
    var showPercent = false
    /// Barbatana do SharkBar no começo do item.
    var showFin = false

    static let headsetSymbols = ["headphones", "airpods.max", "beats.headphones", "headphones.dots", "ear", "waveform", "music.note"]
    static let mouseSymbols = ["computermouse", "computermouse.fill", "magicmouse", "magicmouse.fill", "cursorarrow", "cursorarrow.rays", "scope"]

    init() {}

    /// Tolerante a campos faltando ou de versões anteriores (para não zerar os ajustes).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MenuBarLook()
        battery = (try? c.decodeIfPresent(BatteryStyle.self, forKey: .battery)) ?? d.battery
        color = (try? c.decodeIfPresent(BarColorMode.self, forKey: .color)) ?? d.color
        let rawIcons = (try? c.decodeIfPresent(String.self, forKey: .icons)) ?? "device"
        icons = rawIcons == "initials" ? .initials : .device
        headsetSymbol = (try? c.decodeIfPresent(String.self, forKey: .headsetSymbol)) ?? d.headsetSymbol
        mouseSymbol = (try? c.decodeIfPresent(String.self, forKey: .mouseSymbol)) ?? d.mouseSymbol
        headsetColor = (try? c.decodeIfPresent(RGB.self, forKey: .headsetColor)) ?? d.headsetColor
        mouseColor = (try? c.decodeIfPresent(RGB.self, forKey: .mouseColor)) ?? d.mouseColor
        showPercent = (try? c.decodeIfPresent(Bool.self, forKey: .showPercent)) ?? d.showPercent
        showFin = (try? c.decodeIfPresent(Bool.self, forKey: .showFin)) ?? (rawIcons == "fin")
    }
}

struct SettingsData: Codable, Equatable {
    var lowBatteryAlert = true
    var lowBatteryThreshold = 20
    var chargedAlert = true
    var showHUD = true
    var muteSync = false
    var menuBarStyle: MenuBarStyle = .full
    /// Opcional para continuar lendo ajustes salvos por versões anteriores.
    var menuBarLook: MenuBarLook?
    var look: MenuBarLook {
        get { menuBarLook ?? MenuBarLook() }
        set { menuBarLook = newValue }
    }
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
