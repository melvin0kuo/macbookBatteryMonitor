import Foundation
import Observation

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case iconAndPercent
    case iconOnly
    case percentOnly
    case iconAndTime
    case iconPercentAndTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconAndPercent: return "圖示 + 百分比"
        case .iconOnly: return "只有圖示"
        case .percentOnly: return "只有百分比"
        case .iconAndTime: return "圖示 + 剩餘時間"
        case .iconPercentAndTime: return "圖示內百分比 + 剩餘時間"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// 影響選單列圖示的設定改變時呼叫
    @ObservationIgnored var onChange: (() -> Void)?
    /// 系統監控模組開關改變時呼叫
    @ObservationIgnored var onMonitorsChange: (() -> Void)?
    /// 更新頻率或省電模式改變時呼叫（重設所有取樣間隔）
    @ObservationIgnored var onIntervalChange: (() -> Void)?
    @ObservationIgnored var onPreciseChargingChange: (() -> Void)?

    /// 可選的更新頻率（秒）
    static let updateIntervals = [1, 2, 5, 10]

    /// 更新頻率（秒），預設每秒
    var updateInterval: Int {
        didSet { defaults.set(updateInterval, forKey: Keys.updateInterval); onIntervalChange?() }
    }

    /// 省電模式：電力流向改用靜態圖示、不播放動畫，更新頻率至少每 2 秒
    var powerSaving: Bool {
        didSet { defaults.set(powerSaving, forKey: Keys.powerSaving); onIntervalChange?() }
    }

    /// 電池、系統監控、耗電排行共用的取樣間隔（秒）
    var sampleInterval: TimeInterval { TimeInterval(powerSaving ? max(2, updateInterval) : updateInterval) }

    /// 介面上顯示的更新頻率
    var updateText: String { Self.updateText(seconds: Int(sampleInterval)) }

    static func updateText(seconds: Int) -> String { seconds <= 1 ? "每秒更新" : "每 \(seconds) 秒更新" }

    /// 每個系統監控模組是否在選單列顯示（並依取樣間隔更新）
    var monitorCPU: Bool {
        didSet { defaults.set(monitorCPU, forKey: Keys.monitorCPU); onMonitorsChange?() }
    }
    var monitorMemory: Bool {
        didSet { defaults.set(monitorMemory, forKey: Keys.monitorMemory); onMonitorsChange?() }
    }
    var monitorDisk: Bool {
        didSet { defaults.set(monitorDisk, forKey: Keys.monitorDisk); onMonitorsChange?() }
    }
    var monitorNetwork: Bool {
        didSet { defaults.set(monitorNetwork, forKey: Keys.monitorNetwork); onMonitorsChange?() }
    }

    func isMonitorEnabled(_ kind: MonitorKind) -> Bool {
        switch kind {
        case .cpu: return monitorCPU
        case .memory: return monitorMemory
        case .disk: return monitorDisk
        case .network: return monitorNetwork
        }
    }

    /// 選用的管理員 CPU 取樣（預設關閉）。開啟時安裝系統服務，關閉時移除；由 AdminCPUSampler 在下一次更新時套用
    var adminCPUSampling: Bool {
        didSet { defaults.set(adminCPUSampling, forKey: Keys.adminCPUSampling) }
    }

    var chargingVisualStyle: ChargingVisualStyle {
        didSet { defaults.set(chargingVisualStyle.rawValue, forKey: Keys.chargingVisualStyle) }
    }
    var chargingHoldPercent: Int {
        didSet { defaults.set(chargingHoldPercent, forKey: Keys.chargingHoldPercent) }
    }
    var chargingTargetPercent: Int {
        didSet {
            defaults.set(chargingTargetPercent, forKey: Keys.chargingTargetPercent)
            if chargingHoldPercent > chargingTargetPercent { chargingHoldPercent = chargingTargetPercent }
        }
    }
    var chargingSleepStrategy: ChargingSleepStrategy {
        didSet { defaults.set(chargingSleepStrategy.rawValue, forKey: Keys.chargingSleepStrategy) }
    }
    var preciseChargingScheduling: Bool {
        didSet {
            defaults.set(preciseChargingScheduling, forKey: Keys.preciseChargingScheduling)
            onPreciseChargingChange?()
        }
    }

    /// 電力流向細項中隱藏的項目（FlowItem.rawValue）
    var hiddenFlowItems: Set<String> {
        didSet { defaults.set(hiddenFlowItems.sorted(), forKey: Keys.hiddenFlowItems) }
    }
    /// 詳細資訊分頁中隱藏的欄位（DetailField.rawValue）
    var hiddenDetailFields: Set<String> {
        didSet { defaults.set(hiddenDetailFields.sorted(), forKey: Keys.hiddenDetailFields) }
    }
    /// 每個周邊設備的低電量通知門檻（設備 id → %，0 表示關閉）；沒設定過的設備用預設值
    var peripheralThresholds: [String: Int] {
        didSet { defaults.set(peripheralThresholds, forKey: Keys.peripheralThresholds) }
    }
    static let defaultPeripheralThreshold = 20
    static let peripheralThresholdChoices = [0, 10, 15, 20, 30, 50]

    func isVisible(_ item: FlowItem) -> Bool { !hiddenFlowItems.contains(item.rawValue) }
    func isVisible(_ field: DetailField) -> Bool { !hiddenDetailFields.contains(field.rawValue) }
    func setVisible(_ item: FlowItem, _ visible: Bool) {
        if visible { hiddenFlowItems.remove(item.rawValue) } else { hiddenFlowItems.insert(item.rawValue) }
    }
    func setVisible(_ field: DetailField, _ visible: Bool) {
        if visible { hiddenDetailFields.remove(field.rawValue) } else { hiddenDetailFields.insert(field.rawValue) }
    }
    func peripheralThreshold(for id: String) -> Int { peripheralThresholds[id] ?? Self.defaultPeripheralThreshold }
    func setPeripheralThreshold(_ value: Int, for id: String) { peripheralThresholds[id] = value }

    /// App 圖示的背景色；改變時立刻套用到 App 本身（失敗原因放在 appIconError）
    var appIconColor: AppIconColor {
        didSet {
            defaults.set(appIconColor.rawValue, forKey: Keys.appIconColor)
            appIconError = AppIconChanger.apply(appIconColor)
        }
    }
    private(set) var appIconError: String?

    /// 每天自動檢查一次 GitHub 上有沒有新版本（只檢查，不會自動安裝）
    var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Keys.autoCheckUpdates) }
    }

    var display: MenuBarDisplay {
        didSet { defaults.set(display.rawValue, forKey: Keys.display); onChange?() }
    }
    var lowAlertEnabled: Bool {
        didSet { defaults.set(lowAlertEnabled, forKey: Keys.lowAlertEnabled) }
    }
    var lowThreshold: Int {
        didSet { defaults.set(lowThreshold, forKey: Keys.lowThreshold); onChange?() }
    }
    var fullAlertEnabled: Bool {
        didSet { defaults.set(fullAlertEnabled, forKey: Keys.fullAlertEnabled) }
    }
    var fullThreshold: Int {
        didSet { defaults.set(fullThreshold, forKey: Keys.fullThreshold) }
    }

    private enum Keys {
        static let display = "menuBarDisplay"
        static let lowAlertEnabled = "lowAlertEnabled"
        static let lowThreshold = "lowThreshold"
        static let fullAlertEnabled = "fullAlertEnabled"
        static let fullThreshold = "fullThreshold"
        static let monitorCPU = "monitorCPU"
        static let monitorMemory = "monitorMemory"
        static let monitorDisk = "monitorDisk"
        static let monitorNetwork = "monitorNetwork"
        static let powerSaving = "powerSaving"
        static let updateInterval = "updateInterval"
        static let hiddenFlowItems = "hiddenFlowItems"
        static let hiddenDetailFields = "hiddenDetailFields"
        static let peripheralThresholds = "peripheralThresholds"
        static let appIconColor = "appIconColor"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let adminCPUSampling = "adminCPUSampling"
        static let chargingVisualStyle = "chargingVisualStyle"
        static let chargingHoldPercent = "chargingHoldPercent"
        static let chargingTargetPercent = "chargingTargetPercent"
        static let chargingSleepStrategy = "chargingSleepStrategy"
        static let preciseChargingScheduling = "preciseChargingScheduling"
    }

    private init() {
        defaults.register(defaults: [
            Keys.display: MenuBarDisplay.iconAndPercent.rawValue,
            Keys.lowAlertEnabled: true,
            Keys.lowThreshold: 20,
            Keys.fullAlertEnabled: true,
            Keys.fullThreshold: 100,
            Keys.monitorCPU: true,
            Keys.monitorMemory: true,
            Keys.monitorDisk: true,
            Keys.monitorNetwork: true,
            Keys.powerSaving: false,
            Keys.updateInterval: 1,
            Keys.adminCPUSampling: false,
            Keys.autoCheckUpdates: true,
            Keys.chargingVisualStyle: ChargingVisualStyle.energy.rawValue,
            Keys.chargingHoldPercent: 80,
            Keys.chargingTargetPercent: 100,
            Keys.chargingSleepStrategy: ChargingSleepStrategy.readinessFirst.rawValue,
            Keys.preciseChargingScheduling: false,
        ])
        adminCPUSampling = defaults.bool(forKey: Keys.adminCPUSampling)
        display = MenuBarDisplay(rawValue: defaults.string(forKey: Keys.display) ?? "") ?? .iconAndPercent
        lowAlertEnabled = defaults.bool(forKey: Keys.lowAlertEnabled)
        lowThreshold = defaults.integer(forKey: Keys.lowThreshold)
        fullAlertEnabled = defaults.bool(forKey: Keys.fullAlertEnabled)
        fullThreshold = defaults.integer(forKey: Keys.fullThreshold)
        monitorCPU = defaults.bool(forKey: Keys.monitorCPU)
        monitorMemory = defaults.bool(forKey: Keys.monitorMemory)
        monitorDisk = defaults.bool(forKey: Keys.monitorDisk)
        monitorNetwork = defaults.bool(forKey: Keys.monitorNetwork)
        powerSaving = defaults.bool(forKey: Keys.powerSaving)
        let interval = defaults.integer(forKey: Keys.updateInterval)
        updateInterval = Self.updateIntervals.contains(interval) ? interval : 1
        hiddenFlowItems = Set(defaults.stringArray(forKey: Keys.hiddenFlowItems) ?? [])
        hiddenDetailFields = Set(defaults.stringArray(forKey: Keys.hiddenDetailFields) ?? [])
        peripheralThresholds = defaults.dictionary(forKey: Keys.peripheralThresholds) as? [String: Int] ?? [:]
        appIconColor = AppIconColor(rawValue: defaults.string(forKey: Keys.appIconColor) ?? "") ?? .mint
        autoCheckUpdates = defaults.bool(forKey: Keys.autoCheckUpdates)
        chargingVisualStyle = ChargingVisualStyle(rawValue: defaults.string(forKey: Keys.chargingVisualStyle) ?? "") ?? .energy
        chargingHoldPercent = max(50, min(100, defaults.integer(forKey: Keys.chargingHoldPercent)))
        chargingTargetPercent = max(50, min(100, defaults.integer(forKey: Keys.chargingTargetPercent)))
        chargingSleepStrategy = ChargingSleepStrategy(rawValue: defaults.string(forKey: Keys.chargingSleepStrategy) ?? "") ?? .readinessFirst
        preciseChargingScheduling = defaults.bool(forKey: Keys.preciseChargingScheduling)
    }
}
