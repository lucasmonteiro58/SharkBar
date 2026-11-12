import AppKit
import Foundation

/// Conjunto de ajustes aplicados de uma vez (estilo G HUB / Synapse).
struct Profile: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String = "star"
    // Fone (nil = não mexe)
    var ancMode: AncMode?
    var ancLevel: Int?
    var sidetone: Int?
    var eqSlot: Int?
    // Mouse
    var dpiStage: Int?
    var pollingHz: Int?

    var summary: String {
        var parts: [String] = []
        if let m = ancMode { parts.append(m == .off ? "ANC off" : "\(m.title) \(ancLevel ?? 5)") }
        if let s = sidetone { parts.append("sidetone \(s)") }
        if let e = eqSlot { parts.append("EQ \(e + 1)") }
        if let d = dpiStage { parts.append("DPI \(d + 1)") }
        if let p = pollingHz { parts.append("\(p) Hz") }
        return parts.isEmpty ? "Sem ajustes" : parts.joined(separator: " · ")
    }

    static let symbols = ["star", "gamecontroller", "music.note", "briefcase", "person.2.wave.2", "film",
                          "moon", "bolt", "headphones", "scope", "airplane", "book"]
}

/// Regra "ao usar este app, aplicar este perfil".
struct AppRule: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var profileID: UUID
}

@MainActor
final class ProfileStore: ObservableObject {
    struct Data: Codable {
        var profiles: [Profile]
        var activeID: UUID?
        var rules: [AppRule] = []
        /// Perfil aplicado ao sair de um app com regra (nil = não muda).
        var fallbackID: UUID?
    }

    @Published var data: Data { didSet { save() } }

    var profiles: [Profile] { data.profiles }
    var active: Profile? { data.profiles.first { $0.id == data.activeID } }

    private static let key = "profiles.v1"

    init() {
        data = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(Data.self, from: $0) } ?? Data(profiles: Self.starter)
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    static let starter: [Profile] = [
        Profile(name: "Jogo", symbol: "gamecontroller", ancMode: .anc, ancLevel: 10, sidetone: 0, dpiStage: 2, pollingHz: 1000),
        Profile(name: "Música", symbol: "music.note", ancMode: .anc, ancLevel: 7, sidetone: 0, dpiStage: 1, pollingHz: 500),
        Profile(name: "Reunião", symbol: "person.2.wave.2", ancMode: .ambient, ancLevel: 5, sidetone: 30, dpiStage: 1, pollingHz: 500),
    ]

    func add(_ p: Profile) { data.profiles.append(p) }

    func update(_ p: Profile) {
        if let i = data.profiles.firstIndex(where: { $0.id == p.id }) { data.profiles[i] = p }
    }

    func delete(_ id: UUID) {
        data.profiles.removeAll { $0.id == id }
        data.rules.removeAll { $0.profileID == id }
        if data.activeID == id { data.activeID = nil }
        if data.fallbackID == id { data.fallbackID = nil }
    }

    func next(after id: UUID?) -> Profile? {
        guard !profiles.isEmpty else { return nil }
        let i = profiles.firstIndex { $0.id == id } ?? -1
        return profiles[(i + 1) % profiles.count]
    }
}

/// Troca de perfil automática conforme o app em primeiro plano.
@MainActor
final class AppWatcher {
    var onApp: ((String) -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.onApp?(id) }
        }
    }
}
