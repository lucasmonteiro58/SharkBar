import AppIntents
import Foundation

// Ações do app Atalhos / Siri. Rodam no processo do SharkBar, que fala direto com o USB.

enum ShortcutAudioMode: String, AppEnum {
    case off, anc, ambient
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Modo de áudio"
    static let caseDisplayRepresentations: [ShortcutAudioMode: DisplayRepresentation] = [
        .off: "Desligado", .anc: "Cancelamento de ruído", .ambient: "Ambiente",
    ]
    var mode: AncMode { self == .off ? .off : self == .anc ? .anc : .ambient }
}

struct SetHeadsetModeShortcut: AppIntent {
    static let title: LocalizedStringResource = "Definir modo de áudio do BlackShark"
    static let description = IntentDescription("Liga o cancelamento de ruído, o modo ambiente ou desliga os dois.")
    @Parameter(title: "Modo") var mode: ShortcutAudioMode
    @Parameter(title: "Intensidade (1–10)", inclusiveRange: (1, 10)) var level: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Definir modo de áudio para \(\.$mode)") { \.$level }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.shared.headset.setANC(mode.mode, level: level)
        return .result(dialog: "Modo de áudio: \(mode.mode.title)")
    }
}

struct NextDPIShortcut: AppIntent {
    static let title: LocalizedStringResource = "Próximo DPI do Attack Shark"
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = AppModel.shared.mouse
        guard m.synced else { return .result(dialog: "Configure o mouse no SharkBar primeiro.") }
        m.nextStage()
        return .result(dialog: "\(m.config.activeDPI ?? 0) DPI")
    }
}

struct SetDPIStageShortcut: AppIntent {
    static let title: LocalizedStringResource = "Escolher estágio de DPI do Attack Shark"
    @Parameter(title: "Estágio", inclusiveRange: (1, 6)) var stage: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let m = AppModel.shared.mouse
        guard m.synced else { return .result(dialog: "Configure o mouse no SharkBar primeiro.") }
        m.setStage(stage - 1)
        return .result(dialog: "Estágio \(stage): \(m.config.stages[safe: stage - 1]?.dpi ?? 0) DPI")
    }
}

struct SetPollingShortcut: AppIntent {
    static let title: LocalizedStringResource = "Definir polling rate do Attack Shark"
    @Parameter(title: "Hz", default: 1000) var hz: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        let valid = AttackShark.pollingRates.min { abs($0 - hz) < abs($1 - hz) } ?? 1000
        AppModel.shared.mouse.setPolling(valid)
        return .result()
    }
}

struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Perfil do SharkBar"
    static let defaultQuery = ProfileQuery()
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProfileQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        AppModel.shared.profiles.profiles.filter { identifiers.contains($0.id) }.map { ProfileEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ProfileEntity] {
        AppModel.shared.profiles.profiles.map { ProfileEntity(id: $0.id, name: $0.name) }
    }
}

struct ApplyProfileShortcut: AppIntent {
    static let title: LocalizedStringResource = "Aplicar perfil do SharkBar"
    @Parameter(title: "Perfil") var profile: ProfileEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let p = AppModel.shared.profiles.profiles.first(where: { $0.id == profile.id }) else {
            return .result(dialog: "Perfil não encontrado.")
        }
        AppModel.shared.apply(p)
        return .result(dialog: "Perfil \(p.name) aplicado.")
    }
}

struct BatteryShortcut: AppIntent {
    static let title: LocalizedStringResource = "Bateria do fone e do mouse"
    static let description = IntentDescription("Diz a bateria do BlackShark V3 Pro e do Attack Shark X6.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let h = AppModel.shared.headset.snapshot, m = AppModel.shared.mouse.snapshot
        let hs = h.connected ? h.battery.map { "fone \($0)%" + (h.charging ? " carregando" : "") } ?? "fone conectado" : "fone desligado"
        let msg = m.connected ? m.battery.map { "mouse \($0)%" } ?? "mouse conectado" : "mouse desligado"
        let text = "Bateria: \(hs), \(msg)."
        return .result(value: text, dialog: "\(text)")
    }
}

struct SharkBarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BatteryShortcut(), phrases: ["Bateria no \(.applicationName)", "Como está a bateria no \(.applicationName)"],
                    shortTitle: "Bateria", systemImageName: "battery.75percent")
        AppShortcut(intent: SetHeadsetModeShortcut(), phrases: ["Mudar modo de áudio no \(.applicationName)"],
                    shortTitle: "Modo de áudio", systemImageName: "ear")
        AppShortcut(intent: ApplyProfileShortcut(), phrases: ["Aplicar perfil no \(.applicationName)"],
                    shortTitle: "Aplicar perfil", systemImageName: "square.stack.3d.up")
        AppShortcut(intent: NextDPIShortcut(), phrases: ["Próximo DPI no \(.applicationName)"],
                    shortTitle: "Próximo DPI", systemImageName: "scope")
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
