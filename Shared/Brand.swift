import Foundation

/// Identidade do app num lugar só.
enum Brand {
    static let name = "SharkBar"
    static let bundleID = "dev.sharkbar.app"
    /// Instalações antigas (versão "Fone") — usado para migrar configurações.
    static let legacyBundleID = "dev.fone.blackshark"
    static let repoURL = URL(string: "https://github.com/lucasmonteiro58/SharkBar")!
}
