import SwiftUI
import UniformTypeIdentifiers

struct AutomationPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Automação", symbol: "wand.and.stars",
                       subtitle: "Perfis que mudam sozinhos conforme o app em uso, e atalhos de teclado globais.")
            PerAppCard()
            HotkeysCard()
            ShortcutsInfoCard()
        }
    }
}

private struct PerAppCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let store = model.profiles
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Perfil por app", symbol: "app.badge",
                             trailing: AnyView(Toggle("", isOn: Binding(get: { model.settings.data.perAppProfiles },
                                                                      set: { model.settings.data.perAppProfiles = $0 }))
                                .toggleStyle(.switch).labelsHidden()))
                Text("Quando um destes apps vier para a frente, o perfil é aplicado. Ao sair dele, volta para o perfil padrão.")
                    .font(.caption).foregroundStyle(.secondary)

                if store.data.rules.isEmpty {
                    Text("Nenhuma regra ainda.").foregroundStyle(.secondary).padding(.vertical, 6)
                }
                ForEach(store.data.rules) { rule in
                    HStack(spacing: 10) {
                        AppIcon(bundleID: rule.bundleID).frame(width: 24, height: 24)
                        Text(rule.appName).frame(width: 180, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { rule.profileID }, set: { new in
                            if let i = store.data.rules.firstIndex(where: { $0.id == rule.id }) { store.data.rules[i].profileID = new }
                        })) {
                            ForEach(store.profiles) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
                        }
                        .labelsHidden()
                        Button { store.data.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Menu("Adicionar app aberto") {
                        ForEach(runningApps(), id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? "?") { add(bundleID: app.bundleIdentifier!, name: app.localizedName ?? "?") }
                        }
                    }
                    .fixedSize()
                    Button("Escolher app…") { pickApp() }
                    Spacer()
                    Picker("Ao sair:", selection: Binding(get: { store.data.fallbackID }, set: { store.data.fallbackID = $0 })) {
                        Text("Manter perfil").tag(UUID?.none)
                        ForEach(store.profiles) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .fixedSize()
                }
                .disabled(store.profiles.isEmpty)
            }
        }
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(bundleID: String, name: String) {
        guard let first = model.profiles.profiles.first,
              !model.profiles.data.rules.contains(where: { $0.bundleID == bundleID }) else { return }
        model.profiles.data.rules.append(AppRule(bundleID: bundleID, appName: name, profileID: first.id))
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let b = Bundle(url: url), let id = b.bundleIdentifier else { return }
        add(bundleID: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
    }
}

struct AppIcon: View {
    let bundleID: String
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else {
            Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
        }
    }
}

private struct HotkeysCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Atalhos de teclado", symbol: "keyboard")
                Text("Funcionam em qualquer app. Use pelo menos ⌃, ⌥ ou ⌘ na combinação.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(HotkeyAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        HotkeyRecorder(hotkey: Binding(get: { model.settings.data.hotkeys[action] },
                                                       set: { model.settings.data.hotkeys[action] = $0 }))
                    }
                }
            }
        }
    }
}

/// Botão que grava a próxima combinação de teclas.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Pressione…" : (hotkey?.display ?? "Definir"))
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .frame(minWidth: 90)
            }
            .tint(recording ? Theme.accent : nil)
            if hotkey != nil {
                Button { hotkey = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil } // Esc cancela
            if let hk = HotkeyCenter.hotkey(from: e) { hotkey = hk; stop() }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

private struct ShortcutsInfoCard: View {
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "square.2.layers.3d.top.filled").font(.title).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Atalhos e Siri").font(.headline)
                    Text("Procure por “SharkBar” no app Atalhos: definir modo de áudio, trocar DPI, aplicar perfil e ler a bateria. Dá para usar em automações (ex.: ao entrar em Foco).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abrir Atalhos") { NSWorkspace.shared.open(URL(string: "shortcuts://")!) }
            }
        }
    }
}
