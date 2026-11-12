import SwiftUI

enum Theme {
    /// Verde-água do ícone; legível no claro e no escuro.
    static let accent = Color(red: 0.10, green: 0.78, blue: 0.62)
    static let neon = Color(red: 0.27, green: 0.96, blue: 0.55)
    static let headsetTint = Color(red: 0.25, green: 0.62, blue: 1.0)
    static let mouseTint = Color(red: 0.62, green: 0.45, blue: 1.0)

    /// Fundos opacos que acompanham claro/escuro.
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 1, alpha: 1)
    })

    static func batteryColor(_ level: Int?, charging: Bool = false) -> Color {
        guard let l = level else { return .gray }
        if charging { return accent }
        return l <= 15 ? .red : l <= 30 ? .orange : accent
    }
}

/// Cartão com material e borda sutil (padrão dos apps de periféricos).
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Opaco: no popover translúcido, um fundo claro atrás apagava os textos.
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

/// Título de seção com ícone, usado dentro das páginas.
struct SectionTitle: View {
    let title: String
    var symbol: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).foregroundStyle(.secondary) }
            Text(title).font(.headline)
            Spacer()
            trailing
        }
    }
}

struct BatteryRing: View {
    let level: Int?
    var charging = false
    var symbol = "headphones"
    var lineWidth: CGFloat = 6
    var fontSize: CGFloat = 13
    var tint: Color? = nil

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                .stroke(tint ?? Theme.batteryColor(level, charging: charging),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: level)
            VStack(spacing: 0) {
                Image(systemName: charging ? "bolt.fill" : symbol)
                    .font(.system(size: fontSize * 0.75, weight: .semibold))
                    .foregroundStyle(charging ? Theme.accent : .secondary)
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.system(size: fontSize, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

/// Etiqueta pequena (conexão, carregando, mutado…).
struct Chip: View {
    let text: String
    var symbol: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }
}

/// Botão de opção em formato de pílula, com estado selecionado.
struct OptionPill: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(selected ? tint : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .foregroundStyle(selected ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: selected)
    }
}

/// Ícone de aparelho num quadrado arredondado colorido.
struct DeviceGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 34
    var dimmed = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background((dimmed ? Color.gray : tint).gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

func shortDPI(_ dpi: Int) -> String {
    dpi >= 10000 ? (dpi % 1000 == 0 ? "\(dpi / 1000)k" : String(format: "%.1fk", Double(dpi) / 1000)) : "\(dpi)"
}

/// 10 sliders verticais, -12…+12 dB.
struct EQEditor: View {
    @Binding var bands: [Int]
    var tint: Color = Theme.accent

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(bands.indices, id: \.self) { i in
                VStack(spacing: 4) {
                    Text(bands[i] > 0 ? "+\(bands[i])" : "\(bands[i])")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(bands[i] == 0 ? .secondary : .primary)
                    Slider(value: Binding(get: { Double(bands[i]) }, set: { bands[i] = Int($0.rounded()) }),
                           in: -12...12, step: 1)
                        .tint(tint)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 120, height: 22)
                        .frame(width: 30, height: 120)
                    Text(BlackShark.eqBands[i]).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }
}
