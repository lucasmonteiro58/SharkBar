import SwiftUI

struct HeadsetPage: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        let h = model.headset, s = h.snapshot
        let controllable = s.connected && s.link != .bluetooth
        VStack(alignment: .leading, spacing: 18) {
            DeviceHero(
                title: "BlackShark V3 Pro", subtitle: "Razer · fone sem fio com ANC",
                symbol: "headphones", tint: Theme.headsetTint,
                connected: s.connected, battery: s.battery, charging: s.charging,
                chips: chips(s, dongle: h.dongleConnected)
            ) { EmptyView() }

            if !controllable {
                Card {
                    Label(s.link == .bluetooth
                          ? "Conectado por Bluetooth: a Razer não expõe ANC, EQ e sidetone por BT. Use o dongle 2.4 GHz ou o cabo."
                          : "Ligue o fone (ou conecte o dongle) para ajustar.",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("", selection: $tab) {
                Text("Áudio").tag(0)
                Text("Equalizador").tag(1)
                Text("Microfone").tag(2)
                Text("Energia").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case 0: AudioSection()
                case 1: EQSection()
                case 2: MicSection()
                default: PowerSection()
                }
            }
            .disabled(!controllable)
            .opacity(controllable ? 1 : 0.55)

            if let err = h.lastError, s.connected {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
            }
        }
        .task { await model.headset.refreshAll() }
    }

    private func chips(_ s: HeadsetSnapshot, dongle: Bool) -> [Chip] {
        var c: [Chip] = []
        if s.connected, let l = s.link { c.append(Chip(text: l.title, symbol: l.symbol)) }
        else { c.append(Chip(text: dongle ? "Desligado" : "Dongle ausente", symbol: "powersleep")) }
        if s.charging { c.append(Chip(text: "Carregando", symbol: "bolt.fill", color: Theme.accent)) }
        if s.micMuted == true { c.append(Chip(text: "Mic mutado", symbol: "mic.slash.fill", color: .orange)) }
        if let t = model.history.remaining(for: .headset), !s.charging {
            c.append(Chip(text: BatteryHistory.format(t) + " restantes", symbol: "clock"))
        }
        return c
    }
}

private struct AudioSection: View {
    @EnvironmentObject var model: AppModel
    @State private var level: Double?

    var body: some View {
        let h = model.headset, s = h.snapshot
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Cancelamento de ruído", symbol: "ear.trianglebadge.exclamationmark")
                    HStack(spacing: 8) {
                        ForEach(AncMode.allCases) { m in
                            OptionPill(title: m.title, symbol: m.symbol, selected: s.ancMode == m, tint: Theme.headsetTint) { h.setANC(m) }
                        }
                    }
                    HStack {
                        Text("Intensidade").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { level ?? Double(s.ancLevel ?? 5) }, set: { level = $0 }), in: 1...10, step: 1) { editing in
                            if !editing, let l = level { h.setANC(s.ancMode ?? .anc, level: Int(l)); level = nil }
                        }
                        .tint(Theme.headsetTint)
                        Text("\(Int(level ?? Double(s.ancLevel ?? 5)))").monospacedDigit().frame(width: 24)
                    }
                    .disabled(s.ancMode == nil || s.ancMode == .off)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Sidetone", symbol: "waveform.and.mic")
                    Text("Quanto da sua própria voz você ouve no fone.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Slider(value: Binding(get: { Double(h.sidetone) }, set: { h.sidetone = Int($0) }), in: 0...100) { editing in
                            if !editing { h.commitSidetone() }
                        }
                        .tint(Theme.headsetTint)
                        Text("\(h.sidetone)").monospacedDigit().frame(width: 30)
                    }
                }
            }
        }
    }
}

private struct EQSection: View {
    @EnvironmentObject var model: AppModel
    @State private var selected = 0
    @State private var newPresetName = ""
    @State private var showSave = false
    @State private var importMessage: String?

