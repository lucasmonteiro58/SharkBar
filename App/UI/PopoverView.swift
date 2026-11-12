import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            header
            HeadsetQuickCard()
            MouseQuickCard()
            footer
        }
        .padding(12)
        .frame(width: 360)
    }

    private func open(_ page: Page? = nil) {
        if let page { NavigationState.shared.page = page }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
            Text(Brand.name).font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
            Menu {
                ForEach(model.profiles.profiles) { p in
                    Button { model.apply(p) } label: {
                        Label(p.name, systemImage: model.profiles.data.activeID == p.id ? "checkmark" : p.symbol)
                    }
                }
                Divider()
                Button("Gerenciar perfis…") { open(.profiles) }
            } label: {
                Label(model.profiles.active?.name ?? "Perfil", systemImage: model.profiles.active?.symbol ?? "square.stack.3d.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
    }

    private var footer: some View {
        HStack {
            Button { open() } label: {
                Label("Abrir \(Brand.name)", systemImage: "slider.horizontal.3")
            }
            Spacer()
            Button { Task { await model.headset.refreshAll() } } label: { Image(systemName: "arrow.clockwise") }
                .help("Atualizar")
            Button { open(.settings) } label: { Image(systemName: "gearshape") }
                .help("Ajustes")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Sair do \(Brand.name)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
    }
}

struct HeadsetQuickCard: View {
    @EnvironmentObject var model: AppModel
    @State private var level: Double?

    var body: some View {
        let h = model.headset, s = h.snapshot
        let controllable = s.connected && s.link != .bluetooth
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DeviceGlyph(symbol: s.connected ? "headphones" : "headphones.slash", tint: Theme.headsetTint, dimmed: !s.connected)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BlackShark V3 Pro").font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 4) {
                            if s.connected, let link = s.link { Chip(text: link.short, symbol: link.symbol) }
                            else { Chip(text: h.dongleConnected ? "Desligado" : "Dongle ausente", symbol: "powersleep") }
                            if s.charging { Chip(text: "Carregando", symbol: "bolt.fill", color: Theme.accent) }
                            if s.micMuted == true { Chip(text: "Mic mutado", symbol: "mic.slash.fill", color: .orange) }
                        }
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        BatteryRing(level: s.connected ? s.battery : nil, charging: s.charging, lineWidth: 5, fontSize: 11)
                            .frame(width: 46, height: 46)
                        if let t = model.history.remaining(for: .headset), s.connected, !s.charging {
                            Text(BatteryHistory.format(t)).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
                if controllable {
                    HStack(spacing: 6) {
                        ForEach(AncMode.allCases) { m in
                            OptionPill(title: m.title, symbol: m.symbol, selected: s.ancMode == m, tint: Theme.headsetTint) { h.setANC(m) }
                        }
                    }
                    if let mode = s.ancMode, mode != .off {
                        row("Intensidade", value: Int(level ?? Double(s.ancLevel ?? 5))) {
                            Slider(value: Binding(get: { level ?? Double(s.ancLevel ?? 5) }, set: { level = $0 }), in: 1...10, step: 1) { editing in
                                if !editing, let l = level { h.setANC(mode, level: Int(l)); level = nil }
                            }
                            .tint(Theme.headsetTint)
                        }
                    }
                    row("Sidetone", value: h.sidetone) {
                        Slider(value: Binding(get: { Double(h.sidetone) }, set: { h.sidetone = Int($0) }), in: 0...100) { editing in
                            if !editing { h.commitSidetone() }
                        }
                        .tint(Theme.headsetTint)
                    }
                } else if s.link == .bluetooth {
                    Text("Por Bluetooth só a bateria fica disponível. Use o dongle para controlar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let err = h.lastError, s.connected {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    private func row<C: View>(_ title: String, value: Int, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            control()
            Text("\(value)").font(.caption.monospacedDigit()).frame(width: 26, alignment: .trailing)
        }
    }
}

struct MouseQuickCard: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let ms = model.mouse, m = ms.snapshot
        let controllable = ms.dongleConnected && m.link != .bluetooth
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    DeviceGlyph(symbol: "computermouse", tint: Theme.mouseTint, dimmed: !m.connected)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attack Shark X6").font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 4) {
                            if m.connected, let link = m.link { Chip(text: link.short, symbol: link.symbol) }
                            else { Chip(text: ms.dongleConnected ? "Dormindo" : "Dongle ausente", symbol: "moon.zzz") }
                            if let dpi = m.dpi, m.connected { Chip(text: "\(dpi) DPI", symbol: "scope", color: Theme.mouseTint) }
                        }
                    }
                    Spacer()
                    BatteryRing(level: m.connected ? m.battery : nil, symbol: "computermouse", lineWidth: 5, fontSize: 11)
                        .frame(width: 46, height: 46)
                }
                if controllable {
                    if ms.synced {
                        HStack(spacing: 5) {
                            ForEach(Array(ms.config.stages.enumerated()), id: \.element.id) { i, st in
                                if st.enabled {
                                    OptionPill(title: shortDPI(st.dpi), selected: ms.config.activeStage == i, tint: Theme.mouseTint) { ms.setStage(i) }
                                }
                            }
                        }
                    } else {
                        HStack {
                            Label("Configure o mouse uma vez para liberar a troca de DPI.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button("Configurar") {
                                NavigationState.shared.page = .mouse
                                openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                            }
                            .controlSize(.small)
                        }
                    }
                    HStack(spacing: 5) {
                        ForEach(AttackShark.pollingRates, id: \.self) { hz in
                            OptionPill(title: hz == 1000 ? "1000 Hz" : "\(hz)", selected: ms.config.pollingHz == hz, tint: Theme.mouseTint) { ms.setPolling(hz) }
                        }
                    }
                }
                if let err = ms.lastError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }
}
