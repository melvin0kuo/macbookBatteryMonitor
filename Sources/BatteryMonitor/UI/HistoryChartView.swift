import Charts
import SwiftUI

struct HistoryChartView: View {
    let history: HistoryStore
    let ui: PanelState

    private var range: HistoryRange { ui.historyRange }

    var body: some View {
        let now = Date()
        let points = history.points(range: range.seconds, now: now)
        let domain = now.addingTimeInterval(-range.seconds)...now
        let wattPoints = points.filter { $0.watts != nil }

        Card(expand: true) {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("", selection: ui.binding(\.historyRange)) {
                    ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 190)
                Spacer()
                legend
            }

            if points.count < 2 {
                VStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                    Text("資料收集中，每分鐘記錄一次…")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(points) { p in
                    LineMark(
                        x: .value("時間", p.t),
                        y: .value("電量", p.pct),
                        series: .value("段", p.segment)
                    )
                    .foregroundStyle(p.plugged ? Color.green : Color.blue)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) { Text("\(v)%") }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: axisDates(domain)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: xFormat)
                    }
                }
                .padding(.trailing, 10)
                .frame(height: wattPoints.isEmpty ? 140 : 100)

                if !wattPoints.isEmpty {
                Chart(wattPoints) { p in
                    AreaMark(
                        x: .value("時間", p.t),
                        y: .value("功率", p.watts ?? 0),
                        series: .value("段", p.wattsSegment)
                    )
                    .foregroundStyle(Color.orange.opacity(0.35).gradient)
                    .interpolationMethod(.monotone)
                }
                .chartXScale(domain: domain)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int(v))W") }
                        }
                    }
                }
                .padding(.trailing, 10)
                .frame(height: 42)
                }

                Text(summary(points))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            legendItem(.blue, "用電池")
            legendItem(.green, "接電源")
            legendItem(.orange, "耗電")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }

    /// 對齊整點/整天的刻度，太靠近左右邊緣的不畫（標籤會被切掉）
    private func axisDates(_ domain: ClosedRange<Date>) -> [Date] {
        let calendar = Calendar.current
        let (component, step): (Calendar.Component, Int)
        let start: Date
        switch range {
        case .hour:
            (component, step) = (.minute, 15)
            start = calendar.dateInterval(of: .hour, for: domain.lowerBound)?.start ?? domain.lowerBound
        case .day:
            (component, step) = (.hour, 6)
            start = calendar.startOfDay(for: domain.lowerBound)
        case .week:
            (component, step) = (.day, 1)
            start = calendar.startOfDay(for: domain.lowerBound)
        }
        let margin = range.seconds * 0.07
        var dates: [Date] = []
        var date = start
        while date <= domain.upperBound {
            if date.timeIntervalSince(domain.lowerBound) > margin, domain.upperBound.timeIntervalSince(date) > margin {
                dates.append(date)
            }
            guard let next = calendar.date(byAdding: component, value: step, to: date) else { break }
            date = next
        }
        return dates
    }

    private var xFormat: Date.FormatStyle {
        range == .week ? .dateTime.month(.defaultDigits).day() : .dateTime.hour().minute()
    }

    private func summary(_ points: [ChartPoint]) -> String {
        let watts = points.compactMap(\.watts)
        let minPct = Int(points.map(\.pct).min() ?? 0)
        let maxPct = Int(points.map(\.pct).max() ?? 0)
        let range = "電量範圍 \(minPct)%–\(maxPct)%"
        guard !watts.isEmpty else { return range + " · 耗電資料收集中" }
        return "平均耗電 \(Format.watts(watts.reduce(0, +) / Double(watts.count))) · " + range
    }
}
