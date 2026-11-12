import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Dados

struct Entry: TimelineEntry {
    let date: Date
    let headset: HeadsetSnapshot
    let mouse: MouseSnapshot

    /// Considera desatualizado se o app não escreve há 30 min (app fechado).
    var headsetOnline: Bool { headset.connected && Date.now.timeIntervalSince(headset.updated) < 1800 }
    var mouseOnline: Bool { mouse.connected && Date.now.timeIntervalSince(mouse.updated) < 1800 }
    /// Controles do fone só funcionam pelo dongle/cabo.
    var headsetControllable: Bool { headsetOnline && headset.link != .bluetooth }
    var mouseControllable: Bool { mouseOnline && mouse.link != .bluetooth && mouse.synced == true }

    static let placeholder = Entry(date: .now, headset: .placeholder, mouse: .placeholder)
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? .placeholder : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // O app recarrega os widgets a cada mudança; isto é só um fallback.
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func current() -> Entry {
        Entry(date: .now,
              headset: SharedStore.load(HeadsetSnapshot.self, "headset") ?? HeadsetSnapshot(),
              mouse: SharedStore.load(MouseSnapshot.self, "mouse") ?? MouseSnapshot())
    }
}

// MARK: - Peças

let accent = Color(red: 0.27, green: 0.95, blue: 0.45)

struct BatteryRing: View {
    let level: Int?
    var charging = false
    var symbol = "headphones"
    var lineWidth: CGFloat = 7
    var fontSize: CGFloat = 16