    var body: some View {
        let h = model.headset
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Equalizador do fone", symbol: "slider.vertical.3",
                                 trailing: AnyView(presetMenu))
                    if h.eqSlots.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 6) {
                            ForEach(h.eqSlots) { slot in
                                OptionPill(title: "Slot \(slot.id + 1)", symbol: slot.active ? "checkmark.circle.fill" : nil,
                                           selected: selected == slot.id, tint: Theme.headsetTint) { selected = slot.id }
                                    .opacity(slot.enabled ? 1 : 0.4)
                            }
                        }
                        if let i = h.eqSlots.firstIndex(where: { $0.id == selected }) {
                            let slot = h.eqSlots[i]
                            EQEditor(bands: Binding(get: { h.eqSlots[i].bands }, set: { h.eqSlots[i].bands = $0 }), tint: Theme.headsetTint)
                                .disabled(!slot.enabled)
                            HStack {
                                if !slot.enabled { Text("Slot desativado no fone").font(.caption).foregroundStyle(.secondary) }
                                else if slot.active { Label("Em uso", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.accent) }
                                Spacer()
                                Button("Salvar como preset…") { newPresetName = ""; showSave = true }
                                Button("Usar este slot") { h.activateSlot(slot.id) }.disabled(!slot.enabled || slot.active)
                                Button("Gravar no fone") { h.commitSlot(slot.id) }
                                    .buttonStyle(.borderedProminent).tint(Theme.headsetTint)
                                    .disabled(!slot.enabled)
                            }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Biblioteca de EQ", symbol: "books.vertical")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(model.eqLibrary.all) { p in
                            PresetTile(preset: p) { load(p) } onDelete: { model.eqLibrary.delete(p.id) }
                        }
                    }
                    HStack {
                        if let importMessage { Text(importMessage).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Importar…") {
                            let n = model.eqLibrary.importFile()
                            importMessage = n > 0 ? "\(n) preset(s) importado(s)" : "Nada importado"
                        }
                        Button("Exportar…") { model.eqLibrary.exportAll() }
                    }
                }
            }
        }
        .onAppear { if let a = h.eqSlots.first(where: \.active) { selected = a.id } }
        .alert("Salvar preset", isPresented: $showSave) {
            TextField("Nome", text: $newPresetName)
            Button("Salvar") {
                if let slot = h.eqSlots.first(where: { $0.id == selected }), !newPresetName.isEmpty {
                    model.eqLibrary.add(name: newPresetName, bands: slot.bands)
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var presetMenu: some View {
        Menu("Carregar preset") {
            ForEach(model.eqLibrary.all) { p in Button(p.name) { load(p) } }
        }
        .fixedSize()
    }

    private func load(_ p: EQPreset) {
        let h = model.headset
        if let i = h.eqSlots.firstIndex(where: { $0.id == selected }) { h.eqSlots[i].bands = p.bands }
    }
}

private struct PresetTile: View {
    let preset: EQPreset
    let onLoad: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onLoad) {
            VStack(alignment: .leading, spacing: 6) {
                // mini curva
                HStack(alignment: .center, spacing: 2) {
                    ForEach(preset.bands.indices, id: \.self) { i in
                        Capsule().fill(Theme.headsetTint.opacity(0.8))
                            .frame(width: 5, height: CGFloat(4 + abs(preset.bands[i]) * 2))
                            .offset(y: CGFloat(-preset.bands[i]))
                    }
                }
                .frame(height: 30)
                HStack {
                    Text(preset.name).font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if !preset.builtIn {
                        Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless).font(.caption)
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Carregar no slot selecionado (depois clique em Gravar no fone)")
    }
}

private struct MicSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let h = model.headset, s = h.snapshot
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Mute", symbol: s.micMuted == true ? "mic.slash.fill" : "mic.fill")
                    HStack {
                        Label(s.micMuted == true ? "Microfone mutado (chave no fone)" : "Microfone ativo",
                              systemImage: s.micMuted == true ? "mic.slash.fill" : "mic.fill")
                            .foregroundStyle(s.micMuted == true ? .orange : .primary)
                        Spacer()
                    }
                    Toggle("Sincronizar com o Mac: ao mutar no fone, mutar também a entrada de áudio do Mac",
                           isOn: Binding(get: { model.settings.data.muteSync }, set: { model.settings.data.muteSync = $0 }))
                        .toggleStyle(.switch)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Equalizador do microfone", symbol: "mic.badge.plus")
                    HStack(spacing: 6) {
                        ForEach(Array(BlackShark.micPresets.enumerated()), id: \.element) { i, p in
                            OptionPill(title: "Preset \(i + 1)", selected: h.micPreset == p, tint: Theme.headsetTint) { h.setMicPreset(p) }
                        }
                    }
                    EQEditor(bands: Binding(get: { h.micEQ }, set: { h.micEQ = $0 }), tint: Theme.headsetTint)
                    HStack {
                        Spacer()
                        Button("Zerar") { h.micEQ = Array(repeating: 0, count: 10) }
                        Button("Gravar no fone") { h.commitMicEQ() }.buttonStyle(.borderedProminent).tint(Theme.headsetTint)
                    }
                }
            }
        }
    }
}

private struct PowerSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let h = model.headset
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Desligamento automático", symbol: "powersleep")
                Text("Desliga o fone depois de um tempo sem áudio.").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(BlackShark.autoOffChoices, id: \.self) { m in
                        OptionPill(title: m == 0 ? "Nunca" : "\(m) min", selected: h.autoOff == m, tint: Theme.headsetTint) { h.setAutoOff(m) }
                    }
                }
            }
        }
    }
}
