import Foundation

enum ChargingSleepStrategy: String, Codable, CaseIterable, Identifiable {
    case readinessFirst
    case preciseWake

    var id: String { rawValue }
}

enum ChargingSchedule: Codable, Equatable {
    case oneOff(Date)
    /// Calendar weekday uses 1 = Sunday ... 7 = Saturday.
    case recurring(weekdays: Set<Int>, minuteOfDay: Int)

    func nextDeadline(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .oneOff(let deadline):
            return deadline > date ? deadline : nil
        case .recurring(let weekdays, let minuteOfDay):
            guard (0..<(24 * 60)).contains(minuteOfDay) else { return nil }
            let validDays = weekdays.filter { (1...7).contains($0) }
            guard !validDays.isEmpty else { return nil }
            let hour = minuteOfDay / 60
            let minute = minuteOfDay % 60
            return validDays.compactMap { weekday in
                var parts = DateComponents()
                parts.weekday = weekday
                parts.hour = hour
                parts.minute = minute
                parts.second = 0
                return calendar.nextDate(after: date, matching: parts,
                                         matchingPolicy: .nextTimePreservingSmallerComponents,
                                         repeatedTimePolicy: .first, direction: .forward)
            }.min()
        }
    }
}

struct ChargingPlan: Codable, Equatable, Identifiable {
    var id: UUID
    var schedule: ChargingSchedule
    var deadline: Date
    var targetPercent: Int
    var holdPercent: Int
    var restoreLimit: Int
    var sleepStrategy: ChargingSleepStrategy
    var createdAt: Date
    var completedAt: Date?
    var readyNotifiedDeadline: Date?
    var lateNotifiedDeadline: Date?
    var restorePending: Bool?

    init(id: UUID = UUID(), schedule: ChargingSchedule, deadline: Date, targetPercent: Int,
         holdPercent: Int, restoreLimit: Int, sleepStrategy: ChargingSleepStrategy, createdAt: Date,
         completedAt: Date? = nil, readyNotifiedDeadline: Date? = nil,
         lateNotifiedDeadline: Date? = nil, restorePending: Bool? = nil) {
        self.id = id
        self.schedule = schedule
        self.deadline = deadline
        self.targetPercent = min(max(targetPercent, 50), 100)
        self.holdPercent = min(max(holdPercent, 50), 100)
        self.restoreLimit = min(max(restoreLimit, 50), 100)
        self.sleepStrategy = sleepStrategy
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.readyNotifiedDeadline = readyNotifiedDeadline
        self.lateNotifiedDeadline = lateNotifiedDeadline
        self.restorePending = restorePending
    }
}

struct ChargingPlanInput: Equatable {
    var now: Date
    var percent: Int
    var connected: Bool
    var limitSupported: Bool
    var currentLimit: Int
    var estimatedMinutes: Int?
    var isCharging: Bool
    var systemPaused: Bool
}

enum ChargingPlanPhase: String, Codable, Equatable {
    case unsupported
    case unplugged
    case waiting
    case starting
    case charging
    case systemPaused
    case ready
    case late
}

struct ChargingPlanDecision: Equatable {
    var phase: ChargingPlanPhase
    var targetPercent: Int
    var deadline: Date
    var startAt: Date?
    var wakeAt: Date?
    var desiredLimit: Int?
    var requiredMinutes: Int
    var notifyReady: Bool
    var notifyLate: Bool
}

enum ChargingPlanEngine {
    static let safetyMinutes = 15
    static let maximumEstimateMinutes = 24 * 60

    static func evaluate(_ plan: ChargingPlan, input: ChargingPlanInput) -> ChargingPlanDecision {
        let needed = requiredMinutes(plan: plan, input: input)
        let start = plan.deadline.addingTimeInterval(-Double(needed + safetyMinutes) * 60)
        let wake = plan.sleepStrategy == .preciseWake && start > input.now
            ? start.addingTimeInterval(-60) : nil

        func result(_ phase: ChargingPlanPhase, limit: Int?, ready: Bool = false,
                    late: Bool = false) -> ChargingPlanDecision {
            ChargingPlanDecision(phase: phase, targetPercent: plan.targetPercent,
                                 deadline: plan.deadline, startAt: start,
                                 wakeAt: wake, desiredLimit: limit, requiredMinutes: needed,
                                 notifyReady: ready, notifyLate: late)
        }

        guard input.limitSupported else { return result(.unsupported, limit: nil) }
        guard input.connected else { return result(.unplugged, limit: nil) }
        if input.percent >= plan.targetPercent {
            return result(.ready, limit: plan.targetPercent, ready: true)
        }
        if input.now >= plan.deadline {
            return result(.late, limit: plan.targetPercent, late: true)
        }
        if input.now < start {
            return result(.waiting, limit: plan.holdPercent)
        }
        if input.now.addingTimeInterval(Double(needed) * 60) > plan.deadline {
            return result(.late, limit: plan.targetPercent, late: true)
        }
        if input.isCharging { return result(.charging, limit: plan.targetPercent) }
        if input.systemPaused { return result(.systemPaused, limit: plan.targetPercent) }
        return result(.starting, limit: plan.targetPercent)
    }

    private static func requiredMinutes(plan: ChargingPlan, input: ChargingPlanInput) -> Int {
        guard input.percent < plan.targetPercent else { return 0 }
        if let estimate = input.estimatedMinutes, estimate > 0 {
            return min(estimate, maximumEstimateMinutes)
        }
        let missing = Double(plan.targetPercent - max(0, input.percent))
        let fallback = Int(ceil(missing / ChargingRateEstimator.fallbackPercentPerHour * 60))
        return min(max(0, fallback), maximumEstimateMinutes)
    }
}

enum ChargingRateEstimator {
    static let fallbackPercentPerHour = 20.0
    private static let retention: TimeInterval = 7 * 24 * 3600

    static func percentPerHour(samples: [HistorySample], now: Date = Date()) -> Double? {
        let cutoff = now.addingTimeInterval(-retention)
        let ordered = samples.filter { $0.t >= cutoff && $0.t <= now }.sorted { $0.t < $1.t }
        guard ordered.count >= 2 else { return nil }
        var rates: [Double] = []
        var seconds = 0.0
        for (left, right) in zip(ordered, ordered.dropFirst()) {
            let dt = right.t.timeIntervalSince(left.t)
            guard dt > 0, dt <= 30 * 60, left.plugged, right.plugged,
                  left.charging || right.charging else { continue }
            let delta = right.pct - left.pct
            guard delta > 0 else { continue }
            rates.append(Double(delta) / dt * 3600)
            seconds += dt
        }
        guard seconds >= 5 * 60, !rates.isEmpty else { return nil }
        rates.sort()
        let middle = rates.count / 2
        let rate = rates.count.isMultiple(of: 2) ? (rates[middle - 1] + rates[middle]) / 2 : rates[middle]
        guard rate.isFinite, (1...100).contains(rate) else { return nil }
        return rate
    }
}
