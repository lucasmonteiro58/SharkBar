import Foundation

/// Executa os comandos vindos dos widgets e da Central de Controle.
@MainActor
final class CommandRouter {
    static let shared = CommandRouter()
    weak var headset: HeadsetController?
    weak var mouse: MouseController?

    private init() {
        CommandListener.start { cmd in
            MainActor.assumeIsolated { CommandRouter.shared.handle(cmd) }
        }
    }

    private func handle(_ cmd: FoneCommand) {
        switch cmd {
        case .ancOff: headset?.setANC(.off)
        case .ancOn: headset?.setANC(.anc)
        case .ancAmbient: headset?.setANC(.ambient)
        case .ancCycle: headset?.cycleANC()
        case .refresh:
            Task { await headset?.refreshStatus() }
        case .mouseNextStage:
            if mouse?.synced == true { mouse?.nextStage() }
        case .mouseStage0, .mouseStage1, .mouseStage2, .mouseStage3, .mouseStage4, .mouseStage5:
            // Sem o primeiro envio completo, trocar estágio sobrescreveria a configuração do mouse.
            if mouse?.synced == true, let i = Int(cmd.rawValue.split(separator: ".").last ?? "") { mouse?.setStage(i) }
        case .openWindow:
            AppModel.shared.openWindow()
        case .nextProfile:
            AppModel.shared.nextProfile()
        case .polling125, .polling250, .polling500, .polling1000:
            if let hz = Int(cmd.rawValue.split(separator: ".").last ?? "") { mouse?.setPolling(hz) }
        }
    }
}
