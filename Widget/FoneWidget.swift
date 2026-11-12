import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: HeadsetSnapshot?
    var mouse: MouseSnapshot? = nil
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: .placeholder, mouse: .placeholder) }

    private func current() -> Entry {
        Entry(date: .now, snapshot: SharedStore.load(HeadsetSnapshot.self, "headset"),
              mouse: SharedStore.load(MouseSnapshot.self, "mouse"))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // O app chama reloadAllTimelines() a cada mudança; isto é só um fallback.
        let entry = current()
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct BatteryRing: View {
    let level: Int?
    let charging: Bool
    var lineWidth: CGFloat = 8
    var symbol = "headphones"
    var fontSize: CGFloat = 18

    var color: Color {
        guard let l = level else { return .gray }
        if charging { return .green }
        return l <= 15 ? .red : l <= 30 ? .orange : .green
    }

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(level ?? 0) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: charging ? "bolt.fill" : symbol)
                    .font(.system(size: fontSize * 0.75, weight: .semibold))
                    .foregroundStyle(charging ? .green : .secondary)
                Text(level.map { "\($0)%" } ?? "—")
                    .font(.system(size: fontSize, weight: .bold, design: .rounded).monospacedDigit())
            }
        }
    }
}

struct FoneWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    private func fresh(_ d: Date) -> Bool { Date.now.timeIntervalSince(d) < 30 * 60 }

    var body: some View {
        let s = entry.snapshot ?? HeadsetSnapshot()
        let m = entry.mouse ?? MouseSnapshot()
        let online = s.connected && fresh(s.updated)
        let mouseOnline = m.connected && fresh(m.updated)

        Group {
            if family == .systemSmall {
                HStack(spacing: 10) {
                    VStack(spacing: 6) {
                        BatteryRing(level: online ? s.battery : nil, charging: s.charging, lineWidth: 6,
                                symbol: online ? (s.micMuted == true ? "mic.slash.fill" : "headphones") : "headphones.slash", fontSize: 14)
                        Text(online ? (s.ancMode?.title ?? "Fone") : "Fone off")
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    VStack(spacing: 6) {
                        BatteryRing(level: mouseOnline ? m.battery : nil, charging: false, lineWidth: 6,
                                    symbol: "computermouse", fontSize: 14)
                        Text(mouseOnline ? (m.dpi.map { "\($0) DPI" } ?? "Mouse") : "Mouse off")
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 14) {
                    deviceColumn(ring: BatteryRing(level: online ? s.battery : nil, charging: s.charging, lineWidth: 8,
                                                   symbol: online ? (s.micMuted == true ? "mic.slash.fill" : "headphones") : "headphones.slash"),
                                 title: "BlackShark V3 Pro",
                                 lines: online ? [
                                    ((s.link ?? .dongle).symbol, (s.link ?? .dongle).short + (s.charging ? " · carregando" : "")),
                                    (s.ancMode?.symbol ?? "ear", s.ancMode.map { $0 == .off ? $0.title : "\($0.title) · \(s.ancLevel ?? 0)" } ?? "—"),
                                    (s.micMuted == true ? "mic.slash.fill" : "mic.fill", s.micMuted == true ? "Mic mutado" : "Mic ativo"),
                                 ] : [("headphones.slash", "Desconectado")])
                    Divider()
                    deviceColumn(ring: BatteryRing(level: mouseOnline ? m.battery : nil, charging: false, lineWidth: 8,
                                                   symbol: "computermouse"),
                                 title: "Attack Shark X6",
                                 lines: mouseOnline ? [
                                    ((m.link ?? .dongle).symbol, (m.link ?? .dongle).short),
                                    ("scope", m.dpi.map { "\($0) DPI" } ?? "—"),
                                    ("waveform.path", m.pollingHz.map { "\($0) Hz" } ?? "—"),
                                 ] : [("computermouse", "Dormindo/desligado")])
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func deviceColumn(ring: BatteryRing, title: String, lines: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ring.frame(width: 58, height: 58)
                Text(title).font(.caption.bold()).lineLimit(2)
            }
            ForEach(lines, id: \.1) { line in
                Label(line.1, systemImage: line.0).font(.caption2).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@main
struct FoneWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FoneWidget", provider: Provider()) { entry in
            FoneWidgetView(entry: entry)
        }
        .configurationDisplayName("Fone & Mouse")
        .description("Bateria do BlackShark V3 Pro e do Attack Shark X6.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