    private var color: Color {
        guard let l = level else { return .gray }
        if charging { return accent }
        return l <= 15 ? .red : l <= 30 ? .orange : accent
    }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Image(systemName: charging ? "bolt.fill" : symbol)
                    .font(.system(size: fontSize * 0.72, weight: .semibold))
                    .foregroundStyle(charging ? accent : .secondary)
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.system(size: fontSize, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

/// Botão de pílula usado nos widgets interativos.
struct Pill<I: AppIntent>: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    let intent: I

    var body: some View {
        Button(intent: intent) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(selected ? accent.opacity(0.9) : Color.primary.opacity(0.08), in: Capsule())
            .foregroundStyle(selected ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

func shortDPI(_ dpi: Int) -> String {
    dpi >= 10000 ? (dpi % 1000 == 0 ? "\(dpi / 1000)k" : String(format: "%.1fk", Double(dpi) / 1000)) : "\(dpi)"
}

struct HeadsetHeader: View {
    let e: Entry
    var ring: CGFloat = 58

    var body: some View {
        let s = e.headset
        HStack(spacing: 10) {
            BatteryRing(level: e.headsetOnline ? s.battery : nil, charging: s.charging,
                        symbol: e.headsetOnline ? (s.micMuted == true ? "mic.slash.fill" : "headphones") : "headphones.slash")
                .frame(width: ring, height: ring)
            VStack(alignment: .leading, spacing: 3) {
                Text("BlackShark V3 Pro").font(.caption.bold()).lineLimit(1)
                if e.headsetOnline {
                    Label((s.link ?? .dongle).short + (s.charging ? " · carregando" : ""), systemImage: (s.link ?? .dongle).symbol)
                    if let m = s.ancMode {
                        Label(m == .off ? m.title : "\(m.title) · \(s.ancLevel ?? 0)", systemImage: m.symbol)
                    }
                    if s.micMuted == true { Label("Mic mutado", systemImage: "mic.slash.fill").foregroundStyle(.orange) }
                } else {
                    Label("Desligado", systemImage: "headphones.slash").foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

struct MouseHeader: View {
    let e: Entry
    var ring: CGFloat = 58

    var body: some View {
        let m = e.mouse
        HStack(spacing: 10) {
            BatteryRing(level: e.mouseOnline ? m.battery : nil, symbol: "computermouse")
                .frame(width: ring, height: ring)
                .opacity(e.mouseOnline ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 3) {
                Text("Attack Shark X6").font(.caption.bold()).lineLimit(1)
                if e.mouseOnline {
                    Label((m.link ?? .dongle).short, systemImage: (m.link ?? .dongle).symbol)
                    Label(m.dpi.map { "\($0) DPI" } ?? "—", systemImage: "scope")
                    Label(m.pollingHz.map { "\($0) Hz" } ?? "—", systemImage: "waveform.path")
                } else {
                    Label("Dormindo/desligado", systemImage: "moon.zzz").foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

struct AudioModeButtons: View {
    let e: Entry
    var body: some View {
        HStack(spacing: 5) {
            Pill(title: "Off", symbol: "speaker.wave.2", selected: e.headset.ancMode == .off, intent: SetAudioModeIntent(.off))
            Pill(title: "ANC", symbol: "ear.trianglebadge.exclamationmark", selected: e.headset.ancMode == .anc, intent: SetAudioModeIntent(.anc))
            Pill(title: "Ambiente", symbol: "ear", selected: e.headset.ancMode == .ambient, intent: SetAudioModeIntent(.ambient))
        }
        .disabled(!e.headsetControllable)
        .opacity(e.headsetControllable ? 1 : 0.4)
    }
}

struct DPIButtons: View {
    let e: Entry
    var columns = 3
    var body: some View {
        let stages = (e.mouse.stageDPIs ?? []).enumerated().compactMap { i, d in d.map { (i, $0) } }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: columns), spacing: 5) {
            ForEach(stages, id: \.0) { i, dpi in
                Pill(title: shortDPI(dpi), selected: e.mouse.stage == i, intent: SetDPIStageIntent(index: i))
            }
        }
        .disabled(!e.mouseControllable)
        .opacity(e.mouseControllable ? 1 : 0.4)
    }
}

struct PollingButtons: View {
    let e: Entry
    var body: some View {
        HStack(spacing: 5) {
            ForEach([125, 250, 500, 1000], id: \.self) { hz in
                Pill(title: hz == 1000 ? "1k Hz" : "\(hz)", selected: e.mouse.pollingHz == hz, intent: SetPollingIntent(hz))
            }
        }
        .disabled(!(e.mouseOnline && e.mouse.link != .bluetooth))
        .opacity(e.mouseOnline && e.mouse.link != .bluetooth ? 1 : 0.4)
    }
}

// MARK: - Widget 1: visão geral (fone + mouse)

struct OverviewView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var body: some View {
        let e = entry
        Group {
            switch family {
            case .systemSmall:
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        BatteryRing(level: e.headsetOnline ? e.headset.battery : nil, charging: e.headset.charging,
                                    symbol: e.headsetOnline ? (e.headset.micMuted == true ? "mic.slash.fill" : "headphones") : "headphones.slash",
                                    lineWidth: 6, fontSize: 13)
                        BatteryRing(level: e.mouseOnline ? e.mouse.battery : nil, symbol: "computermouse", lineWidth: 6, fontSize: 13)
                    }
                    HStack {
                        Text(e.headsetOnline ? (e.headset.ancMode?.title ?? "Fone") : "Fone off")
                        Spacer()
                        Text(e.mouseOnline ? (e.mouse.dpi.map { "\($0) DPI" } ?? "Mouse") : "Mouse off")
                    }
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            case .systemLarge:
                VStack(alignment: .leading, spacing: 10) {
                    HeadsetHeader(e: e, ring: 64)
                    AudioModeButtons(e: e)
                    Divider()
                    MouseHeader(e: e, ring: 64)
                    DPIButtons(e: e)
                    PollingButtons(e: e)
                    Spacer(minLength: 0)
                    footer(e)
                }
            default:
                HStack(spacing: 12) {
                    HeadsetHeader(e: e)
                    Divider()
                    MouseHeader(e: e)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func footer(_ e: Entry) -> some View {
        HStack {
            Text(max(e.headset.updated, e.mouse.updated), style: .relative)
            Spacer()
            Button(intent: RefreshDevicesIntent()) { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain)
        }
        .font(.caption2).foregroundStyle(.tertiary)
    }
}

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FoneWidget", provider: Provider()) { OverviewView(entry: $0) }
            .configurationDisplayName("Fone & Mouse")
            .description("Bateria do BlackShark V3 Pro e do Attack Shark X6. O tamanho grande tem os controles.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget 2: BlackShark V3 Pro

struct HeadsetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var body: some View {
        let e = entry, s = e.headset
        Group {
            if family == .systemSmall {
                VStack(spacing: 6) {
                    BatteryRing(level: e.headsetOnline ? s.battery : nil, charging: s.charging,
                                symbol: e.headsetOnline ? (s.micMuted == true ? "mic.slash.fill" : "headphones") : "headphones.slash",
                                lineWidth: 8, fontSize: 18)
                        .frame(width: 78, height: 78)
                    Button(intent: CycleAudioModeIntent()) {
                        Label(e.headsetOnline ? (s.ancMode?.title ?? "—") : "Desligado",
                              systemImage: s.ancMode?.symbol ?? "headphones")
                            .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!e.headsetControllable)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HeadsetHeader(e: e, ring: 62)
                    AudioModeButtons(e: e)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct HeadsetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HeadsetWidget", provider: Provider()) { HeadsetView(entry: $0) }
            .configurationDisplayName("BlackShark V3 Pro")
            .description("Bateria e modo de áudio do fone, com botões de ANC e ambiente.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget 3: Attack Shark X6

struct MouseWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var body: some View {
        let e = entry, m = e.mouse
        Group {
            if family == .systemSmall {
                VStack(spacing: 6) {
                    BatteryRing(level: e.mouseOnline ? m.battery : nil, symbol: "computermouse", lineWidth: 8, fontSize: 18)
                        .frame(width: 78, height: 78)
                    Button(intent: NextDPIStageIntent()) {
                        Label(e.mouseOnline ? (m.dpi.map { "\($0) DPI" } ?? "—") : "Off", systemImage: "scope")
                            .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!e.mouseControllable)
                }
            } else {
                HStack(spacing: 12) {
                    VStack(spacing: 4) {
                        BatteryRing(level: e.mouseOnline ? m.battery : nil, symbol: "computermouse", lineWidth: 7, fontSize: 15)
                            .frame(width: 64, height: 64)
                        Text("Attack Shark X6").font(.system(size: 9, weight: .semibold)).lineLimit(1)
                        Label(e.mouseOnline ? (m.link ?? .dongle).short : "Off", systemImage: (m.link ?? .none).symbol)
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(width: 84)
                    VStack(spacing: 6) {
                        DPIButtons(e: e)
                        PollingButtons(e: e)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct MouseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MouseWidget", provider: Provider()) { MouseWidgetView(entry: $0) }
            .configurationDisplayName("Attack Shark X6")
            .description("Bateria, DPI e polling do mouse, com botões para trocar.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Pacote

@main
struct FoneWidgets: WidgetBundle {
    var body: some Widget {
        OverviewWidget()
        HeadsetWidget()
        MouseWidget()
        if #available(macOS 26.0, *) {
            AudioModeControl()
            NoiseCancellingControl()
            AmbientControl()
            DPIControl()
            BatteryControl()
        }
    }
}
