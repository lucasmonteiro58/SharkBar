import SwiftUI

@main
struct SharkBarApp: App {
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
                .tint(Theme.accent)
        } label: {
            MenuBarLabel(headset: model.headset.snapshot, mouse: model.mouse.snapshot,
                         style: model.settings.data.menuBarStyle, look: model.settings.data.look)
        }
        .menuBarExtraStyle(.window)

        Window(Brand.name, id: "main") {
            MainWindowHost()
                .environmentObject(model)
                .tint(Theme.accent)
                .frame(minWidth: 820, minHeight: 600)
        }
        .handlesExternalEvents(matching: ["open"])
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 920, height: 680)
    }
}


/// Descarta a hierarquia da janela ao fechá-la. O SwiftUI mantém a janela `Window` fechada
/// na memória com tudo dentro (~75 MB); assim ela volta a ocupar quase nada até ser reaberta.
private struct MainWindowHost: View {
    @State private var alive = true

    var body: some View {
        Group {
            if alive { MainWindow() } else { Color.clear }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { n in
            if Self.isMain(n.object) { alive = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { n in
            if Self.isMain(n.object), !alive { alive = true }
        }
        .onOpenURL { url in
            if let p = Page(rawValue: url.lastPathComponent) { NavigationState.shared.page = p }
            alive = true
        }
    }

    private static func isMain(_ object: Any?) -> Bool {
        (object as? NSWindow)?.identifier?.rawValue.hasPrefix("main") == true
    }
}
