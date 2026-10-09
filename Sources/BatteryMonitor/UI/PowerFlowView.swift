import SwiftUI

/// AlDente 風格的電力流向：變壓器 → 系統 ⇄ 電池
struct PowerFlowView: View {
    let s: BatterySnapshot
    let e: Estimates

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle("電力流向", systemImage: "arrow.left.arrow.right")
                HStack(spacing: 0) {
                    node(symbol: "powerplug.fill", title: "變壓器", value: adapterText, active: s.externalConnected, tint: .yellow)
                    arrow(pointingRight: true, active: s.externalConnected)
                    node(symbol: "laptopcomputer", title: "系統耗電", value: Format.watts(e.systemWatts), active: true, tint: .blue)
                    arrow(pointingRight: batteryCharging, active: batteryActive)
                    node(symbol: batterySymbol, title: batteryTitle, value: Format.watts(abs(e.batteryWatts)), active: batteryActive,
                         tint: batteryCharging ? .green : .orange)
                }
            }
        }
    }

    private var batteryActive: Bool { abs(e.batteryWatts) >= 0.05 }
    private var batteryCharging: Bool { e.batteryWatts > 0 }
    private var batteryTitle: String {
        guard batteryActive else { return "電池閒置" }
        return batteryCharging ? "充入電池" : "電池放電"
    }

    private var adapterText: String {
        guard s.externalConnected else { return "未連接" }
        if let input = e.adapterInputWatts { return Format.watts(input) }
        if let rated = s.adapter?.watts { return "\(rated) W 額定" }
        return "已連接"
    }

    private var batterySymbol: String {
        if batteryCharging { return "battery.100percent.bolt" }
        switch s.percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private func node(symbol: String, title: String, value: String, active: Bool, tint: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(tint.opacity(active ? 0.18 : 0.06))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(active ? tint : Color.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(active ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func arrow(pointingRight: Bool, active: Bool) -> some View {
        Image(systemName: pointingRight ? "chevron.right.2" : "chevron.left.2")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(active ? Color.accentColor : Color.secondary.opacity(0.3))
            .offset(y: -16)
    }
}
