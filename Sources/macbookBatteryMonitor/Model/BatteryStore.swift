import Foundation
import Observation
import IOKit.pwr_mgt

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
    let adminCPU = AdminCPUSampler()
    /// 周邊設備電量（鍵盤、滑鼠、耳機等）
    let peripherals = PeripheralStore()
    /// 一鍵更新
    let updater = Updater()
    /// 主面板的充電上限滑桿（調整 macOS 系統設定裡的充電上限）
    let chargeLimit = SystemChargeLimit()
    let chargingPlan = ChargingPlanController()
    let chargingWake = ChargingWakeScheduler()
    private(set) var componentPower: ComponentPowerSample?
    private(set) var breakdown = PowerBreakdown(systemWatts: nil, status: .sampling)
    @ObservationIgnored private let hardwareWorker = HardwarePowerWorker()
    @ObservationIgnored private var samplingGate = SamplingGate()

    func setHardwareSampling(active: Bool) {
        adminCPU.update(active: active, enabled: AppSettings.shared.adminCPUSampling)
        let changed = samplingGate.active != active
        samplingGate.setActive(active)
        if !active {
            if changed {
                componentPower = nil
                breakdown = PowerBreakdown(systemWatts: estimates?.systemWatts, status: .sampling)
                let generation = samplingGate.generation
                Task { await hardwareWorker.stop(generation: generation) }
            }
            return
        }
        guard let ticket = samplingGate.begin() else { return }
        Task {
            let result = await hardwareWorker.sample(generation: ticket)
            guard samplingGate.finish(ticket), var result else { return }
            if AppSettings.shared.adminCPUSampling { result.cpuWatts = adminCPU.watts }
            componentPower = result
            breakdown = PowerBreakdown.make(systemWatts: result.systemWatts,
                components: result, now: ProcessInfo.processInfo.systemUptime)
        }
    }


    /// 平滑電流用的時間常數（秒），約等於「近 3 分鐘平均」
    @ObservationIgnored private let tau: Double = 180
    @ObservationIgnored private var avgDischarge: Double?
    @ObservationIgnored private var avgCharge: Double?
    @ObservationIgnored private var lastDate: Date?
    @ObservationIgnored private var lastState: PowerState?
    @ObservationIgnored private var chargingPresentation = ChargingPresentation()
    @ObservationIgnored private var flowPresentation = PowerFlowPresentation()
    /// 這次接上電源的時間（判斷充電上限是否已被關掉用）
    @ObservationIgnored private var pluggedSince: Date?
    @ObservationIgnored private var processStream: ProcessEnergyStream?
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
            chargingPresentation = ChargingPresentation()
            flowPresentation = PowerFlowPresentation()
            return
        }
        if s.externalConnected {
            if pluggedSince == nil { pluggedSince = s.date }
        } else {
            pluggedSince = nil
        }
        s.chargeLimit = ChargeLimitReader.resolve(externalConnected: s.externalConnected, pluggedSince: pluggedSince)
        let state = chargingPresentation.state(s, uptime: ProcessInfo.processInfo.systemUptime)
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
        let current = Double(abs(s.effectiveAmperage_mA))
        if s.effectiveAmperage_mA < 0 {
            avgDischarge = ema(avgDischarge, current, dt)
        } else if s.effectiveAmperage_mA > 0 {
            avgCharge = ema(avgCharge, current, dt)
        }
        lastDate = s.date
        lastState = state

        snapshot = s
        var computed = Estimator.estimates(s, avgDischarge_mA: avgDischarge, avgCharge_mA: avgCharge, displayState: state)
        // 接著電源但沒在充電（滿電、到達上限、暫停）時，電池功率的小幅波動不改變流向圖，與上方的狀態文字一致
        let holding = [.full, .limitReached, .pluggedIdle].contains(state) && !computed.drainingOnAC && !s.drainingAboveLimit
        computed.displayFlow = flowPresentation.kind(connected: s.externalConnected, watts: computed.batteryWatts,
            holding: holding, uptime: ProcessInfo.processInfo.systemUptime)
        estimates = computed
        evaluateChargingPlan(reason: .refresh)
    }

    func prepareChargingPlanForSleep() {
        let assertion = ChargingSleepAssertion()
        evaluateChargingPlan(reason: .willSleep) { assertion?.release() }
    }

    func reevaluateChargingPlanAfterWake() {
        evaluateChargingPlan(reason: .didWake)
    }

    func cancelChargingPlan() {
        guard let target = chargingPlan.cancel(currentLimit: chargeLimit.limit) else { return }
        applyScheduledLimit(target)
    }

    private func evaluateChargingPlan(reason: ChargingEvaluationReason, completion: (() -> Void)? = nil) {
        guard let s = snapshot, let e = estimates else { completion?(); return }
        let estimated = Estimator.minutesToCharge(to: chargingPlan.plan?.targetPercent ?? 100,
                                                   snapshot: s, estimates: e)
            ?? chargingHistoryEstimate(snapshot: s)
        let input = ChargingPlanInput(now: s.date, percent: s.percent,
                                      connected: s.externalConnected,
                                      limitSupported: chargeLimit.supported,
                                      currentLimit: chargeLimit.limit,
                                      estimatedMinutes: estimated,
                                      isCharging: e.state == .charging,
                                      systemPaused: e.state == .pluggedIdle || e.state == .limitReached)
        let target = chargingPlan.evaluate(input: input, reason: reason,
                                           preciseWakeAvailable: chargingWake.hasUsableScheduledWake)
        syncChargingWake()
        guard let target else { completion?(); return }
        applyScheduledLimit(target, refreshAfterWrite: reason != .willSleep, completion: completion)
    }

    func syncChargingWake() {
        chargingWake.sync(decision: chargingPlan.decision,
                          enabled: AppSettings.shared.preciseChargingScheduling)
    }

    private func chargingHistoryEstimate(snapshot: BatterySnapshot) -> Int? {
        guard let target = chargingPlan.plan?.targetPercent, target > snapshot.percent,
              let rate = ChargingRateEstimator.percentPerHour(samples: history.samples, now: snapshot.date) else {
            return nil
        }
        return Int(ceil(Double(target - snapshot.percent) / rate * 60))
    }

    private func applyScheduledLimit(_ target: Int, refreshAfterWrite: Bool = true,
                                     completion: (() -> Void)? = nil) {
        Task {
            let success = await chargeLimit.apply(target)
            chargingPlan.completeLimitWrite(target: target, success: success)
            if success && refreshAfterWrite { refresh() }
            completion?()
        }
    }

    func recordHistory() {
        guard let s = snapshot, let e = estimates else { return }
        history.add(HistorySample(
            t: s.date,
            pct: s.percent,
            watts: e.systemWatts ?? max(0, -e.batteryWatts),
            plugged: s.externalConnected,
            charging: e.state == .charging
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

    /// 面板開著且停在耗電排行時，持續以 top 取樣（間隔同設定）；其他時候停掉
    func setProcessSampling(active: Bool) {
        guard active, panelVisible else {
            processStream?.stop()
            return
        }
        let interval = Int(AppSettings.shared.sampleInterval)
        // 切換省電模式後，用新的間隔重新啟動 top
        if let stream = processStream, stream.interval != interval {
            stream.stop()
            processStream = nil
        }
        if processStream == nil {
            processStream = ProcessEnergyStream(interval: interval) { [weak self] result in
                MainActor.assumeIsolated {
                    self?.topProcesses = result
                    self?.processesLoaded = true
                }
            }
        }
        processStream?.start()
    }

    private func ema(_ previous: Double?, _ value: Double, _ dt: Double) -> Double {
        guard let previous, dt > 0 else { return value }
        let alpha = 1 - exp(-dt / tau)
        return previous + alpha * (value - previous)
    }

    /// 截圖用的示範數據（README、版本說明）：不含任何使用者的真實資料
    func loadPreview(now: Date = Date()) {
        var s = BatterySnapshot()
        s.date = now
        s.percent = 78
        s.voltage_mV = 12450
        s.amperage_mA = -520
        s.cycleCount = 212
        s.designCycleCount = 1000
        s.remaining_mAh = 3900
        s.fullCharge_mAh = 5000
        s.nominal_mAh = 5080
        s.design_mAh = 5500
        s.psTimeToEmpty = 445
        s.avgTimeToEmpty = 450
        s.temperature_C = 31.4
        s.smcAdapterWatts = 0
        s.smcSystemWatts = 6.5
        s.chargeLimit = ChargeLimit(limit: 80, reason: "manualChargeLimit", active: false)
        chargeLimit.loadPreview(limit: 80)
        snapshot = s
        avgDischarge = 520
        estimates = Estimator.estimates(s, avgDischarge_mA: 520, avgCharge_mA: nil)
        systemHealth = SystemHealth(maxCapacityPercent: 92, condition: "Good", cycleCount: 212)
        unpluggedAt = now.addingTimeInterval(-(2 * 3600 + 15 * 60))
        // 24 小時：前一晚接電充到 80%，早上拔掉後慢慢用到 78%
        var samples: [HistorySample] = []
        for minute in stride(from: 24 * 60, through: 0, by: -10) {
            let t = now.addingTimeInterval(-Double(minute) * 60)
            let plugged = minute > 135
            let pct = plugged ? min(80, 45 + (24 * 60 - minute) / 12) : 80 - (135 - minute) / 60
            let watts = plugged ? 4.5 + 2 * sin(Double(minute) / 37) : 6 + 2.5 * sin(Double(minute) / 9)
            samples.append(HistorySample(t: t, pct: pct, watts: max(1, watts), plugged: plugged, charging: plugged && pct < 80))
        }
        history.loadPreview(samples)
        topProcesses = [
            EnergyProcess(id: "safari", name: "Safari", power: 12.4, appPath: "/Applications/Safari.app"),
            EnergyProcess(id: "music", name: "音樂", power: 6.8, appPath: "/System/Applications/Music.app"),
            EnergyProcess(id: "mail", name: "郵件", power: 3.2, appPath: "/System/Applications/Mail.app"),
            EnergyProcess(id: "photos", name: "照片", power: 2.1, appPath: "/System/Applications/Photos.app"),
            EnergyProcess(id: "finder", name: "Finder", power: 0.9, appPath: "/System/Library/CoreServices/Finder.app"),
        ]
        processesLoaded = true
    }

    /// 開發用快照：接著電源的示範狀態（檢查充電中、已達充電上限時的版面）
    func loadPluggedPreview(now: Date = Date(), atLimit: Bool) {
        loadPreview(now: now)
        guard var s = snapshot else { return }
        s.externalConnected = true
        s.adapter = AdapterInfo(watts: 30)
        s.chargeLimit = ChargeLimit(limit: 80, reason: "manualChargeLimit", active: true)
        s.psTimeToEmpty = nil
        s.avgTimeToEmpty = nil
        if atLimit {
            s.percent = 80
            s.amperage_mA = 0
            s.smcAdapterWatts = 6.5
        } else {
            s.percent = 62
            s.amperage_mA = 1500
            s.isCharging = true
            s.smcAdapterWatts = 25
        }
        snapshot = s
        unpluggedAt = nil
        avgDischarge = nil
        avgCharge = atLimit ? nil : 1500
        estimates = Estimator.estimates(s, avgDischarge_mA: nil, avgCharge_mA: avgCharge)
    }
}

/// 睡眠通知到寫入確認之間短暫延後系統睡眠，最久由寫入本身的逾時保護結束。
private final class ChargingSleepAssertion {
    private var id: IOPMAssertionID = 0

    init?() {
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "正在套用智慧充電上限" as CFString, &id)
        guard result == kIOReturnSuccess else { return nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.release() }
    }

    func release() {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }

    deinit { release() }
}
