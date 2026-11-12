import SwiftUI

/// Item da barra de menu. Monocromático vira imagem "template" (o macOS pinta conforme a barra);
/// com cores, desenha em branco/preto conforme o tema e mantém as cores da bateria.
struct MenuBarLabel: View {
    let headset: HeadsetSnapshot
    let mouse: MouseSnapshot
    let style: MenuBarStyle
    var look: MenuBarLook = MenuBarLook()
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: render())
    }

    @MainActor private func render() -> NSImage {
        let template = look.color == .monochrome
        let fg: Color = template ? .black : (scheme == .dark ? .white : .black)
        let content = MenuBarContent(headset: headset, mouse: mouse, style: style, look: look, foreground: fg, template: template)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)!
        image.isTemplate = template
        return image
    }
}

/// O conteúdo desenhado (também usado na pré-via dos Ajustes).
struct MenuBarContent: View {
    let headset: HeadsetSnapshot
    let mouse: MouseSnapshot
    let style: MenuBarStyle
    let look: MenuBarLook
    let foreground: Color
    var template = false

    var body: some View {
        HStack(spacing: 5) {
            if look.icons == .fin {
                FinShape().fill(foreground).frame(width: 11, height: 12)
            }
            if style != .mouseOnly {
                DeviceSegment(kind: .headset, connected: headset.connected, level: headset.battery,
                              charging: headset.charging, muted: headset.micMuted == true,
                              bluetooth: headset.link == .bluetooth, look: look, showPercent: showPercent,
                              foreground: foreground, template: template)
            }
            if style != .headsetOnly {
                DeviceSegment(kind: .mouse, connected: mouse.connected, level: mouse.battery,
                              charging: false, muted: false, bluetooth: mouse.link == .bluetooth,
                              look: look, showPercent: showPercent, foreground: foreground, template: template)
            }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(foreground)
        .padding(.vertical, 1)
        .fixedSize() // nunca truncar ("6…") quando a imagem é renderizada
    }

    private var showPercent: Bool { look.showPercent && style != .iconsOnly }
}

private struct DeviceSegment: View {
    let kind: DeviceKind
    let connected: Bool
    let level: Int?
    let charging: Bool
    let muted: Bool
    let bluetooth: Bool
    let look: MenuBarLook
    let showPercent: Bool
    let foreground: Color
    let template: Bool

    var body: some View {
        HStack(spacing: 3) {
            icon
            if connected {
                battery
                if showPercent || look.battery == .number, let l = level { Text("\(l)%") }
                if charging { Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(tint) }
                if muted { Image(systemName: "mic.slash.fill").font(.system(size: 10)) }
                if bluetooth { Text("BT").font(.system(size: 8, weight: .bold)) }
            }
        }
        .opacity(connected ? 1 : 0.4)
    }

    @ViewBuilder private var icon: some View {
        switch look.icons {
        case .device:
            Image(systemName: connected ? symbol : (kind == .headset ? "headphones.slash" : symbol))
        case .initials:
            Text(kind == .headset ? "BS" : "X6").font(.system(size: 10, weight: .heavy, design: .rounded))
        case .fin, .none:
            if !connected { Image(systemName: kind == .headset ? "headphones.slash" : "computermouse") }
        }
    }

    private var symbol: String { kind == .headset ? look.headsetSymbol : look.mouseSymbol }

    /// Cor da parte "bateria" conforme o modo.
    private var tint: Color {
        if template { return foreground }
        switch look.color {
        case .monochrome: return foreground
        case .accent: return Theme.accent
        case .perDevice: return (kind == .headset ? look.headsetColor : look.mouseColor).color
        case .byLevel:
            if charging { return Color(red: 0.25, green: 0.6, blue: 1) }
            guard let l = level else { return foreground }
            return l <= 15 ? .red : l <= 30 ? .yellow : .green
        }
    }

    private var fraction: CGFloat { CGFloat(level ?? 0) / 100 }

    @ViewBuilder private var battery: some View {
        switch look.battery {
        case .capsule:
            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5).stroke(foreground.opacity(0.55), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 1.5).fill(tint)
                        .frame(width: max(1.5, 17 * fraction)).padding(1.5)
                }
                .frame(width: 22, height: 10)
                RoundedRectangle(cornerRadius: 1).fill(foreground.opacity(0.55)).frame(width: 1.5, height: 4)
            }
        case .ring:
            ZStack {
                Circle().stroke(foreground.opacity(0.3), lineWidth: 2)
                Circle().trim(from: 0, to: fraction).stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 13, height: 13)
        case .bars:
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1.5).fill(foreground.opacity(0.25))
                RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(height: max(1.5, 13 * fraction))
            }
            .frame(width: 5, height: 13)
        case .number:
            EmptyView()
        }
    }
}

/// Barbatana do logo do SharkBar.
struct FinShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.75, y: r.minY),
                   control1: CGPoint(x: r.minX + r.width * 0.3, y: r.maxY - r.height * 0.25),
                   control2: CGPoint(x: r.minX + r.width * 0.5, y: r.minY + r.height * 0.15))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                   control1: CGPoint(x: r.minX + r.width * 0.85, y: r.minY + r.height * 0.45),
                   control2: CGPoint(x: r.minX + r.width * 0.85, y: r.maxY - r.height * 0.2))
        p.closeSubpath()
        return p
    }
}
