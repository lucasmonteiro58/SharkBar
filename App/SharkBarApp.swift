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
            MenuBarLabel(headset: model.headset.snapshot, mouse: model.mouse.snapshot, style: model.settings.data.menuBarStyle)
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

/// Ícone da barra de menu desenhado como imagem template (acompanha claro/escuro):
/// 🎧 84% ⚡ 🎙̸   🖱 100%  — esmaecido quando desligado, "BT" quando por Bluetooth.
struct MenuBarLabel: View {
    let headset: HeadsetSnapshot
    let mouse: MouseSnapshot
    let style: MenuBarStyle

    var body: some View {
        Image(nsImage: render())
    }

    @MainActor private func render() -> NSImage {
        let showPercent = style != .iconsOnly
        let content = HStack(spacing: 4) {
            if style != .mouseOnly { headsetPart(showPercent) }
            if style == .full || style == .iconsOnly { Spacer().frame(width: 2) }
            if style != .headsetOnly { mousePart(showPercent) }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(.black)
        .padding(.vertical, 1)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }

    @ViewBuilder private func headsetPart(_ percent: Bool) -> some View {
        let s = headset
        if s.connected {
            HStack(spacing: 2) {
                Image(systemName: "headphones")
                if percent, let b = s.battery { Text("\(b)%") }
                if s.charging { Image(systemName: "bolt.fill").font(.system(size: 9)) }
                if s.micMuted == true { Image(systemName: "mic.slash.fill").font(.system(size: 10)) }
                if s.link == .bluetooth { Text("BT").font(.system(size: 8, weight: .bold)) }
            }
        } else {
            Image(systemName: "headphones.slash").opacity(0.45)
        }
    }

    @ViewBuilder private func mousePart(_ percent: Bool) -> some View {
        let m = mouse
        if m.connected {
            HStack(spacing: 2) {
                Image(systemName: "computermouse")
                if percent, let b = m.battery { Text("\(b)%") }
                if m.link == .bluetooth { Text("BT").font(.system(size: 8, weight: .bold)) }
            }
        } else {
            Image(systemName: "computermouse").opacity(0.35)
        }
    }
}
