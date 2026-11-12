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
            MainWindow()
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

