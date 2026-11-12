import Foundation

/// Protocolo do Attack Shark X6 (dongle Beken 1d57:fa60), interface 2 (usage 01:80).
///
/// Configurações são SET_REPORT *feature* e o mouse **não permite lê-las de volta**:
/// o app guarda o estado canônico e reenvia o relatório inteiro a cada mudança.
/// O dongle confirma cada escrita com o input report `03 10 50 00 <id>` e manda
/// heartbeats `03 10 40 01 <bateria/10>` cerca de 1×/s.
///
/// Fonte: github.com/blak0p/attack-shark-linux (docs/protocol-x6.md, protocol-captures.md),
/// conferido neste mouse (ACK de 0x06 no macOS).
enum AttackShark {
    static let vendorID = 0x1D57
    static let productID = 0xFA60
    static let configUsagePage = 0x01
    static let configUsage = 0x80

    static let pollingRates = [125, 250, 500, 1000]
    static let dpiRange = 50...26000
    static let maxStages = 6

    /// 0x04 — DPI, estágio ativo, cores por estágio, lift-off, angle snapping, ripple. 52 bytes.
    static func configReport(_ c: MouseConfig) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 52)
        r[0] = 0x04; r[1] = 0x38; r[2] = 0x01
        // Estágios 7–8 (não usados no X6) com as cores de fábrica.
        r.replaceSubrange(43..<49, with: [0xFF, 0x40, 0x00, 0xFF, 0xFF, 0xFF])
        r[3] = c.angleSnapping ? 1 : 0
        r[4] = c.ripple ? 1 : 0
        r[5] = c.stages.prefix(8).enumerated().reduce(0) { $0 | ($1.element.enabled ? UInt8(1 << $1.offset) : 0) }
        r[6] = r[3]
        r[7] = c.liftOff2mm ? 1 : 0
        for (i, s) in c.stages.prefix(8).enumerated() {
            let raw = UInt16(max(dpiRange.lowerBound, min(dpiRange.upperBound, s.dpi)) / 50 - 1)
            r[8 + i] = UInt8(raw & 0xFF)
            r[16 + i] = UInt8(raw >> 8)
            r[25 + i * 3] = s.color.r; r[26 + i * 3] = s.color.g; r[27 + i * 3] = s.color.b
        }
        r[24] = UInt8(c.activeStage + 1)
        r[49] = 0x01
        let sum = r[3..<50].reduce(0) { $0 + UInt16($1) }
        r[50] = UInt8(sum >> 8); r[51] = UInt8(sum & 0xFF)
        return r
    }

    /// 0x05 — iluminação, sleep, deep sleep, tempo de resposta. 13 bytes.
    static func lightingReport(_ c: MouseConfig) -> [UInt8] {
        let deep = UInt8(max(1, min(60, c.deepSleepMinutes)))
        let speed = UInt8(max(1, min(8, c.lightSpeed)))
        var r: [UInt8] = [0x05, 0x0F, 0x01, c.lightMode.rawValue,
                          (deep & 0xF0) | (9 - speed),
                          ((deep << 4) & 0xF0) | 0x08,
                          c.lightColor.r, c.lightColor.g, c.lightColor.b,
                          UInt8(max(1, min(120, Int((c.sleepMinutes * 2).rounded())))),
                          UInt8(max(2, min(25, c.responseMs))),
                          0, 0]
        let sum = r[3..<11].reduce(0) { $0 + UInt16($1) }
        r[11] = UInt8(sum >> 8); r[12] = UInt8(sum & 0xFF)
        return r
    }

    /// 0x06 — polling rate. 9 bytes.
    static func pollingReport(_ hz: Int) -> [UInt8] {
        let v = UInt8(1000 / max(125, min(1000, hz)))
        return [0x06, 0x09, 0x01, v, 0xFF - v, 0, 0, 0, 0]
    }

    // MARK: Botões (0x08) e macros (0x09)

    /// Os 7 botões físicos → grupo no relatório 0x08 (offset 3 + (grupo-1)*3).
    static let buttonGroups: [UInt8] = [1, 2, 3, 7, 8, 5, 6]
    /// Ação de fábrica de cada botão.
    static let defaultButtons: [ButtonAction] = [.left, .right, .middle, .forward, .backward, .dpiPlus, .dpiMinus]

    private static let remapBaseline: [UInt8] = [
        0x08, 0x3b, 0x01, 0x02, 0x00, 0x00, 0x03, 0x00, 0x00, 0x04, 0x00, 0x00,
        0x0d, 0x00, 0x00, 0x0e, 0x00, 0x00, 0x0f, 0x00, 0x00, 0x06, 0x00, 0x00,
        0x05, 0x00, 0x00, 0x3c, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x94,
    ]

    /// 0x08 — remapeamento (59 bytes). Botão com macro vira `12 00 <grupo>`.
    static func remapReport(_ buttons: [ButtonAction]) -> [UInt8] {
        var r = remapBaseline
        for (i, action) in buttons.prefix(7).enumerated() {
            let group = buttonGroups[i]
            let off = 3 + Int(group - 1) * 3
            if action == .macro {
                r[off] = 0x12; r[off + 1] = 0; r[off + 2] = group
            } else {
                r[off] = action.rawValue
            }
        }
        let sum = r[3..<57].reduce(0) { $0 + UInt16($1) }
        r[57] = UInt8(sum >> 8); r[58] = UInt8(sum & 0xFF)
        return r
    }

    /// 0x09 — macro de teclado (EXPERIMENTAL: formato decifrado de capturas, não documentado).
    /// Bloco lógico de 128 bytes: [4] repetições, [25] nº de eventos, [26…] pares (atraso|flag, tecla),
    /// checksum soma([0..125]) em [126..127]. Vai em 3 relatórios de 64 bytes: 09 40 <id> 00/01, 09 0c <id> 02.
    static func macroReports(_ macro: MouseMacro, group: UInt8) -> [[UInt8]] {
        var block = [UInt8](repeating: 0, count: 128)
        block[4] = UInt8(max(1, min(255, macro.repeatCount)))
        var events: [(UInt8, UInt8)] = []
        let steps = macro.keys.prefix(24)
        // Byte de flags = (atraso/10) | 0x01 ao apertar, | 0x81 ao soltar (como o app oficial:
        // 100 ms → 0b / 8b). O último evento do macro fica com atraso zero (0x81).
        let d = UInt8(max(1, min(120, macro.delayMs / 10)))
        for key in steps {
            for m in key.modifierUsages { events.append((d | 0x01, m)) }
            events.append((d | 0x01, key.usage))
            events.append((d | 0x81, key.usage))
            for m in key.modifierUsages.reversed() { events.append((d | 0x81, m)) }
        }
        if !events.isEmpty { events[events.count - 1].0 = 0x81 }
        let capped = events.prefix(49)
        block[25] = UInt8(capped.count)
        for (i, e) in capped.enumerated() { block[26 + i * 2] = e.0; block[27 + i * 2] = e.1 }
        let sum = block[0..<126].reduce(0) { $0 + UInt16($1) }
        block[126] = UInt8(sum >> 8); block[127] = UInt8(sum & 0xFF)
        let chunks: [(UInt8, Range<Int>)] = [(0x40, 0..<60), (0x40, 60..<120), (0x0c, 120..<128)]
        return chunks.enumerated().map { idx, c in
            var r = [UInt8](repeating: 0, count: 64)
            r[0] = 0x09; r[1] = c.0; r[2] = group; r[3] = UInt8(idx)
            r.replaceSubrange(4..<(4 + c.1.count), with: block[c.1])
            return r
        }
    }

    enum Event {
        case heartbeat(battery: Int, online: Bool)
        case stageButton(stage: Int)   // 0-based
        case ack(reportID: UInt8)
    }

    static func parse(_ p: [UInt8]) -> Event? {
        guard p.count >= 5, p[0] == 0x03, p[1] == 0x10 else { return nil }
        switch p[2] {
        case 0x40: return .heartbeat(battery: min(100, Int(p[4]) * 10), online: p[3] != 0)
        case 0x10: return p[3] >= 1 ? .stageButton(stage: Int(p[3]) - 1) : nil
        case 0x50: return .ack(reportID: p[4])
        default: return nil
        }
    }
}

