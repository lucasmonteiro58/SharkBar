import SwiftUI

@main
struct FoneApp: App {
    @StateObject private var headset = HeadsetController()
    @StateObject private var mouse = MouseController()
    @StateObject private var loginItem = LoginItem()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(headset)
                .environmentObject(mouse)
                .environmentObject(loginItem)
        } label: {
            MenuBarLabel(snapshot: headset.snapshot, mouse: mouse.snapshot)
        }
        .menuBarExtraStyle(.window)

        Window("Fone & Mouse", id: "controls") {
            TabView {
                ControlsView()
                    .tabItem { Label("BlackShark V3 Pro", systemImage: "headphones") }
                MouseView()
                    .tabItem { Label("Attack Shark X6", systemImage: "computermouse") }
            }
            .environmentObject(headset)
            .environmentObject(mouse)
            .frame(minWidth: 580, minHeight: 640)
        }
        .windowResizability(.contentSize)
    }
}

/// Ícone da barra de menu desenhado como imagem template (adapta a claro/escuro):
/// 🎧 84% ⚡︎ 🎙̸   🖱 100%  — esmaecido quando desligado, "BT" quando por Bluetooth.
struct MenuBarLabel: View {
    let snapshot: HeadsetSnapshot
    let mouse: MouseSnapshot

    var body: some View {
        Image(nsImage: render())
    }

    @MainActor private func render() -> NSImage {
        let content = HStack(spacing: 4) {
            headset
            Spacer().frame(width: 3)
            mouseView
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

    @ViewBuilder private var headset: some View {
        let s = snapshot
        if s.connected {
            HStack(spacing: 2) {
                Image(systemName: "headphones")
                if let b = s.battery { Text("\(b)%") }
                if s.charging { Image(systemName: "bolt.fill").font(.system(size: 9)) }
                if s.micMuted == true { Image(systemName: "mic.slash.fill").font(.system(size: 10)) }
                if s.link == .bluetooth { Text("BT").font(.system(size: 8, weight: .bold)) }
            }
        } else {
            Image(systemName: "headphones.slash").opacity(0.45)
        }
    }

    @ViewBuilder private var mouseView: some View {
        let m = mouse
        if m.connected {
            HStack(spacing: 2) {
                Image(systemName: "computermouse")
                if let b = m.battery { Text("\(b)%") }
                if m.link == .bluetooth { Text("BT").font(.system(size: 8, weight: .bold)) }
            }
        } else {
            Image(systemName: "computermouse").opacity(0.35)
        }
    }
}
