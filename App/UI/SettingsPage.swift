import SwiftUI

struct SettingsPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Ajustes", symbol: "gearshape", subtitle: "Barra de menu, avisos e comportamento do \(Brand.name).")

            MenuBarAppearanceCard()

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

/// Aparência do item na barra de menu, com pré-via.
private struct MenuBarAppearanceCard: View {
    @EnvironmentObject var model: AppModel

    private var look: Binding<MenuBarLook> {
        Binding(get: { model.settings.data.look }, set: { model.settings.data.look = $0 })
    }

    var body: some View {
        let l = model.settings.data.look
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Barra de menu", symbol: "menubar.rectangle")

                HStack(spacing: 10) {
                    preview(dark: true)
                    preview(dark: false)
                }

                option("Aparelhos") {
                    ForEach(MenuBarStyle.choices) { s in
                        OptionPill(title: s.title, selected: model.settings.data.menuBarStyle == s
                                   || (s == .full && model.settings.data.menuBarStyle == .iconsOnly)) {
                            model.settings.data.menuBarStyle = s
                        }
                    }
                }
                option("Bateria") {
                    ForEach(BatteryStyle.allCases) { b in
                        OptionPill(title: b.title, symbol: symbol(for: b), selected: l.battery == b) { look.wrappedValue.battery = b }
                    }
                }
                option("Cor") {
                    ForEach(BarColorMode.allCases) { c in
                        OptionPill(title: c.title, selected: l.color == c) { look.wrappedValue.color = c }
                    }
                }
                if l.color == .perDevice {
                    HStack(spacing: 20) {
                        ColorPicker("Fone", selection: Binding(get: { l.headsetColor.color }, set: { look.wrappedValue.headsetColor = RGB($0) }),
                                    supportsOpacity: false)
                        ColorPicker("Mouse", selection: Binding(get: { l.mouseColor.color }, set: { look.wrappedValue.mouseColor = RGB($0) }),
                                    supportsOpacity: false)
                        Spacer()
                    }
                    .padding(.leading, 90)
                }
                option("Ícone") {
                    ForEach(BarIconMode.allCases) { i in
                        OptionPill(title: i.title, selected: l.icons == i) { look.wrappedValue.icons = i }
                    }
                }
                if l.icons == .device {
                    symbolRow("Fone", symbols: MenuBarLook.headsetSymbols, selected: l.headsetSymbol) { look.wrappedValue.headsetSymbol = $0 }
                    symbolRow("Mouse", symbols: MenuBarLook.mouseSymbols, selected: l.mouseSymbol) { look.wrappedValue.mouseSymbol = $0 }
                }
                Toggle("Mostrar porcentagem", isOn: Binding(get: { l.showPercent && model.settings.data.menuBarStyle != .iconsOnly },
                                                          set: {
                    look.wrappedValue.showPercent = $0
                    if model.settings.data.menuBarStyle == .iconsOnly { model.settings.data.menuBarStyle = .full }
                }))
                .toggleStyle(.switch)
                .disabled(l.battery == .number)

                Text("Usa Hidden Bar, Bartender ou Ice? Segure ⌘ e arraste o ícone do \(Brand.name) para a área sempre visível.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func symbol(for b: BatteryStyle) -> String {
        switch b {
        case .capsule: "battery.75percent"
        case .ring: "circle.dashed"
        case .bars: "chart.bar.fill"
        case .number: "percent"
        }
    }

    private func option<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            content()
        }
    }

    private func symbolRow(_ title: String, symbols: [String], selected: String, set: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
            ForEach(symbols, id: \.self) { sym in
                Button { set(sym) } label: {
                    Image(systemName: sym).font(.system(size: 15))
                        .frame(width: 34, height: 28)
                        .background(sym == selected ? Theme.accent.opacity(0.25) : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(sym == selected ? Theme.accent : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    /// Simula a barra de menu clara/escura com dados de exemplo.
    private func preview(dark: Bool) -> some View {
        var h = HeadsetSnapshot.placeholder
        h.battery = 64
        h.charging = true
        let m = MouseSnapshot.placeholder
        let fg: Color = dark ? .white : .black
        return HStack {
            Spacer()
            MenuBarContent(headset: h, mouse: m, style: model.settings.data.menuBarStyle, look: model.settings.data.look, foreground: fg)
                .scaleEffect(1.4)
            Spacer()
        }
        .frame(height: 44)
        .background(dark ? Color(white: 0.12) : Color(white: 0.93), in: RoundedRectangle(cornerRadius: 10))
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}
