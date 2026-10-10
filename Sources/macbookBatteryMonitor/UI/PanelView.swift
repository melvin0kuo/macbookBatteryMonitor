import SwiftUI

struct RootView: View {
    let store: BatteryStore
    let settings: AppSettings
    let ui: PanelState

    var body: some View {
        Group {
            if !ui.isVisible {
                Color.clear.frame(height: 1)
            } else {
                switch ui.page {
                case .main: PanelView(store: store, settings: settings, ui: ui)
                case .settings: SettingsView(settings: settings, ui: ui)
                }
            }
        }
        .frame(width: 380)
    }
}

struct PanelView: View {
    let store: BatteryStore
    let settings: AppSettings
    let ui: PanelState

    var body: some View {
        VStack(spacing: 10) {
            if let s = store.snapshot, let e = store.estimates {
                HeaderView(s: s, e: e, lowThreshold: settings.lowThreshold)
                TimeCard(s: s, e: e, unpluggedAt: store.unpluggedAt, fullThreshold: settings.fullThreshold)
                PowerFlowView(s: s, e: e)
                Picker("", selection: ui.binding(\.tab)) {
                    ForEach(BottomTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Group {
                    switch ui.tab {
                    case .details: DetailsGridView(s: s, e: e, health: store.systemHealth)
                    case .history: HistoryChartView(history: store.history, ui: ui)
                    case .processes: TopProcessesView(store: store)
                    }
                }
                .frame(height: 222, alignment: .top)
                footer(updated: s.date)
            } else {
                ContentUnavailableView("找不到電池", systemImage: "battery.0percent", description: Text("這台 Mac 沒有內建電池。"))
                footer(updated: nil)
            }
        }
        .padding(14)
    }

    private func footer(updated: Date?) -> some View {
        HStack(spacing: 12) {
            if let updated {
                Text("更新於 \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                ui.page = .settings
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("設定")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("結束電池監控")
        }
    }
}

private struct HeaderView: View {
    let s: BatterySnapshot
    let e: Estimates
    let lowThreshold: Int

    var body: some View {
        HStack(spacing: 14) {
            BatteryGlyph(percent: s.percent, state: e.state, lowThreshold: lowThreshold, limit: s.chargeLimit?.limit)
                .frame(width: 62, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(s.percent)%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Label(e.state.title, systemImage: e.state.symbol)
                    .font(.callout)
                    .foregroundStyle(e.state.tint)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(headline.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(headline.value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    private var headline: (caption: String, value: String) {
        switch e.state {
        case .discharging:
            return ("剩餘時間", e.headlineToEmpty.map { Format.duration($0) } ?? "計算中…")
        case .charging:
            if let limit = s.chargeLimit?.limit, s.percent < limit {
                return ("充到 \(limit)% 還要", e.toLimit.map { Format.duration($0) } ?? "計算中…")
            }
            return ("充滿還要", e.toFull.map { Format.duration($0) } ?? "計算中…")
        case .pluggedIdle:
            return ("電源供電", "暫停充電")
        case .full:
            return ("電源供電", "已充飽")
        case .limitReached:
            return ("充電上限", s.chargeLimit.map { "\($0.limit)%" } ?? "—")
        }
    }
}

private struct TimeCard: View {
    let s: BatterySnapshot
    let e: Estimates
    let unpluggedAt: Date?
    let fullThreshold: Int

    var body: some View {
        Card {
            switch e.state {
            case .discharging: discharging
            case .charging: charging
            case .pluggedIdle, .full, .limitReached: plugged
            }
        }
    }

    private var discharging: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle("預估可用時間", systemImage: "clock")
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    Text("")
                    Text("用到 0%").font(.caption).foregroundStyle(.secondary)
                    Text("用到 10%").font(.caption).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("系統預估").foregroundStyle(.secondary)
                    Text(e.systemToEmpty == nil ? "計算中…" : Format.duration(e.systemToEmpty))
                    Text(e.systemTo10 == nil && s.percent > Estimator.reservePercent ? "計算中…" : to10(e.systemTo10)).fontWeight(.semibold)
                }
                GridRow {
                    Text("依目前耗電").foregroundStyle(.secondary)
                    Text(Format.duration(e.liveToEmpty))
                    Text(to10(e.liveTo10)).fontWeight(.semibold)
                }
            }
            .font(.callout)
            .monospacedDigit()
            Divider()
            HStack {
                Text("已使用電池").foregroundStyle(.secondary)
                Spacer()
                Text(unpluggedAt.map { Format.since($0) } ?? "—").monospacedDigit()
            }
            .font(.callout)
            if let current = e.avgDischarge_mA {
                Text("近 3 分鐘平均放電 \(Format.milliamps(current))（約 \(Format.watts(current * Double(s.voltage_mV) / 1_000_000))）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var charging: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("充電預估", systemImage: "bolt")
            if let limit = s.chargeLimit?.limit {
                row("充到上限 (\(limit)%)", Format.duration(e.toLimit))
            } else {
                row("充滿 (100%)", Format.duration(e.toFull))
            }
            if fullThreshold < 100, s.percent < fullThreshold {
                row("充到 \(fullThreshold)%", Format.duration(Estimator.minutesToCharge(to: fullThreshold, snapshot: s, estimates: e)))
            }
            row("充電電流", Format.milliamps(e.avgCharge_mA))
            row("充入功率", Format.watts(max(0, e.batteryWatts)))
        }
    }

    private var plugged: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("電源狀態", systemImage: "powerplug")
            Text(pluggedMessage)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let limit = s.chargeLimit?.limit {
                row("充電上限", "\(limit)%（系統設定）")
                if let minutes = minutesToDrain(to: limit) {
                    row("降到上限約需", Format.duration(minutes))
                }
            }
            if let watts = s.adapter?.watts {
                row("變壓器", "\(watts) W")
            }
        }
    }

    /// 電量高於上限、macOS 正在放電時，估計多久會降到上限
    private func minutesToDrain(to limit: Int) -> Int? {
        guard s.percent > limit, s.amperage_mA < 0, let full = s.fullCharge_mAh else { return nil }
        let current = e.avgDischarge_mA ?? Double(-s.amperage_mA)
        guard current > 10 else { return nil }
        return Int((Double(full) * Double(s.percent - limit) / 100 / current * 60).rounded())
    }

    private var pluggedMessage: String {
        switch e.state {
        case .limitReached:
            let limit = s.chargeLimit?.limit ?? 100
            if s.percent > limit, s.amperage_mA < 0 {
                return "電量高於充電上限，macOS 正在讓電池慢慢放電到 \(limit)%，期間由變壓器和電池一起供電。"
            }
            if s.percent > limit {
                return "已超過系統設定的充電上限，電池暫停充電、由變壓器供電。電量降到 \(limit)% 以下後才會再充到上限。"
            }
            return "已達系統設定的充電上限，電池暫停充電，目前由變壓器供電。"
        case .full:
            return "電池已充飽，目前由變壓器供電。"
        default:
            return "已接上電源，但電池目前沒有在充電。可能是「最佳化電池充電」暫停在 80%，或電池溫度保護。"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func to10(_ minutes: Int?) -> String {
        s.percent <= Estimator.reservePercent ? "已低於 10%" : Format.duration(minutes)
    }
}
