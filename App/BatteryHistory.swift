import Foundation

enum DeviceKind: String, Codable, CaseIterable, Identifiable {
    case headset, mouse
    var id: String { rawValue }
    var title: String { self == .headset ? "BlackShark V3 Pro" : "Attack Shark X6" }
    var symbol: String { self == .headset ? "headphones" : "computermouse" }
}

struct BatterySample: Codable, Equatable {
    var date: Date
    var device: DeviceKind
    var level: Int
    var charging: Bool
}

/// Guarda leituras de bateria dos últimos 7 dias e estima o tempo restante.
@MainActor
final class BatteryHistory: ObservableObject {
    @Published private(set) var samples: [BatterySample] = []
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Brand.name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("battery-history.json")
        samples = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([BatterySample].self, from: $0) } ?? []
    }

    func record(_ device: DeviceKind, level: Int?, charging: Bool) {
        guard let level else { return }
        let last = samples.last { $0.device == device }
        // Grava quando muda, ou a cada 10 min para o gráfico ter continuidade.
        if let last, last.level == level, last.charging == charging, Date.now.timeIntervalSince(last.date) < 600 { return }
        samples.append(BatterySample(date: .now, device: device, level: level, charging: charging))
        let cutoff = Date.now.addingTimeInterval(-7 * 86400)
        samples.removeAll { $0.date < cutoff }
        if let d = try? JSONEncoder().encode(samples) { try? d.write(to: url, options: .atomic) }
    }

    func samples(for device: DeviceKind, since: Date) -> [BatterySample] {
        samples.filter { $0.device == device && $0.date >= since }
    }

    /// Estimativa pela taxa de descarga desde a última vez que parou de carregar.
    func remaining(for device: DeviceKind) -> TimeInterval? {
        let list = samples.filter { $0.device == device }
        guard let last = list.last, !last.charging else { return nil }
        var run: [BatterySample] = []
        for s in list.reversed() {
            if s.charging { break }
            run.insert(s, at: 0)
        }
        guard let first = run.first, run.count >= 3 else { return nil }
        let hours = last.date.timeIntervalSince(first.date) / 3600
        let used = Double(first.level - last.level)
        guard hours >= 0.25, used >= 2 else { return nil }
        let perHour = used / hours
        return Double(last.level) / perHour * 3600
    }

    static func format(_ t: TimeInterval) -> String {
        let h = Int(t / 3600), m = Int(t.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "~\(h) h \(m) min" : "~\(m) min"
    }
}
