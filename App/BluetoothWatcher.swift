import Foundation
import IOBluetooth

/// Vê se um aparelho pareado está conectado por Bluetooth (e a bateria, quando o macOS sabe).
enum BluetoothWatcher {
    struct Status {
        var connected: Bool
        var battery: Int?
    }

    /// `match`: trechos do nome Bluetooth, ex. ["BlackShark"] ou ["X6", "Attack Shark"].
    static func status(matching match: [String]) -> Status {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return Status(connected: false)
        }
        for d in devices {
            let name = d.name ?? ""
            guard match.contains(where: { name.localizedCaseInsensitiveContains($0) }) else { continue }
            if d.isConnected() {
                return Status(connected: true, battery: battery(of: d))
            }
        }
        return Status(connected: false)
    }

    /// Propriedades privadas que o macOS preenche para fones/mouses BT; nem todo aparelho informa.
    private static func battery(of d: IOBluetoothDevice) -> Int? {
        for key in ["batteryPercentSingle", "batteryPercentCombined", "batteryPercentLeft"] {
            if d.responds(to: NSSelectorFromString(key)), let v = d.value(forKey: key) as? Int, (1...100).contains(v) {
                return v
            }
        }
        return nil
    }
}
