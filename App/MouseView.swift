import SwiftUI

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: UInt8(c.redComponent * 255), g: UInt8(c.greenComponent * 255), b: UInt8(c.blueComponent * 255))
    }
}

struct MouseView: View {
    @EnvironmentObject var mouse: MouseController

    var body: some View {
        let s = mouse.snapshot
        Form {
            if !mouse.synced {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("O X6 não deixa ler as configurações atuais.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Os valores abaixo são o padrão de fábrica. Ajuste o que quiser e clique em \"Enviar tudo\": isso substitui DPI, cores, iluminação e polling que estão no mouse agora.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Enviar tudo para o mouse") { mouse.sendAll() }
                    }
                }
            }

            Section("Status") {
                LabeledContent("Conexão") {
                    Label(s.connected ? (s.link ?? .dongle).title : (mouse.dongleConnected ? "Desligado/dormindo" : "Dongle ausente"),
                          systemImage: (s.link ?? .none).symbol)
                }
                if s.link == .bluetooth {
                    Text("Por Bluetooth as configurações não podem ser enviadas — só pelo dongle 2.4G.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Bateria") {
                    if let b = s.battery {
                        HStack {
                            ProgressView(value: Double(b), total: 100).frame(width: 140)
                            Text("\(b)%").monospacedDigit()
                        }
                    } else { Text("—") }
                }
            }

            Section("DPI") {
                ForEach($mouse.config.stages) { $stage in
                    let i = mouse.config.stages.firstIndex(where: { $0.id == stage.id }) ?? 0
                    HStack(spacing: 10) {
                        Button {
                            mouse.setStage(i)
                        } label: {
                            Image(systemName: mouse.config.activeStage == i ? "largecircle.fill.circle" : "circle")
                        }
                        .buttonStyle(.plain)
                        .disabled(!stage.enabled)
                        .help("Usar este estágio")
                        Text("\(i + 1)").monospacedDigit().frame(width: 14)
                        Toggle("", isOn: $stage.enabled).labelsHidden()
                            .disabled(stage.enabled && mouse.config.stages.filter(\.enabled).count == 1)
                        Slider(value: Binding(get: { Double(stage.dpi) }, set: { stage.dpi = Int($0 / 50) * 50 }),
                               in: 50...26000, step: 50)
                        TextField("", value: $stage.dpi, format: .number)
                            .frame(width: 64).multilineTextAlignment(.trailing)
                        ColorPicker("", selection: Binding(get: { stage.color.color }, set: { stage.color = RGB($0) }),
                                    supportsOpacity: false).labelsHidden()
                    }
                    .opacity(stage.enabled ? 1 : 0.5)
                }
                HStack {
                    Text("Valores de 50 a 26000, em passos de 50.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Aplicar DPI") { mouse.applyConfig() }.keyboardShortcut(.defaultAction)
                }
            }

            Section("Sensor") {
                Picker("Polling rate", selection: Binding(get: { mouse.config.pollingHz }, set: { mouse.setPolling($0) })) {
                    ForEach(AttackShark.pollingRates, id: \.self) { Text("\($0) Hz").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Lift-off", selection: Binding(get: { mouse.config.liftOff2mm },
                                                      set: { mouse.config.liftOff2mm = $0; mouse.applyConfig() })) {
                    Text("1 mm").tag(false); Text("2 mm").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Angle snapping", isOn: Binding(get: { mouse.config.angleSnapping },
                                                       set: { mouse.config.angleSnapping = $0; mouse.applyConfig() }))
                Toggle("Ripple control", isOn: Binding(get: { mouse.config.ripple },
                                                       set: { mouse.config.ripple = $0; mouse.applyConfig() }))
            }

            Section("Iluminação e energia") {
                Picker("Modo", selection: $mouse.config.lightMode) {
                    ForEach(LightMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if mouse.config.lightMode == .steady || mouse.config.lightMode == .breathing {
                    ColorPicker("Cor", selection: Binding(get: { mouse.config.lightColor.color },
                                                          set: { mouse.config.lightColor = RGB($0) }), supportsOpacity: false)
                }
                if mouse.config.lightMode == .breathing {
                    Stepper("Velocidade: \(mouse.config.lightSpeed)", value: $mouse.config.lightSpeed, in: 1...8)
                }
                Stepper(value: $mouse.config.sleepMinutes, in: 0.5...60, step: 0.5) {
                    Text("Dormir após: \(mouse.config.sleepMinutes.formatted()) min")
                }
                Stepper("Sono profundo após: \(mouse.config.deepSleepMinutes) min", value: $mouse.config.deepSleepMinutes, in: 1...60)
                Stepper("Debounce: \(mouse.config.responseMs) ms", value: $mouse.config.responseMs, in: 2...25)
                HStack {
                    Spacer()
                    Button("Aplicar iluminação/energia") { mouse.applyLighting() }
                }
            }

            Section {
                HStack {
                    Button("Restaurar padrão de fábrica", role: .destructive) { mouse.resetToFactory() }
                    Spacer()
                    Button("Enviar tudo") { mouse.sendAll() }
                }
            } footer: {
                Text("Botões e macros ainda não são suportados.").font(.caption).foregroundStyle(.secondary)
            }

            if let err = mouse.lastError {
                Section { Text(err).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .disabled(!mouse.dongleConnected)
        .overlay(alignment: .topTrailing) {
            if mouse.busy { ProgressView().controlSize(.small).padding(8) }
        }
    }
}

/// Bloco do mouse no menu da barra.
struct MouseMenuSection: View {
    @EnvironmentObject var mouse: MouseController

    /// 800, 1200, 26k — curto para caber no menu.
    static func shortDPI(_ dpi: Int) -> String {
        dpi >= 10000 ? (dpi % 1000 == 0 ? "\(dpi / 1000)k" : String(format: "%.1fk", Double(dpi) / 1000)) : "\(dpi)"
    }

    var body: some View {
        let s = mouse.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "computermouse")
                    .font(.system(size: 24))
                    .foregroundStyle(s.connected ? .green : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Attack Shark X6").font(.headline)
                    Text(s.connected ? "Conectado via \((s.link ?? .dongle).title)" : mouse.dongleConnected ? "Dormindo ou desligado" : "Desligado (dongle ausente)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if s.connected, let b = s.battery {
                    Text("\(b)%").font(.title3.monospacedDigit())
                        .foregroundStyle(b <= 20 ? .red : .primary)
                }
            }
            if mouse.dongleConnected && s.link != .bluetooth {
                Picker("", selection: Binding(get: { mouse.config.activeStage }, set: { mouse.setStage($0) })) {
                    ForEach(Array(mouse.config.stages.enumerated()), id: \.element.id) { i, st in
                        if st.enabled { Text(verbatim: Self.shortDPI(st.dpi)).tag(i) }
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Estágio de DPI")
                .disabled(!mouse.synced) // trocar estágio reenviaria todos os DPIs
                Picker("", selection: Binding(get: { mouse.config.pollingHz }, set: { mouse.setPolling($0) })) {
                    ForEach(AttackShark.pollingRates, id: \.self) { Text(verbatim: "\($0) Hz").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if !mouse.synced {
                    Text("Configurações ainda não enviadas — abra Controles…").font(.caption).foregroundStyle(.orange)
                }
            }
            if let err = mouse.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
