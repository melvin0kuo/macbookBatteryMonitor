import Observation
import SwiftUI

enum PowerFlowLevel { case overview, components, chip }

enum PanelPage {
    case main
    case settings
    case chargingPlan
    /// 設定 → 顯示項目
    case displayItems
}

enum BottomTab: String, CaseIterable {
    case details = "詳細資訊"
    case history = "電量歷史"
    case processes = "耗電排行"
    case peripherals = "周邊設備"
    case recap = "今日"
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case hour = "1 小時"
    case day = "24 小時"
    case week = "7 天"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .hour: return 3600
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        }
    }
}

/// 面板的介面狀態。
/// 只裝 Command Line Tools 時沒有 SwiftUI 的 macro 外掛，不能用 @State，所以集中放在這裡。
@MainActor
@Observable
final class PanelState {
    /// 面板關閉時設為 false，畫面會換成空白，不再監聽任何資料
    var isVisible = false
    var powerFlowLevel: PowerFlowLevel = .overview
    var page: PanelPage = .main
    var tab: BottomTab = .details
    var historyRange: HistoryRange = .day
    var chargingWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    var chargingTime: Date = Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date()
    var customChargingDeadline: Date = Date().addingTimeInterval(4 * 3600)
    /// 設定頁等可捲動頁面量到的內容高度，下次打開直接用，面板不必先撐到最高再縮回來
    var pageHeights: [PanelPage: CGFloat] = [:]
    var loginStatus: LoginItem.Status = .disabled
    var loginError: String?

    func binding<T>(_ keyPath: ReferenceWritableKeyPath<PanelState, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}
