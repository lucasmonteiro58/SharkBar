import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Ajustes", symbol: "gearshape", subtitle: "Barra de menu, avisos e comportamento do \(Brand.name).")

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Barra de menu", symbol: "menubar.rectangle")
                    HStack(spacing: 8) {
                        ForEach(MenuBarStyle.allCases) { s in
                            OptionPill(title: s.title, selected: model.settings.data.menuBarStyle == s) {
                                model.settings.data.menuBarStyle = s
                            }
                        }
                    }
                    MenuBarLabel(headset: .placeholder, mouse: .placeholder, style: model.settings.data.menuBarStyle)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    Text("Usa Hidden Bar, Bartender ou Ice? Segure ⌘ e arraste o ícone do \(Brand.name) para a área sempre visível.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Comportamento", symbol: "switch.2")
                    Toggle("Iniciar com o Mac", isOn: Binding(get: { model.loginItem.enabled }, set: { model.loginItem.set($0) }))
                    Toggle("Mostrar aviso na tela (HUD) ao trocar ANC, DPI, mute ou perfil", isOn: binding(\.showHUD))
                    Toggle("Mute sincronizado: mutar a entrada do Mac junto com a chave do fone", isOn: binding(\.muteSync))
                    Toggle("Trocar perfil automaticamente conforme o app (Automação)", isOn: binding(\.perAppProfiles))
                    if let err = model.loginItem.error { Text(err).font(.caption).foregroundStyle(.red) }
                }
                .toggleStyle(.switch)
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Widgets e Central de Controle", symbol: "square.grid.2x2")
                    Text("Clique com o botão direito na mesa › Editar Widgets e procure “\(Brand.name)”. Na Central de Controle, use Editar Controles para adicionar ANC, modo ambiente, DPI e bateria.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            HStack {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text("\(Brand.name) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.headline)
                    Text("Projeto independente, sem relação com a Razer ou a Attack Shark.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Link("GitHub", destination: Brand.repoURL)
            }
            .padding(.top, 6)
        }
    }

    private func binding(_ kp: WritableKeyPath<SettingsData, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings.data[keyPath: kp] }, set: { model.settings.data[keyPath: kp] = $0 })
    }
}
