import Carbon.HIToolbox
import SwiftUI

extension RGB {
    var color: Color { Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: UInt8(c.redComponent * 255), g: UInt8(c.greenComponent * 255), b: UInt8(c.blueComponent * 255))
    }
}

struct MousePage: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0

    var body: some View {
        let ms = model.mouse, m = ms.snapshot
        VStack(alignment: .leading, spacing: 18) {
            DeviceHero(
                title: "Attack Shark X6", subtitle: "PAW3395 · até 26 000 DPI",
                symbol: "computermouse", tint: Theme.mouseTint,
                connected: m.connected, battery: m.battery, chips: chips(m, dongle: ms.dongleConnected)
            ) { EmptyView() }

            if !ms.synced {
                Card {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("O X6 não deixa ler a configuração atual").font(.headline)
                            Text("Os valores abaixo começam no padrão de fábrica. Ajuste e clique em “Enviar tudo”: isso substitui DPI, cores, iluminação, polling e botões que estão no mouse.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Enviar tudo para o mouse") { ms.sendAll() }
                                .buttonStyle(.borderedProminent).tint(Theme.mouseTint)
                        }
                    }
                }
            }

            Picker("", selection: $tab) {
                Text("Desempenho").tag(0)
                Text("Botões e macros").tag(1)
                Text("Iluminação e energia").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case 0: PerformanceSection()
                case 1: ButtonsSection()
                default: LightingSection()
                }
            }
            .disabled(!ms.dongleConnected || m.link == .bluetooth)

            HStack {
                if let err = ms.lastError { Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red) }
                Spacer()
                Button("Restaurar padrão de fábrica", role: .destructive) { ms.resetToFactory() }
                Button("Enviar tudo") { ms.sendAll() }
            }
            .disabled(!ms.dongleConnected)
        }
    }

    private func chips(_ m: MouseSnapshot, dongle: Bool) -> [Chip] {
        var c: [Chip] = []
        if m.connected, let l = m.link { c.append(Chip(text: l.title, symbol: l.symbol)) }
        else { c.append(Chip(text: dongle ? "Dormindo/desligado" : "Dongle ausente", symbol: "moon.zzz")) }
        if let d = m.dpi, m.connected { c.append(Chip(text: "\(d) DPI", symbol: "scope", color: Theme.mouseTint)) }
        if let hz = m.pollingHz, m.connected { c.append(Chip(text: "\(hz) Hz", symbol: "waveform.path")) }
        if model.mouse.busy { c.append(Chip(text: "Enviando…", symbol: "arrow.up.circle")) }
        return c
    }
}

