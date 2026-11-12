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
