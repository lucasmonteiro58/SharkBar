import Foundation
import ServiceManagement

/// "Iniciar com o Mac" via SMAppService (aparece em Ajustes › Geral › Itens de Início).
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    private static let askedKey = "loginItem.registeredOnce"

    init() {
        // Na primeira execução, liga automaticamente; depois respeita a escolha do usuário.
        if !UserDefaults.standard.bool(forKey: Self.askedKey) {
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            set(true)
        }
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        enabled = SMAppService.mainApp.status == .enabled
    }
}
