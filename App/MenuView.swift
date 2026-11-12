import SwiftUI

struct MenuView: View {
    @EnvironmentObject var headset: HeadsetController
    @EnvironmentObject var loginItem: LoginItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = headset.snapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: s.connected ? "headphones" : "headphones.slash")
                    .font(.system(size: 26))
                    .foregroundStyle(s.connected ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("BlackShark V3 Pro").font(.headline)
                    Text(statusLine(s)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let b = s.battery, s.connected {
                    Label("\(b)%", systemImage: s.batterySymbol)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(b <= 15 && !s.charging ? .red : .primary)
                }
            }

            if s.connected && s.link != .bluetooth {
                Divider()
                Text("Modo de áudio").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { s.ancMode ?? .off },
                    set: { headset.setANC($0) }
                )) {
                    ForEach(AncMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if s.ancMode != nil && s.ancMode != .off {
                    LevelSlider(title: "Intensidade", value: s.ancLevel ?? 5) { headset.setANC(s.ancMode!, level: $0) }
                }

                HStack {
                    Text("Sidetone").font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { Double(headset.sidetone) },
                                          set: { headset.sidetone = Int($0) }),
                           in: 0...100) { editing in if !editing { headset.commitSidetone() } }
                    Text("\(headset.sidetone)").monospacedDigit().frame(width: 28, alignment: .trailing)
                }

                if let muted = s.micMuted {
                    Label(muted ? "Microfone mutado" : "Microfone ativo",
                          systemImage: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.caption)
                        .foregroundStyle(muted ? .orange : .secondary)
                }
            }

            if let err = headset.lastError {
                Text(err).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            MouseMenuSection()

            Divider()
            Toggle("Iniciar com o Mac", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.set($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
            if let err = loginItem.error {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Controles…") {
                    openWindow(id: "controls")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button {
                    Task { await headset.refreshAll() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .help("Atualizar")
                Button("Sair") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func statusLine(_ s: HeadsetSnapshot) -> String {
        if s.connected, let link = s.link {
            var parts = ["Conectado via \(link.title)"]
            if s.charging { parts.append("carregando") }
            if s.micMuted == true { parts.append("mic mutado") }
            return parts.joined(separator: " · ")
        }
        return headset.dongleConnected ? "Desligado ou fora de alcance" : "Desligado (dongle ausente)"
    }
}

/// Slider 1…10 que só envia ao soltar.
struct LevelSlider: View {
    let title: String
    let value: Int
    let commit: (Int) -> Void
    @State private var local: Double?

    var body: some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { local ?? Double(value) }, set: { local = $0 }),
                   in: 1...10, step: 1) { editing in
                if !editing, let l = local { commit(Int(l)); local = nil }
            }
            Text("\(Int(local ?? Double(value)))").monospacedDigit().frame(width: 28, alignment: .trailing)
        }
    }
}
