import AppIntents
import SwiftUI
import WidgetKit

// Controles para a Central de Controle / barra de menu (macOS 26+).
// Ajustes do Sistema › Central de Controle, ou "Editar Controles" na própria Central.

@available(macOS 26.0, *)
struct HeadsetValue: ControlValueProvider {
    var previewValue: HeadsetSnapshot { .placeholder }
    func currentValue() async throws -> HeadsetSnapshot {
        SharedStore.load(HeadsetSnapshot.self, "headset") ?? HeadsetSnapshot()
    }
}

@available(macOS 26.0, *)
struct MouseValue: ControlValueProvider {
    var previewValue: MouseSnapshot { .placeholder }
    func currentValue() async throws -> MouseSnapshot {
        SharedStore.load(MouseSnapshot.self, "mouse") ?? MouseSnapshot()
    }
}

/// Botão que alterna Desligado → Cancelamento → Ambiente e mostra o modo atual.
@available(macOS 26.0, *)
struct AudioModeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.fone.blackshark.control.audiomode", provider: HeadsetValue()) { s in
            ControlWidgetButton(action: CycleAudioModeIntent()) {
                Label {
                    Text("Modo de áudio")
                    Text(s.connected ? (s.ancMode?.title ?? "—") : "Fone desligado")
                } icon: {
                    Image(systemName: s.connected ? (s.ancMode?.symbol ?? "headphones") : "headphones.slash")
                }
            }
        }
        .displayName("Modo de áudio do fone")
        .description("Alterna entre desligado, cancelamento de ruído e ambiente.")
    }
}

@available(macOS 26.0, *)
struct NoiseCancellingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.fone.blackshark.control.anc", provider: HeadsetValue()) { s in
            ControlWidgetToggle("Cancelamento de ruído", isOn: s.ancMode == .anc, action: ToggleNoiseCancellingIntent()) { on in
                Label(on ? "Ligado" : "Desligado", systemImage: on ? "ear.trianglebadge.exclamationmark" : "ear.badge.waveform")
            }
            .tint(.green)
        }
        .displayName("Cancelamento de ruído")
        .description("Liga e desliga o ANC do BlackShark V3 Pro.")
    }
}

@available(macOS 26.0, *)
struct AmbientControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.fone.blackshark.control.ambient", provider: HeadsetValue()) { s in
            ControlWidgetToggle("Modo ambiente", isOn: s.ancMode == .ambient, action: ToggleAmbientIntent()) { on in
                Label(on ? "Ligado" : "Desligado", systemImage: "ear")
            }
            .tint(.blue)
        }
        .displayName("Modo ambiente")
        .description("Liga e desliga o modo ambiente do BlackShark V3 Pro.")
    }
}

@available(macOS 26.0, *)
struct DPIControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.fone.blackshark.control.dpi", provider: MouseValue()) { m in
            ControlWidgetButton(action: NextDPIStageIntent()) {
                Label {
                    Text("DPI do mouse")
                    Text(m.connected ? (m.dpi.map { "\($0) DPI" } ?? "—") : "Mouse desligado")
                } icon: {
                    Image(systemName: "computermouse")
                }
            }
        }
        .displayName("DPI do mouse")
        .description("Passa para o próximo estágio de DPI do Attack Shark X6.")
    }
}

/// Mostra a bateria dos dois; tocar atualiza.
@available(macOS 26.0, *)
struct BatteryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dev.fone.blackshark.control.battery", provider: BothValue()) { v in
            ControlWidgetButton(action: RefreshDevicesIntent()) {
                Label {
                    Text("Bateria")
                    Text(v.summary)
                } icon: {
                    Image(systemName: v.headset.charging ? "battery.100percent.bolt" : "battery.75percent")
                }
            }
        }
        .displayName("Bateria do fone e mouse")
        .description("Mostra a bateria do BlackShark V3 Pro e do Attack Shark X6.")
    }
}

@available(macOS 26.0, *)
struct BothValue: ControlValueProvider {
    struct Value {
        var headset: HeadsetSnapshot
        var mouse: MouseSnapshot
        var summary: String {
            let h = headset.connected ? headset.battery.map { "Fone \($0)%" } ?? "Fone —" : "Fone off"
            let m = mouse.connected ? mouse.battery.map { "Mouse \($0)%" } ?? "Mouse —" : "Mouse off"
            return "\(h) · \(m)"
        }
    }
    var previewValue: Value { Value(headset: .placeholder, mouse: .placeholder) }
    func currentValue() async throws -> Value {
        Value(headset: SharedStore.load(HeadsetSnapshot.self, "headset") ?? HeadsetSnapshot(),
              mouse: SharedStore.load(MouseSnapshot.self, "mouse") ?? MouseSnapshot())
    }
}
