import Foundation
import SwiftUI

struct DailyRecapPresentation: Equatable {
    var headline: String
    var netChange: String
    var used: String
    var charged: String
    var plugIns: String
    var unplugged: String
    var longest: String

    static func make(_ recap: DailyBatteryRecap) -> DailyRecapPresentation {
        guard let start = recap.startPercent, let end = recap.endPercent else {
            return .init(headline: "今天還沒有足夠資料", netChange: "—", used: "0%",
                         charged: "0%", plugIns: "0 次", unplugged: "0 分鐘", longest: "0 分鐘")
        }
        let net = end - start
        return .init(headline: "今天使用了 \(recap.usedPercent)% 電量",
                     netChange: net > 0 ? "+\(net)%" : "\(net)%",
                     used: "\(recap.usedPercent)%", charged: "\(recap.chargedPercent)%",
                     plugIns: "\(recap.plugInCount) 次", unplugged: duration(recap.unpluggedMinutes),
                     longest: duration(recap.longestUnpluggedMinutes))
    }

    private static func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) 分鐘" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) 小時" : "\(hours) 小時 \(rest) 分"
    }
}

struct DailyRecapView: View {
    let recap: DailyBatteryRecap

    private var value: DailyRecapPresentation { .make(recap) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("今日電量回顧", systemImage: "sparkles")
                        .font(.callout.weight(.semibold))
                    Text(value.headline).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(value.netChange).font(.title3.weight(.semibold)).monospacedDigit()
                    Text("淨變化").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 8) {
                metric("使用", value.used, "battery.25percent", .orange)
                metric("補回", value.charged, "bolt.fill", .green)
                metric("接電", value.plugIns, "powerplug.fill", .cyan)
            }
            HStack(spacing: 8) {
                wideMetric("使用電池時間", value.unplugged, "clock")
                wideMetric("最長一次", value.longest, "figure.walk.motion")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("今日電量回顧。\(value.headline)。補回 \(value.charged)，接電 \(value.plugIns)，使用電池 \(value.unplugged)，最長一次 \(value.longest)")
    }

    private func metric(_ title: String, _ number: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(number).font(.headline).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func wideMetric(_ title: String, _ number: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(number).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
