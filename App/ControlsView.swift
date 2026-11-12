import SwiftUI

struct ControlsView: View {
    @EnvironmentObject var headset: HeadsetController
    @State private var selectedSlot = 0

    var body: some View {
        let s = headset.snapshot
        Form {
            Section("Status") {
                LabeledContent("Conexão") {
                    Label(s.connected ? (s.link ?? .dongle).title : (headset.dongleConnected ? "Fone desligado" : "Dongle ausente"),
                          systemImage: (s.link ?? .none).symbol)
                }
                if s.link == .bluetooth {
                    Text("Por Bluetooth a Razer não expõe ANC, EQ nem sidetone — use o dongle 2.4G para controlar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Bateria") {
                    if let b = s.battery {
                        HStack {
                            ProgressView(value: Double(b), total: 100).frame(width: 140)
                            Label("\(b)%", systemImage: s.batterySymbol).monospacedDigit()
                        }
                    } else { Text("—") }
                }
                LabeledContent("Carregando", value: s.charging ? "Sim" : "Não")
                LabeledContent("Microfone") {
                    Label(s.micMuted == true ? "Mutado" : s.micMuted == false ? "Ativo" : "—",
                          systemImage: s.micMuted == true ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(s.micMuted == true ? .orange : .primary)
                }
            }

            Section("Cancelamento de ruído") {
                Picker("Modo", selection: Binding(get: { s.ancMode ?? .off }, set: { headset.setANC($0) })) {
                    ForEach(AncMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                LevelSlider(title: "Intensidade", value: s.ancLevel ?? 5) { headset.setANC(s.ancMode ?? .anc, level: $0) }
                    .disabled(s.ancMode == nil || s.ancMode == .off)
            }

            Section("Microfone") {
                HStack {
                    Text("Sidetone")
                    Slider(value: Binding(get: { Double(headset.sidetone) }, set: { headset.sidetone = Int($0) }),
                           in: 0...100) { editing in if !editing { headset.commitSidetone() } }
                    Text("\(headset.sidetone)").monospacedDigit().frame(width: 32, alignment: .trailing)
                }
                Picker("Preset do mic", selection: Binding(get: { headset.micPreset }, set: { headset.setMicPreset($0) })) {
                    ForEach(Array(BlackShark.micPresets.enumerated()), id: \.element) { i, p in
                        Text("Preset \(i + 1)").tag(p)
                    }
                }
                .pickerStyle(.segmented)
                EQEditor(bands: $headset.micEQ)
                HStack {
                    Spacer()
                    Button("Zerar") { headset.micEQ = Array(repeating: 0, count: 10) }
                    Button("Aplicar EQ do mic") { headset.commitMicEQ() }
                }
            }

            Section("Equalizador do fone") {
                if headset.eqSlots.isEmpty {
                    Text("Carregando…").foregroundStyle(.secondary)
                } else {
                    Picker("Slot", selection: $selectedSlot) {
                        ForEach(headset.eqSlots) { slot in
                            Text("\(slot.id + 1)\(slot.active ? " ●" : "")").tag(slot.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    if let idx = headset.eqSlots.firstIndex(where: { $0.id == selectedSlot }) {
                        let slot = headset.eqSlots[idx]
                        EQEditor(bands: $headset.eqSlots[idx].bands)
                            .disabled(!slot.enabled)
                        HStack {
                            if !slot.enabled { Text("Slot desativado no fone").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button("Zerar") { headset.eqSlots[idx].bands = Array(repeating: 0, count: 10) }
                                .disabled(!slot.enabled)
                            Button("Usar este slot") { headset.activateSlot(slot.id) }
                                .disabled(!slot.enabled || slot.active)
                            Button("Gravar EQ") { headset.commitSlot(slot.id) }
                                .disabled(!slot.enabled)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }

            Section("Energia") {
                Picker("Desligar automaticamente", selection: Binding(get: { headset.autoOff }, set: { headset.setAutoOff($0) })) {
                    ForEach(BlackShark.autoOffChoices, id: \.self) { m in
                        Text(m == 0 ? "Nunca" : "\(m) min").tag(m)
                    }
                }
            }

            if let err = headset.lastError {
                Section { Text(err).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .disabled(!s.connected || s.link == .bluetooth)
        .overlay(alignment: .topTrailing) {
            if headset.busy { ProgressView().controlSize(.small).padding(8) }
        }
        .task {
            await headset.refreshAll()
            if let active = headset.eqSlots.first(where: \.active) { selectedSlot = active.id }
        }
        .toolbar {
            Button { Task { await headset.refreshAll() } } label: { Image(systemName: "arrow.clockwise") }
        }
    }
}

/// 10 sliders verticais, -12…+12 dB.
struct EQEditor: View {
    @Binding var bands: [Int]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(bands.indices, id: \.self) { i in
                VStack(spacing: 4) {
                    Text(bands[i] > 0 ? "+\(bands[i])" : "\(bands[i])")
                        .font(.caption2.monospacedDigit())
                    Slider(value: Binding(get: { Double(bands[i]) }, set: { bands[i] = Int($0.rounded()) }),
                           in: -12...12, step: 1)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 110, height: 24)
                        .frame(width: 32, height: 110)
                    Text(BlackShark.eqBands[i]).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