/// Ações possíveis para um botão do mouse (IDs do relatório 0x08).
enum ButtonAction: UInt8, Codable, CaseIterable, Identifiable {
    case off = 0x01, left = 0x02, right = 0x03, middle = 0x04, backward = 0x05, forward = 0x06
    case doubleClick = 0x07, fire = 0x08, scrollUp = 0x09, scrollDown = 0x0a
    case dpiCycle = 0x0d, dpiPlus = 0x0e, dpiMinus = 0x0f
    case mediaPlayer = 0x15, previousTrack = 0x16, nextTrack = 0x17, playPause = 0x18, stop = 0x19
    case mute = 0x1a, volumeUp = 0x1b, volumeDown = 0x1c
    case calculator = 0x1d, email = 0x1e, browserForward = 0x20, browserBack = 0x21, browserStop = 0x22
    case myComputer = 0x23, browserRefresh = 0x24, browserHome = 0x25, browserSearch = 0x26
    case macro = 0x12

    var id: UInt8 { rawValue }

    var title: String {
        switch self {
        case .off: "Desativado"
        case .left: "Clique esquerdo"
        case .right: "Clique direito"
        case .middle: "Clique do meio"
        case .backward: "Voltar"
        case .forward: "Avançar"
        case .doubleClick: "Duplo clique"
        case .fire: "Tiro rápido"
        case .scrollUp: "Rolar para cima"
        case .scrollDown: "Rolar para baixo"
        case .dpiCycle: "Ciclar DPI"
        case .dpiPlus: "DPI +"
        case .dpiMinus: "DPI −"
        case .mediaPlayer: "Abrir player"
        case .previousTrack: "Faixa anterior"
        case .nextTrack: "Próxima faixa"
        case .playPause: "Play / pausa"
        case .stop: "Parar"
        case .mute: "Mudo"
        case .volumeUp: "Volume +"
        case .volumeDown: "Volume −"
        case .calculator: "Calculadora"
        case .email: "E-mail"
        case .browserForward: "Navegador: avançar"
        case .browserBack: "Navegador: voltar"
        case .browserStop: "Navegador: parar"
        case .myComputer: "Meu computador"
        case .browserRefresh: "Navegador: recarregar"
        case .browserHome: "Navegador: início"
        case .browserSearch: "Navegador: buscar"
        case .macro: "Macro…"
        }
    }

