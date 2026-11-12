import Foundation

/// Comandos que widgets e controles (sandbox) mandam ao app, que é quem fala com o USB.
/// Vão por notificação Darwin — funciona de dentro da sandbox, mesmo com assinatura ad-hoc.
enum FoneCommand: String, CaseIterable {
    case ancOff = "anc.off"
    case ancOn = "anc.anc"
    case ancAmbient = "anc.ambient"
    case ancCycle = "anc.cycle"
    case mouseNextStage = "mouse.stage.next"
    case mouseStage0 = "mouse.stage.0", mouseStage1 = "mouse.stage.1", mouseStage2 = "mouse.stage.2"
    case mouseStage3 = "mouse.stage.3", mouseStage4 = "mouse.stage.4", mouseStage5 = "mouse.stage.5"
    case polling125 = "mouse.polling.125", polling250 = "mouse.polling.250"
    case polling500 = "mouse.polling.500", polling1000 = "mouse.polling.1000"
    case refresh = "refresh"
    case nextProfile = "profile.next"
    case openWindow = "window.open"

    static let prefix = Brand.bundleID + ".cmd."
    var notificationName: String { Self.prefix + rawValue }

    static func stage(_ i: Int) -> FoneCommand? { FoneCommand(rawValue: "mouse.stage.\(i)") }
    static func polling(_ hz: Int) -> FoneCommand? { FoneCommand(rawValue: "mouse.polling.\(hz)") }

    func post() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(notificationName as CFString), nil, nil, true)
    }
}

/// Lado do app: recebe os comandos.
enum CommandListener {
    nonisolated(unsafe) private static var handler: ((FoneCommand) -> Void)?

    static func start(_ handle: @escaping (FoneCommand) -> Void) {
        handler = handle
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for cmd in FoneCommand.allCases {
            CFNotificationCenterAddObserver(center, nil, { _, _, name, _, _ in
                guard let raw = name?.rawValue as String?,
                      let cmd = FoneCommand(rawValue: String(raw.dropFirst(FoneCommand.prefix.count))) else { return }
                DispatchQueue.main.async { CommandListener.handler?(cmd) }
            }, cmd.notificationName as CFString, nil, .deliverImmediately)
        }
    }
}
