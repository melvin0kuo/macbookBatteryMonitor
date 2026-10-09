import Observation
import SwiftUI

enum PanelPage {
    case main
    case settings
}

enum BottomTab: String, CaseIterable {
    case details = "詳細資訊"
    case history = "電量歷史"
    case processes = "耗電排行"
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
    var page: PanelPage = .main
    var tab: BottomTab = .details
    var historyRange: HistoryRange = .day
    var loginStatus: LoginItem.Status = .disabled
    var loginError: String?

    func binding<T>(_ keyPath: ReferenceWritableKeyPath<PanelState, T>) -> Binding<T> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }
}
