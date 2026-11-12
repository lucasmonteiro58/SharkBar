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
        HStack(spacing: 7) {
            if look.showFin {
                FinShape().fill(foreground).frame(width: 11, height: 12)
            }
            if style != .mouseOnly {
                DeviceBattery(kind: .headset, connected: headset.connected, level: headset.battery,
                              charging: headset.charging, muted: headset.micMuted == true,
                              bluetooth: headset.link == .bluetooth, look: look,
                              showPercent: showPercent, foreground: foreground, template: template)
            }
            if style != .headsetOnly {
                DeviceBattery(kind: .mouse, connected: mouse.connected, level: mouse.battery,
                              charging: false, muted: false, bluetooth: mouse.link == .bluetooth,
                              look: look, showPercent: showPercent, foreground: foreground, template: template)
            }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(foreground)
        .padding(.vertical, 1)
        .fixedSize() // nunca truncar quando a imagem é renderizada
    }

    private var showPercent: Bool { (look.showPercent && style != .iconsOnly) || look.battery == .number }
}

/// Um símbolo por aparelho, com a bateria embutida.
private struct DeviceBattery: View {
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

    private var fraction: CGFloat { connected ? CGFloat(level ?? 0) / 100 : 0 }

    var body: some View {
        HStack(spacing: 3) {
            glyphWithBadge
            if connected, showPercent, let l = level { Text("\(l)%") }
            if connected, bluetooth { Text("BT").font(.system(size: 7, weight: .heavy)) }
        }
        .opacity(connected ? 1 : 0.4)
    }

    // MARK: Símbolo

    /// O selo (raio / mic mutado) abre um recorte no símbolo antes de ser desenhado,
    /// para nunca se misturar com as linhas — funciona também na imagem "template".
    private var glyphWithBadge: some View {
        let hasBadge = connected && (charging || muted)
        return glyph
            .overlay(alignment: .bottomTrailing) {
                if hasBadge {
                    Circle().frame(width: 10, height: 10)
                        .offset(x: badgeOffset.width, y: badgeOffset.height)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
            .overlay(alignment: .bottomTrailing) {
                if hasBadge {
                    Image(systemName: charging ? "bolt.fill" : "mic.slash.fill")
                        .font(.system(size: charging ? 7 : 6.5, weight: .bold))
                        .foregroundStyle(charging ? tint : foreground)
                        .frame(width: 10, height: 10)
                        .offset(x: badgeOffset.width, y: badgeOffset.height)
                }
            }
    }

    private var badgeOffset: CGSize {
        switch look.battery {
        case .pill: CGSize(width: 4, height: 3)
        default: CGSize(width: 3.5, height: 2.5)
        }
    }

    @ViewBuilder private var glyph: some View {
        switch look.battery {
        case .ring:
            ZStack {
                Circle().stroke(foreground.opacity(template ? 0.3 : 0.25), lineWidth: 1.8)
                Circle().trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                inner(size: 7.5)
            }
            .frame(width: 19, height: 19)
        case .fill:
            let box = CGSize(width: 18, height: 16)
            ZStack(alignment: .bottom) {
                inner(size: 14).opacity(template ? 0.3 : 0.35)
                Rectangle().fill(tint)
                    .frame(width: box.width, height: box.height * fraction)
                    .mask(alignment: .bottom) { inner(size: 14).frame(width: box.width, height: box.height) }
            }
            .frame(width: box.width, height: box.height)
        case .pill:
            // [ícone | barra de carga] dentro da cápsula: o ícone nunca fica sobre o preenchimento.
            HStack(spacing: 3) {
                inner(size: 8.5).frame(width: 11)
                ZStack(alignment: .leading) {
                    Capsule().fill(foreground.opacity(template ? 0.25 : 0.2))
                    Capsule().fill(tint).frame(width: max(2.5, 13 * fraction))
                }
                .frame(width: 13, height: 5)
            }
            .padding(.horizontal, 4)
            .frame(height: 15)
            .overlay(Capsule().stroke(foreground.opacity(0.5), lineWidth: 1))
        case .number:
            inner(size: 13)
        }
    }

    /// Ícone do aparelho (ou sigla) que vai dentro do símbolo.
    @ViewBuilder private func inner(size: CGFloat) -> some View {
        switch look.icons {
        case .device:
            Image(systemName: connected ? symbol : (kind == .headset ? "headphones.slash" : symbol))
                .font(.system(size: size, weight: .semibold))
        case .initials:
            Text(kind == .headset ? "BS" : "X6")
                .font(.system(size: size * 0.78, weight: .heavy, design: .rounded))
        }
    }

    private var symbol: String { kind == .headset ? look.headsetSymbol : look.mouseSymbol }

    /// Cor do nível conforme o modo.
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