    var category: String {
        switch self {
        case .off, .left, .right, .middle, .backward, .forward, .doubleClick, .fire: "Mouse"
        case .scrollUp, .scrollDown, .dpiCycle, .dpiPlus, .dpiMinus: "Controles"
        case .mediaPlayer, .previousTrack, .nextTrack, .playPause, .stop, .mute, .volumeUp, .volumeDown: "Mídia"
        case .macro: "Macro"
        default: "Atalhos do sistema"
        }
    }
}

/// Uma tecla de macro: código HID + modificadores.
struct MacroKey: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var usage: UInt8          // HID keyboard usage (A = 0x04)
    var ctrl = false, shift = false, option = false, command = false
    var label: String

    var modifierUsages: [UInt8] {
        [ctrl ? 0xE0 : nil, shift ? 0xE1 : nil, option ? 0xE2 : nil, command ? 0xE3 : nil].compactMap { $0 }
    }

    var display: String {
        (ctrl ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + label
    }
}

struct MouseMacro: Codable, Equatable {
    var keys: [MacroKey] = []
    var delayMs = 30
    var repeatCount = 1
}

struct RGB: Codable, Equatable, Hashable {
    var r: UInt8, g: UInt8, b: UInt8
    static let white = RGB(r: 255, g: 255, b: 255)
}

enum LightMode: UInt8, Codable, CaseIterable, Identifiable {
    case off = 0x00, steady = 0x10, breathing = 0x20, stageColor = 0x50
    var id: UInt8 { rawValue }
    var title: String {
        switch self {
        case .off: "Desligado"
        case .steady: "Fixo"
        case .breathing: "Respirando"
        case .stageColor: "Cor do DPI"
        }
    }
}

struct DPIStage: Codable, Equatable, Identifiable {
    var id = UUID()
    var dpi: Int
    var enabled: Bool = true
    var color: RGB
}

/// Estado canônico do mouse (o mouse não devolve as configurações).
struct MouseConfig: Codable, Equatable {
    var stages: [DPIStage]
    var activeStage = 1
    var pollingHz = 1000
    var liftOff2mm = true
    var angleSnapping = false
    var ripple = false
    var lightMode: LightMode = .stageColor
    var lightColor = RGB(r: 0, g: 255, b: 0)
    var lightSpeed = 6
    var sleepMinutes: Double = 0.5
    var deepSleepMinutes = 10
    var responseMs = 4
    /// Ação de cada um dos 7 botões (nil = padrão de fábrica).
    var buttons: [ButtonAction]? = nil
    /// Macro por botão (índice 0…6), usado quando a ação é `.macro`.
    var macros: [Int: MouseMacro]? = nil

    var buttonActions: [ButtonAction] {
        get { buttons ?? AttackShark.defaultButtons }
        set { buttons = newValue }
    }

    /// Padrão de fábrica do X6.
    static let factory = MouseConfig(stages: [
        DPIStage(dpi: 800, color: RGB(r: 255, g: 0, b: 0)),
        DPIStage(dpi: 1200, color: RGB(r: 0, g: 255, b: 0)),
        DPIStage(dpi: 1600, color: RGB(r: 0, g: 0, b: 255)),
        DPIStage(dpi: 3200, color: RGB(r: 255, g: 255, b: 0)),
        DPIStage(dpi: 5600, color: RGB(r: 0, g: 255, b: 255)),
        DPIStage(dpi: 26000, color: RGB(r: 255, g: 0, b: 255)),
    ])

    var activeDPI: Int? { stages.indices.contains(activeStage) ? stages[activeStage].dpi : nil }
}

/// Resumo do mouse para barra de menu e widget.
struct MouseSnapshot: Codable, Equatable {
    var connected = false
    var link: DeviceLink? = DeviceLink.none
    var battery: Int?
    var dpi: Int?
    var stage: Int?
    var pollingHz: Int?
    /// DPI de cada estágio (nil = desativado), para os botões dos widgets.
    var stageDPIs: [Int?]?
    /// Falso enquanto o app não enviou a configuração ao mouse (trocar estágio sobrescreveria tudo).
    var synced: Bool?
    var updated: Date = .distantPast

    static let placeholder = MouseSnapshot(connected: true, link: .dongle, battery: 100, dpi: 1200, stage: 1, pollingHz: 1000,
                                           stageDPIs: [800, 1200, 1600, 3200, 5600, 26000], synced: true, updated: .now)
}
