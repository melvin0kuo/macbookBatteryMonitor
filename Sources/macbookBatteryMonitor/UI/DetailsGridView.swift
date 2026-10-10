import SwiftUI

struct DetailsGridView: View {
    let s: BatterySnapshot
    let e: Estimates
    let health: SystemHealth?

    var body: some View {
        Card(expand: true) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
                row("電壓", String(format: "%.2f V", Double(s.voltage_mV) / 1000),
                    "電流", "\(s.liveBatteryWatts == nil ? "" : "≈")\(s.effectiveAmperage_mA.formatted()) mA")
                row("電池功率", Format.watts(abs(e.batteryWatts)),
                    "系統耗電", Format.watts(e.systemWatts))
                row("系統預估", systemEstimateText,
                    "溫度", s.temperature_C.map { String(format: "%.1f °C", $0) } ?? "—")
                row("健康度", health?.maxCapacityPercent.map { "\($0)%" } ?? "—",
                    "容量推算", e.healthComputed.map { String(format: "%.1f%%", $0) } ?? "—")
                row("循環次數", cycleText,
                    "電池狀況", health?.conditionText ?? "—")
                row("剩餘容量", Format.mAh(s.remaining_mAh),
                    "滿充容量", Format.mAh(s.fullCharge_mAh))
                row("設計容量", Format.mAh(s.design_mAh),
                    "低耗電模式", s.lowPowerMode ? "開啟" : "關閉")
                row("變壓器", adapterText,
                    "充電上限", s.chargeLimit.map { "\($0.limit)%" } ?? "未設定")
            }
            .font(.callout)
        }
    }

    /// macOS 自己的預估：用電池時是剩餘時間，充電時是充滿時間
    private var systemEstimateText: String {
        switch e.state {
        case .discharging:
            return e.systemToEmpty.map { Format.duration($0) } ?? "計算中…"
        case .charging:
            return e.toFull.map { "充滿 \(Format.clock($0) ?? "")" } ?? "計算中…"
        case .pluggedIdle, .full, .limitReached:
            return "接電中"
        }
    }

    private var cycleText: String {
        if let design = s.designCycleCount { return "\(s.cycleCount) / \(design)" }
        return "\(s.cycleCount)"
    }

    private var adapterText: String {
        guard s.externalConnected else { return "未連接" }
        if let watts = s.adapter?.watts { return "\(watts) W" }
        return "已連接"
    }

    private func row(_ l1: String, _ v1: String, _ l2: String, _ v2: String) -> some View {
        GridRow {
            Text(l1).foregroundStyle(.secondary)
            Text(v1).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
            Text(l2).foregroundStyle(.secondary)
            Text(v2).monospacedDigit().frame(maxWidth: .infinity, alignment: .leading)
        }
        .lineLimit(1)
    }
}
