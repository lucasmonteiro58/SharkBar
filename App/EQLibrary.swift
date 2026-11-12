import AppKit
import Foundation
import UniformTypeIdentifiers

struct EQPreset: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var bands: [Int]          // 10 bandas, -12…12 dB
    var builtIn = false
}

/// Presets prontos + do usuário, com exportar/importar em JSON.
@MainActor
final class EQLibrary: ObservableObject {
    @Published private(set) var user: [EQPreset] { didSet { save() } }
    private static let key = "eqLibrary.v1"

    static let builtIn: [EQPreset] = [
        EQPreset(name: "Flat", bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0], builtIn: true),
        EQPreset(name: "FPS (passos)", bands: [-4, -3, -2, 0, 1, 3, 5, 6, 4, 2], builtIn: true),
        EQPreset(name: "Graves", bands: [7, 6, 5, 3, 1, 0, 0, 0, 0, 0], builtIn: true),
        EQPreset(name: "Voz / Podcast", bands: [-4, -3, -1, 1, 3, 4, 4, 3, 1, 0], builtIn: true),
        EQPreset(name: "Música", bands: [4, 3, 1, 0, -1, 0, 1, 2, 3, 3], builtIn: true),
        EQPreset(name: "Cinema", bands: [5, 4, 2, 0, -1, 0, 2, 3, 3, 2], builtIn: true),
        EQPreset(name: "Agudos claros", bands: [0, 0, 0, 0, 0, 1, 3, 4, 5, 5], builtIn: true),
    ]

    var all: [EQPreset] { Self.builtIn + user }

    init() {
        user = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([EQPreset].self, from: $0) } ?? []
    }

    private func save() {
        if let d = try? JSONEncoder().encode(user) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    func add(name: String, bands: [Int]) { user.append(EQPreset(name: name, bands: bands)) }
    func delete(_ id: UUID) { user.removeAll { $0.id == id } }

    func exportAll() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SharkBar-EQ.json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(user.isEmpty ? Self.builtIn : user).write(to: url)
    }

    /// Retorna quantos presets foram importados.
    @discardableResult
    func importFile() -> Int {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([EQPreset].self, from: data) else { return 0 }
        let valid = list.filter { $0.bands.count == 10 }.map {
            EQPreset(name: $0.name, bands: $0.bands.map { max(-12, min(12, $0)) })
        }
        user.append(contentsOf: valid)
        return valid.count
    }
}
