import Foundation

enum AncMode: Int, Codable, CaseIterable, Identifiable {
    case off = 0
    case anc = 1
    case ambient = 80

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: "Desligado"
        case .anc: "Cancelamento"
        case .ambient: "Ambiente"
        }
    }

    var symbol: String {
        switch self {
        case .off: "speaker.wave.2"
        case .anc: "ear.trianglebadge.exclamationmark"
        case .ambient: "ear"
        }
    }
}

/// Como o aparelho está ligado ao Mac.
enum DeviceLink: String, Codable {
    case dongle, usb, bluetooth, none

    var title: String {
        switch self {
        case .dongle: "2.4 GHz (dongle)"
        case .usb: "Cabo USB"
        case .bluetooth: "Bluetooth"
        case .none: "Desconectado"
        }
    }

    var short: String {
        switch self {
        case .dongle: "2.4G"
        case .usb: "USB"
        case .bluetooth: "BT"
        case .none: "—"
        }
    }

    var symbol: String {
        switch self {
        case .dongle: "antenna.radiowaves.left.and.right"
        case .usb: "cable.connector"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .none: "xmark.circle"
        }
    }
}

/// Estado resumido que o app grava e o widget lê.
struct HeadsetSnapshot: Codable, Equatable {
    var connected: Bool = false
    var link: DeviceLink? = DeviceLink.none
    var battery: Int?
    var charging: Bool = false
    var ancMode: AncMode?
    var ancLevel: Int?
    var micMuted: Bool?
    var updated: Date = .distantPast

    static let placeholder = HeadsetSnapshot(connected: true, battery: 85, charging: false,
                                             ancMode: .anc, ancLevel: 4, micMuted: false, updated: .now)

    var batterySymbol: String {
        if charging { return "battery.100percent.bolt" }
        guard let b = battery else { return "battery.0percent" }
        switch b {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Arquivo JSON compartilhado via App Group entre o app e o widget.
enum SharedStore {
    static let appGroup = "group.dev.fone.blackshark"

    static func url(_ name: String) -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/\(appGroup)")
        return base.appendingPathComponent("\(name).json")
    }

    /// Grava no App Group (para o widget) e uma cópia em ~/Library/Caches (para scripts).
    static func save<T: Encodable>(_ value: T, as name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let mirror = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/dev.fone.blackshark/\(name).json")
        for u in [url(name), mirror] {
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: u, options: .atomic)
        }
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
