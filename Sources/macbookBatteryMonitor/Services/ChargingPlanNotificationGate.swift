import Foundation

enum ChargingPlanNotification: Equatable {
    case ready
    case late
}

enum ChargingPlanNotificationGate {
    static func evaluate(previous: ChargingPlanPhase?, current: ChargingPlanPhase?) -> ChargingPlanNotification? {
        guard previous != current else { return nil }
        switch current {
        case .ready: return .ready
        case .late: return .late
        default: return nil
        }
    }
}
