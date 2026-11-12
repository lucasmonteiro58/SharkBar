import Foundation

/// Protocolo HID do Razer BlackShark V3 Pro (1532:0577 dongle, 1532:0576 cabo).
///
/// Coleção vendor FF14:0001, relatórios de 64 bytes (output → headset, input ← headset):
///
///     [0]  0x02            report id
///     [1]  status          0 na requisição; 0x02 = sucesso na resposta
///     [2]  0x60
///     [6]  4 + n           tamanho
///     [9]  0x80            roteia para o fone sem fio
///     [10] comando         GET = 0x1X/0x2X, SET = GET | 0x80
///     [11] 0x01 na resposta
///     [12] n               quantidade de bytes de dados
///     [13..] dados
///     [62] XOR dos bytes 0..61
///
/// Fontes: openrazer/openrazer#2838 e infinityInfinite/secbird#18, conferido neste fone.
enum BlackShark {
    static let vendorID = 0x1532
    static let productIDs = [0x0577, 0x0576, 0x057A, 0x0579]
    static let reportID: UInt8 = 0x02
    static let reportSize = 64

    enum Command: UInt8 {
        case anc = 0x12
        case speakerEQ = 0x15
        case micPreset = 0x16
        case micEQ = 0x17
        case sidetone = 0x19
        case battery = 0x21
        case charging = 0x2A
        case autoOff = 0x2C
        case micMute = 0x55
        case eqOrder = 0x60
        case eqOrderWrite = 0xE0
        case eqStage = 0xE1

        var set: UInt8 { rawValue | 0x80 }
    }

    enum Status: UInt8 {
        case new = 0x00, busy = 0x01, success = 0x02, failure = 0x03, timeout = 0x04, unsupported = 0x05
    }

    static func request(_ command: UInt8, _ args: [UInt8] = []) -> [UInt8] {
        precondition(args.count <= 49)
        var p = [UInt8](repeating: 0, count: reportSize)
        p[0] = reportID
        p[2] = 0x60
        p[6] = UInt8(4 + args.count)
        p[9] = 0x80
        p[10] = command
        p[12] = UInt8(args.count)
        p.replaceSubrange(13..<(13 + args.count), with: args)
        p[62] = checksum(p)
        return p
    }

    static func checksum(_ p: [UInt8]) -> UInt8 { p[0..<62].reduce(0, ^) }

    struct Reply {
        let command: UInt8
        let status: Status?
        let data: [UInt8]
    }

    static func parse(_ p: [UInt8]) -> Reply? {
        guard p.count >= reportSize, p[0] == reportID, p[2] == 0x60, p[9] == 0x80,
              p[11] == 1, p[12] <= 49, Int(p[6]) == 4 + Int(p[12]),
              checksum(p) == p[62] else { return nil }
        let n = Int(p[12])
        return Reply(command: p[10], status: Status(rawValue: p[1]), data: Array(p[13..<(13 + n)]))
    }

    /// EQ usa sinal-magnitude: 0x85 = -5 dB, 0x80 = -0 (plano).
    static func encodeGain(_ db: Int) -> UInt8 {
        let v = max(-12, min(12, db))
        return v < 0 ? 0x80 | UInt8(-v) : UInt8(v)
    }

    static func decodeGain(_ b: UInt8) -> Int {
        b >= 0x80 ? -Int(b & 0x7F) : Int(b)
    }

    static let eqBands = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    static let autoOffChoices = [0, 5, 15, 30, 45, 60]
    static let micPresets = [0x20, 0x21, 0x22, 0x23]
}
