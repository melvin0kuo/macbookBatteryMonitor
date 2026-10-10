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
    }

    private init() {
        defaults.register(defaults: [
            Keys.display: MenuBarDisplay.iconAndPercent.rawValue,
            Keys.lowAlertEnabled: true,
            Keys.lowThreshold: 20,
            Keys.fullAlertEnabled: true,
            Keys.fullThreshold: 100,
        ])
        display = MenuBarDisplay(rawValue: defaults.string(forKey: Keys.display) ?? "") ?? .iconAndPercent
        lowAlertEnabled = defaults.bool(forKey: Keys.lowAlertEnabled)
        lowThreshold = defaults.integer(forKey: Keys.lowThreshold)
        fullAlertEnabled = defaults.bool(forKey: Keys.fullAlertEnabled)
        fullThreshold = defaults.integer(forKey: Keys.fullThreshold)
    }
}
