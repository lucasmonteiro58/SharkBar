import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case headset, mouse, profiles, automation, battery, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .headset: "BlackShark V3 Pro"
        case .mouse: "Attack Shark X6"
        case .profiles: "Perfis"
        case .automation: "Automação"
        case .battery: "Bateria"
        case .settings: "Ajustes"
        }
    }

    var symbol: String {
        switch self {
        case .headset: "headphones"
        case .mouse: "computermouse"
        case .profiles: "square.stack.3d.up"
        case .automation: "wand.and.stars"
        case .battery: "battery.75percent"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class NavigationState: ObservableObject {
    static let shared = NavigationState()
    @Published var page: Page = .headset
}

struct MainWindow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var nav = NavigationState.shared

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { nav.page }, set: { if let p = $0 { nav.page = p } })) {
                Section("Aparelhos") {
                    deviceRow(.headset, connected: model.headset.snapshot.connected,
                              battery: model.headset.snapshot.battery, tint: Theme.headsetTint)
                    deviceRow(.mouse, connected: model.mouse.snapshot.connected,
                              battery: model.mouse.snapshot.battery, tint: Theme.mouseTint)
                }
                Section("SharkBar") {
                    ForEach([Page.profiles, .automation, .battery, .settings]) { p in
                        Label(p.title, systemImage: p.symbol).tag(p)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) { profileFooter }
        } detail: {
            ScrollView {
                Group {
                    switch nav.page {
                    case .headset: HeadsetPage()
                    case .mouse: MousePage()
                    case .profiles: ProfilesPage()
                    case .automation: AutomationPage()
                    case .battery: BatteryPage()
                    case .settings: SettingsPage()
                    }
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
            .navigationTitle(nav.page.title)
        }
        // sharkbar://open/<página> — usado por atalhos, widgets e links.
        .onOpenURL { url in
            if let p = Page(rawValue: url.lastPathComponent) { nav.page = p }
        }
    }

    private func deviceRow(_ page: Page, connected: Bool, battery: Int?, tint: Color) -> some View {
        HStack(spacing: 10) {
            DeviceGlyph(symbol: page.symbol, tint: tint, size: 26, dimmed: !connected)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(connected ? (battery.map { "\($0)%" } ?? "Conectado") : "Desconectado")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .tag(page)
    }

    private var profileFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PERFIL ATIVO").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Menu {
                ForEach(model.profiles.profiles) { p in
                    Button { model.apply(p) } label: { Label(p.name, systemImage: p.symbol) }
                }
            } label: {
                Label(model.profiles.active?.name ?? "Nenhum", systemImage: model.profiles.active?.symbol ?? "circle.dashed")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Cabeçalho grande das páginas de aparelho.
struct DeviceHero<Trailing: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let connected: Bool
    let battery: Int?
    var charging = false
    var chips: [Chip] = []
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 18) {
            DeviceGlyph(symbol: symbol, tint: tint, size: 64, dimmed: !connected)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle).foregroundStyle(.secondary)
                HStack(spacing: 6) { ForEach(chips.indices, id: \.self) { chips[$0] } }
            }
            Spacer()
            trailing
            BatteryRing(level: connected ? battery : nil, charging: charging, symbol: symbol, lineWidth: 8, fontSize: 18)
                .frame(width: 84, height: 84)
        }
        .padding(18)
        .background(
            LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}
