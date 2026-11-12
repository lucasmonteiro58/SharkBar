import AppIntents
import WidgetKit

/// Todas as intents só mandam um comando ao app (que tem acesso ao USB) e esperam
/// um pouco para o próximo recarregamento do widget já mostrar o estado novo.
private func send(_ cmd: FoneCommand) async {
    cmd.post()
    try? await Task.sleep(for: .milliseconds(450))
}

enum AudioModeOption: String, AppEnum {
    case off, anc, ambient

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Modo de áudio"
    static let caseDisplayRepresentations: [AudioModeOption: DisplayRepresentation] = [
        .off: "Desligado", .anc: "Cancelamento de ruído", .ambient: "Ambiente",
    ]

    var command: FoneCommand {
        switch self {
        case .off: .ancOff
        case .anc: .ancOn
        case .ambient: .ancAmbient
        }
    }
}

struct SetAudioModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Definir modo de áudio do fone"
    @Parameter(title: "Modo") var mode: AudioModeOption

    init() { mode = .anc }
    init(_ mode: AudioModeOption) { self.mode = mode }

    func perform() async throws -> some IntentResult {
        await send(mode.command)
        return .result()
    }
}

struct CycleAudioModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Alternar modo de áudio do fone"
    func perform() async throws -> some IntentResult {
        await send(.ancCycle)
        return .result()
    }
}

/// Liga/desliga o cancelamento de ruído (controle tipo interruptor).
struct ToggleNoiseCancellingIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Cancelamento de ruído"
    @Parameter(title: "Ligado") var value: Bool
    init() { value = false }

    func perform() async throws -> some IntentResult {
        await send(value ? .ancOn : .ancOff)
        return .result()
    }
}

/// Liga/desliga o modo ambiente (controle tipo interruptor).
struct ToggleAmbientIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Modo ambiente"
    @Parameter(title: "Ligado") var value: Bool
    init() { value = false }

    func perform() async throws -> some IntentResult {
        await send(value ? .ancAmbient : .ancOff)
        return .result()
    }
}

struct SetDPIStageIntent: AppIntent {
    static let title: LocalizedStringResource = "Escolher estágio de DPI do mouse"
    @Parameter(title: "Estágio (1–6)") var stage: Int

    init() { stage = 1 }
    init(index: Int) { stage = index + 1 }

    func perform() async throws -> some IntentResult {
        if let cmd = FoneCommand.stage(stage - 1) { await send(cmd) }
        return .result()
    }
}

struct NextDPIStageIntent: AppIntent {
    static let title: LocalizedStringResource = "Próximo DPI do mouse"
    func perform() async throws -> some IntentResult {
        await send(.mouseNextStage)
        return .result()
    }
}

struct SetPollingIntent: AppIntent {
    static let title: LocalizedStringResource = "Definir polling rate do mouse"
    @Parameter(title: "Hz") var hz: Int

    init() { hz = 1000 }
    init(_ hz: Int) { self.hz = hz }

    func perform() async throws -> some IntentResult {
        if let cmd = FoneCommand.polling(hz) { await send(cmd) }
        return .result()
    }
}

struct RefreshDevicesIntent: AppIntent {
    static let title: LocalizedStringResource = "Atualizar fone e mouse"
    func perform() async throws -> some IntentResult {
        await send(.refresh)
        return .result()
    }
}