private struct PerformanceSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let ms = model.mouse
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Estágios de DPI", symbol: "scope",
                                 trailing: AnyView(Button("Aplicar DPI") { ms.applyConfig() }
                                    .buttonStyle(.borderedProminent).tint(Theme.mouseTint)))
                    ForEach(Array(ms.config.stages.indices), id: \.self) { i in
                        stageRow(i)
                    }
                    Text("50 a 26 000 DPI, em passos de 50. A cor é a do LED nesse estágio.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Polling rate", symbol: "waveform.path")
                    HStack(spacing: 6) {
                        ForEach(AttackShark.pollingRates, id: \.self) { hz in
                            OptionPill(title: "\(hz) Hz", selected: ms.config.pollingHz == hz, tint: Theme.mouseTint) { ms.setPolling(hz) }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Sensor", symbol: "dot.viewfinder")
                    HStack {
                        Text("Lift-off distance")
                        Spacer()
                        Picker("", selection: Binding(get: { ms.config.liftOff2mm }, set: { ms.config.liftOff2mm = $0; ms.applyConfig() })) {
                            Text("1 mm").tag(false); Text("2 mm").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                    }
                    Toggle("Angle snapping (deixa linhas retas)", isOn: Binding(get: { ms.config.angleSnapping },
                                                                               set: { ms.config.angleSnapping = $0; ms.applyConfig() }))
                    Toggle("Ripple control (suaviza tremidas em DPI alto)", isOn: Binding(get: { ms.config.ripple },
                                                                                       set: { ms.config.ripple = $0; ms.applyConfig() }))
                }
            }
        }
    }

    @ViewBuilder private func stageRow(_ i: Int) -> some View {
        let ms = model.mouse
        let stage = ms.config.stages[i]
        HStack(spacing: 10) {
            Button { ms.setStage(i) } label: {
                Text("\(i + 1)")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(ms.config.activeStage == i ? Theme.mouseTint : Color.primary.opacity(0.08), in: Circle())
                    .foregroundStyle(ms.config.activeStage == i ? .white : .primary)
            }
            .buttonStyle(.plain)
            .disabled(!stage.enabled)
            .help("Usar este estágio")
            Toggle("", isOn: Binding(get: { ms.config.stages[i].enabled }, set: { ms.config.stages[i].enabled = $0 }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .disabled(stage.enabled && ms.config.stages.filter(\.enabled).count == 1)
            Slider(value: Binding(get: { Double(ms.config.stages[i].dpi) },
                                  set: { ms.config.stages[i].dpi = Int($0 / 50) * 50 }), in: 50...26000, step: 50)
                .tint(Theme.mouseTint)
            TextField("", value: Binding(get: { ms.config.stages[i].dpi }, set: { ms.config.stages[i].dpi = max(50, min(26000, $0 / 50 * 50)) }),
                      format: .number.grouping(.never))
                .frame(width: 64).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
            ColorPicker("", selection: Binding(get: { ms.config.stages[i].color.color }, set: { ms.config.stages[i].color = RGB($0) }),
                        supportsOpacity: false).labelsHidden()
        }
        .opacity(stage.enabled ? 1 : 0.45)
    }
}

private let buttonNames = ["Botão esquerdo", "Botão direito", "Botão do meio (roda)", "Lateral da frente",
                           "Lateral de trás", "Botão 6 (DPI +)", "Botão 7 (DPI −)"]

private struct ButtonsSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let ms = model.mouse
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Botões", symbol: "cursorarrow.click.2",
                                 trailing: AnyView(HStack {
                                     Button("Padrão") { ms.config.buttons = nil; ms.config.macros = nil }
                                     Button("Aplicar botões") { ms.applyButtons() }
                                         .buttonStyle(.borderedProminent).tint(Theme.mouseTint)
                                 }))
                    ForEach(0..<7, id: \.self) { i in
                        ButtonRow(index: i)
                        if i < 6 { Divider() }
                    }
                }
            }
            Label("Macros são experimentais: o formato veio de capturas do app oficial e não é documentado. Se algo der errado, use “Padrão” e “Aplicar botões”.",
                  systemImage: "flask")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ButtonRow: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        let ms = model.mouse
        let action = ms.config.buttonActions[index]
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(buttonNames[index]).frame(width: 170, alignment: .leading)
                Spacer()
                Picker("", selection: Binding(get: { action }, set: { setAction($0) })) {
                    ForEach(categories, id: \.self) { cat in
                        Section(cat) {
                            ForEach(ButtonAction.allCases.filter { $0.category == cat && allowed($0) }) { a in
                                Text(a.title).tag(a)
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }
            if action == .macro { macroEditor }
        }
        .padding(.vertical, 2)
        .onDisappear { stopRecording() }
    }

    private var categories: [String] { ["Mouse", "Controles", "Mídia", "Atalhos do sistema", "Macro"] }

    /// O botão esquerdo não aceita mídia nem controles (limitação do firmware).
    private func allowed(_ a: ButtonAction) -> Bool {
        index != 0 || ["Mouse", "Macro"].contains(a.category)
    }

    private func setAction(_ a: ButtonAction) {
        var list = model.mouse.config.buttonActions
        list[index] = a
        model.mouse.config.buttonActions = list
    }

    private var macro: MouseMacro { model.mouse.config.macros?[index] ?? MouseMacro() }

    private func setMacro(_ m: MouseMacro) {
        var all = model.mouse.config.macros ?? [:]
        all[index] = m
        model.mouse.config.macros = all
    }

    private var macroEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if macro.keys.isEmpty {
                    Text(recording ? "Digite as teclas…" : "Nenhuma tecla").foregroundStyle(.secondary)
                }
                ForEach(macro.keys) { k in Chip(text: k.display, color: Theme.mouseTint) }
                Spacer()
                Button(recording ? "Parar" : "Gravar teclas") { recording ? stopRecording() : startRecording() }
                    .tint(recording ? .red : nil)
                Button("Limpar") { var m = macro; m.keys = []; setMacro(m) }
            }
            HStack(spacing: 16) {
                Stepper("Intervalo: \(macro.delayMs) ms", value: Binding(get: { macro.delayMs }, set: { var m = macro; m.delayMs = $0; setMacro(m) }),
                        in: 10...1000, step: 10)
                Stepper("Repetir: \(macro.repeatCount)×", value: Binding(get: { macro.repeatCount }, set: { var m = macro; m.repeatCount = $0; setMacro(m) }),
                        in: 1...255)
            }
            .font(.caption)
        }
        .padding(10)
        .background(Theme.mouseTint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let usage = KeyMap.hidUsage(for: event.keyCode) {
                let f = event.modifierFlags
                let label = KeyMap.label(for: event)
                var m = macro
                if m.keys.count < 16 {
                    m.keys.append(MacroKey(usage: usage, ctrl: f.contains(.control), shift: f.contains(.shift),
                                           option: f.contains(.option), command: f.contains(.command), label: label))
                    setMacro(m)
                }
            }
            return nil // não deixa a tecla chegar à janela
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Teclas do Mac (kVK) → códigos HID de teclado.
enum KeyMap {
    static func hidUsage(for keyCode: UInt16) -> UInt8? { table[Int(keyCode)] }

    static func label(for e: NSEvent) -> String {
        switch Int(e.keyCode) {
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Space: "Espaço"
        case kVK_Delete: "⌫"
        case kVK_Escape: "Esc"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        case kVK_F1...kVK_F12, kVK_F13...kVK_F16:
            "F" + String((fKeys.firstIndex(of: Int(e.keyCode)) ?? 0) + 1)
        default: (e.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    private static let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]

    private static let table: [Int: UInt8] = {
        var t: [Int: UInt8] = [:]
        let letters = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
                       kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
                       kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
                       kVK_ANSI_Y, kVK_ANSI_Z]
        for (i, k) in letters.enumerated() { t[k] = UInt8(0x04 + i) }
        let digits = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]
        for (i, k) in digits.enumerated() { t[k] = UInt8(0x1E + i) }
        for (i, k) in fKeys.enumerated() { t[k] = UInt8(0x3A + i) }
        let extra: [(Int, UInt8)] = [
            (kVK_Return, 0x28), (kVK_Escape, 0x29), (kVK_Delete, 0x2A), (kVK_Tab, 0x2B), (kVK_Space, 0x2C),
            (kVK_ANSI_Minus, 0x2D), (kVK_ANSI_Equal, 0x2E), (kVK_ANSI_LeftBracket, 0x2F), (kVK_ANSI_RightBracket, 0x30),
            (kVK_ANSI_Backslash, 0x31), (kVK_ANSI_Semicolon, 0x33), (kVK_ANSI_Quote, 0x34), (kVK_ANSI_Grave, 0x35),
            (kVK_ANSI_Comma, 0x36), (kVK_ANSI_Period, 0x37), (kVK_ANSI_Slash, 0x38),
            (kVK_RightArrow, 0x4F), (kVK_LeftArrow, 0x50), (kVK_DownArrow, 0x51), (kVK_UpArrow, 0x52),
            (kVK_Home, 0x4A), (kVK_PageUp, 0x4B), (kVK_ForwardDelete, 0x4C), (kVK_End, 0x4D), (kVK_PageDown, 0x4E),
        ]
        for (k, u) in extra { t[k] = u }
        return t
    }()
}

private struct LightingSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let ms = model.mouse
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Iluminação", symbol: "lightbulb",
                                 trailing: AnyView(Button("Aplicar") { ms.applyLighting() }
                                    .buttonStyle(.borderedProminent).tint(Theme.mouseTint)))
                    HStack(spacing: 6) {
                        ForEach(LightMode.allCases) { mode in
                            OptionPill(title: mode.title, selected: ms.config.lightMode == mode, tint: Theme.mouseTint) { ms.config.lightMode = mode }
                        }
                    }
                    if ms.config.lightMode == .steady || ms.config.lightMode == .breathing {
                        ColorPicker("Cor", selection: Binding(get: { ms.config.lightColor.color }, set: { ms.config.lightColor = RGB($0) }),
                                    supportsOpacity: false)
                    }
                    if ms.config.lightMode == .breathing {
                        HStack {
                            Text("Velocidade")
                            Slider(value: Binding(get: { Double(ms.config.lightSpeed) }, set: { ms.config.lightSpeed = Int($0) }), in: 1...8, step: 1)
                                .tint(Theme.mouseTint)
                            Text("\(ms.config.lightSpeed)").monospacedDigit().frame(width: 20)
                        }
                    }
                    if ms.config.lightMode == .stageColor {
                        Text("Cada estágio de DPI acende com a cor escolhida em Desempenho.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Energia e resposta", symbol: "moon.zzz")
                    Stepper(value: Binding(get: { ms.config.sleepMinutes }, set: { ms.config.sleepMinutes = $0 }), in: 0.5...60, step: 0.5) {
                        Text("Dormir após \(ms.config.sleepMinutes.formatted()) min parado")
                    }
                    Stepper("Sono profundo após \(ms.config.deepSleepMinutes) min",
                            value: Binding(get: { ms.config.deepSleepMinutes }, set: { ms.config.deepSleepMinutes = $0 }), in: 1...60)
                    Stepper("Debounce dos cliques: \(ms.config.responseMs) ms",
                            value: Binding(get: { ms.config.responseMs }, set: { ms.config.responseMs = $0 }), in: 2...25)
                    Text("Clique em Aplicar (acima) para enviar.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
