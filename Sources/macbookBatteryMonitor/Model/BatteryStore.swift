import Foundation
import Observation

@MainActor
@Observable
final class BatteryStore {
    private(set) var snapshot: BatterySnapshot?
    private(set) var estimates: Estimates?
    private(set) var systemHealth: SystemHealth?
    private(set) var topProcesses: [EnergyProcess] = []
    private(set) var processesLoaded = false
    /// 這次拔掉電源的時間，用來算「已使用電池多久」
    private(set) var unpluggedAt: Date?
    let history = HistoryStore()

    /// 平滑電流用的時間常數（秒），約等於「近 3 分鐘平均」
    @ObservationIgnored private let tau: Double = 180
    @ObservationIgnored private var avgDischarge: Double?
    @ObservationIgnored private var avgCharge: Double?
    @ObservationIgnored private var lastDate: Date?
    @ObservationIgnored private var lastState: PowerState?
    /// 這次接上電源的時間（判斷充電上限是否已被關掉用）
    @ObservationIgnored private var pluggedSince: Date?
    @ObservationIgnored private var loadingProcesses = false
    /// 面板開著才允許跑 top，避免關掉後還在背景取樣
    @ObservationIgnored var panelVisible = false

    init() {
        unpluggedAt = history.lastUnplugged()
    }

    func refresh() {
        // 溫度要另外問 SMC，只有面板開著時才需要
        guard var s = BatteryReader.read(includeTemperature: panelVisible) else {
            snapshot = nil
            estimates = nil
            return
        }
        if s.externalConnected {
            if pluggedSince == nil { pluggedSince = s.date }
        } else {
            pluggedSince = nil
        }
        s.chargeLimit = ChargeLimitReader.resolve(externalConnected: s.externalConnected, pluggedSince: pluggedSince)
        let state = Estimator.state(s)
        let dt = lastDate.map { s.date.timeIntervalSince($0) } ?? 0

        if state != lastState {
            if lastState != nil {
                avgDischarge = nil
                avgCharge = nil
            }
            if state == .discharging {
                if lastState != nil { unpluggedAt = s.date }
            } else {
                unpluggedAt = nil
            }
        }
        let current = Double(abs(s.amperage_mA))
        if s.amperage_mA < 0 {
            avgDischarge = ema(avgDischarge, current, dt)
        } else if s.amperage_mA > 0 {
            avgCharge = ema(avgCharge, current, dt)
        }
        lastDate = s.date
        lastState = state

        snapshot = s
        estimates = Estimator.estimates(s, avgDischarge_mA: avgDischarge, avgCharge_mA: avgCharge)
    }

    func recordHistory() {
        guard let s = snapshot, let e = estimates else { return }
        history.add(HistorySample(
            t: s.date,
            pct: s.percent,
            watts: e.systemWatts ?? max(0, -e.batteryWatts),
            plugged: s.externalConnected,
            charging: s.isCharging
        ))
    }

    func refreshHealth() {
        Task {
            if let health = await SystemProfiler.read() {
                systemHealth = health
            }
        }
    }

    func backfillHistory() {
        Task {
            history.backfill(await PowerLog.chargeHistory())
        }
    }

    /// App 剛啟動且歷史紀錄裡找不到拔電時間時，從 pmset 紀錄補
    func resolveUnpluggedDateIfNeeded() {
        guard unpluggedAt == nil, estimates?.state == .discharging else { return }
        Task {
            if let date = await PowerLog.lastUnpluggedDate(), unpluggedAt == nil, estimates?.state == .discharging {
                unpluggedAt = date
            }
        }
    }

    func refreshProcesses() async {
        guard panelVisible, !loadingProcesses else { return }
        loadingProcesses = true
        let result = await ProcessEnergy.sample()
        topProcesses = result
        processesLoaded = true
        loadingProcesses = false
    }

    private func ema(_ previous: Double?, _ value: Double, _ dt: Double) -> Double {
        guard let previous, dt > 0 else { return value }
        let alpha = 1 - exp(-dt / tau)
        return previous + alpha * (value - previous)
    }
}
