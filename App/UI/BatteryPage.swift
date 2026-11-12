import Charts
import SwiftUI

struct BatteryPage: View {
    @EnvironmentObject var model: AppModel
    @State private var range = 1 // 0 = 6 h, 1 = 24 h, 2 = 7 dias

    private var since: Date {
        Date.now.addingTimeInterval(-[6 * 3600.0, 86400, 7 * 86400][range])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Bateria", symbol: "battery.75percent",
                       subtitle: "Histórico dos últimos dias e estimativa de quanto ainda dura.")
            HStack(spacing: 12) {
                summary(.headset, level: model.headset.snapshot.connected ? model.headset.snapshot.battery : nil,
                        charging: model.headset.snapshot.charging, tint: Theme.headsetTint)
                summary(.mouse, level: model.mouse.snapshot.connected ? model.mouse.snapshot.battery : nil,
                        charging: false, tint: Theme.mouseTint)
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Histórico", symbol: "chart.xyaxis.line",
                                 trailing: AnyView(Picker("", selection: $range) {
                                     Text("6 h").tag(0); Text("24 h").tag(1); Text("7 dias").tag(2)
                                 }.pickerStyle(.segmented).labelsHidden().frame(width: 200)))
                    let points = DeviceKind.allCases.flatMap { model.history.samples(for: $0, since: since) }
                    if points.isEmpty {
                        Text("Ainda sem dados — o SharkBar registra a bateria enquanto está aberto.")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        Chart(points, id: \.date) { s in
                            LineMark(x: .value("Hora", s.date), y: .value("Bateria", s.level))
                                .foregroundStyle(by: .value("Aparelho", s.device.title))
                                .interpolationMethod(.monotone)
                            if s.charging {
                                PointMark(x: .value("Hora", s.date), y: .value("Bateria", s.level))
                                    .symbol(.circle).symbolSize(12)
                                    .foregroundStyle(by: .value("Aparelho", s.device.title))
                            }
                        }
                        .chartForegroundStyleScale(["BlackShark V3 Pro": Theme.headsetTint, "Attack Shark X6": Theme.mouseTint])
                        .chartYScale(domain: 0...100)
                        .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                            AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") }
                        } }
                        .frame(height: 240)
                        Text("Pontos marcam leituras durante a carga.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Avisos", symbol: "bell.badge")
                    Toggle("Avisar quando a bateria ficar fraca", isOn: binding(\.lowBatteryAlert))
                    HStack {
                        Text("Limite").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(model.settings.data.lowBatteryThreshold) },
                                              set: { model.settings.data.lowBatteryThreshold = Int($0) }), in: 5...50, step: 5)
                            .tint(Theme.accent)
                        Text("\(model.settings.data.lowBatteryThreshold)%").monospacedDigit().frame(width: 40)
                    }
                    .disabled(!model.settings.data.lowBatteryAlert)
                    Toggle("Avisar quando o fone terminar de carregar", isOn: binding(\.chargedAlert))
                }
                .toggleStyle(.switch)
            }
        }
    }

    private func binding(_ kp: WritableKeyPath<SettingsData, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings.data[keyPath: kp] }, set: { model.settings.data[keyPath: kp] = $0 })
    }

    private func summary(_ d: DeviceKind, level: Int?, charging: Bool, tint: Color) -> some View {
        Card {
            HStack(spacing: 14) {
                BatteryRing(level: level, charging: charging, symbol: d.symbol, lineWidth: 7, fontSize: 15)
                    .frame(width: 66, height: 66)
                VStack(alignment: .leading, spacing: 4) {
                    Text(d.title).font(.headline)
                    if level == nil { Text("Desconectado").foregroundStyle(.secondary) }
                    else if charging { Text("Carregando").foregroundStyle(Theme.accent) }
                    else if let t = model.history.remaining(for: d) { Text("\(BatteryHistory.format(t)) restantes").foregroundStyle(.secondary) }
                    else { Text("Calculando duração…").foregroundStyle(.secondary) }
                }
                Spacer()
            }
        }
    }
}
