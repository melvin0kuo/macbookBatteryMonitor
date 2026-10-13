import Foundation
import Observation

protocol ChargingPlanPersistence: AnyObject {
    func load() -> ChargingPlan?
    func save(_ plan: ChargingPlan?)
}

final class UserDefaultsChargingPlanPersistence: ChargingPlanPersistence {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "chargingPlan") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> ChargingPlan? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ChargingPlan.self, from: data)
    }

    func save(_ plan: ChargingPlan?) {
        guard let plan, let data = try? JSONEncoder().encode(plan) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}

enum ChargingEvaluationReason {
    case refresh
    case willSleep
    case didWake
}

@Observable
final class ChargingPlanController {
    private(set) var plan: ChargingPlan?
    private(set) var decision: ChargingPlanDecision?
    private(set) var writeError: String?
    private(set) var readyNotificationPending = false
    private(set) var lateNotificationPending = false

    @ObservationIgnored private let persistence: ChargingPlanPersistence
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var writeInFlight: Int?
    @ObservationIgnored private var retryAfter: Date?
    @ObservationIgnored private var notifiedReadyFor: UUID?
    @ObservationIgnored private var notifiedLateFor: UUID?

    init(persistence: ChargingPlanPersistence = UserDefaultsChargingPlanPersistence(),
         calendar: Calendar = .current) {
        self.persistence = persistence
        self.calendar = calendar
        plan = persistence.load()
    }

    func startQuick(hours: Double, target: Int, hold: Int, restore: Int,
                    sleepStrategy: ChargingSleepStrategy = .readinessFirst, now: Date = Date()) {
        let deadline = now.addingTimeInterval(max(0.25, hours) * 3600)
        let originalLimit = plan?.restoreLimit ?? restore
        setPlan(ChargingPlan(schedule: .oneOff(deadline), deadline: deadline, targetPercent: target,
                             holdPercent: min(hold, target), restoreLimit: originalLimit,
                             sleepStrategy: sleepStrategy, createdAt: now))
    }

    func saveRecurring(weekdays: Set<Int>, minuteOfDay: Int, target: Int, hold: Int,
                       restore: Int, sleepStrategy: ChargingSleepStrategy = .readinessFirst,
                       now: Date = Date()) {
        let schedule = ChargingSchedule.recurring(weekdays: weekdays, minuteOfDay: minuteOfDay)
        guard let deadline = schedule.nextDeadline(after: now, calendar: calendar) else { return }
        let originalLimit = plan?.restoreLimit ?? restore
        setPlan(ChargingPlan(schedule: schedule, deadline: deadline, targetPercent: target,
                             holdPercent: min(hold, target), restoreLimit: originalLimit,
                             sleepStrategy: sleepStrategy, createdAt: now))
    }

    func evaluate(input: ChargingPlanInput, reason: ChargingEvaluationReason,
                  preciseWakeAvailable: Bool = true) -> Int? {
        guard var active = plan else {
            decision = nil
            return nil
        }
        guard input.limitSupported else {
            decision = ChargingPlanEngine.evaluate(active, input: input)
            return nil
        }
        if active.restorePending == true {
            if active.restoreLimit == input.currentLimit, writeInFlight == nil {
                clearPlan()
                return nil
            }
            return request(active.restoreLimit, currentLimit: input.currentLimit, now: input.now)
        }

        if case .oneOff = active.schedule,
           input.now > active.deadline.addingTimeInterval(2 * 3600) {
            return beginRestore(active, currentLimit: input.currentLimit, now: input.now)
        }

        if case .oneOff = active.schedule, !input.connected,
           active.completedAt != nil || input.percent >= active.targetPercent {
            return beginRestore(active, currentLimit: input.currentLimit, now: input.now)
        }

        if case .recurring = active.schedule {
            let shouldAdvance = (input.now >= active.deadline && input.percent >= active.targetPercent)
                || input.now > active.deadline.addingTimeInterval(2 * 3600)
            let shouldRebase = active.deadline > input.now
            if (shouldAdvance || shouldRebase),
               let next = active.schedule.nextDeadline(after: input.now, calendar: calendar),
               abs(next.timeIntervalSince(active.deadline)) >= 60 {
                active.deadline = next
                active.completedAt = nil
                active.readyNotifiedDeadline = nil
                active.lateNotifiedDeadline = nil
                plan = active
                persistence.save(active)
                notifiedReadyFor = nil
                notifiedLateFor = nil
            }
        }

        let result = ChargingPlanEngine.evaluate(active, input: input)
        if decision?.phase == .late,
           [.waiting, .starting, .charging, .ready].contains(result.phase) {
            active.lateNotifiedDeadline = nil
            notifiedLateFor = nil
            plan = active
            persistence.save(active)
        }
        if result.phase == .ready, active.completedAt == nil {
            active.completedAt = input.now
            plan = active
            persistence.save(active)
        }
        decision = result
        readyNotificationPending = result.notifyReady && active.readyNotifiedDeadline != active.deadline
            && notifiedReadyFor != active.id
        lateNotificationPending = result.notifyLate && active.lateNotifiedDeadline != active.deadline
            && notifiedLateFor != active.id

        var desired = result.desiredLimit
        if reason == .willSleep,
           (active.sleepStrategy == .readinessFirst || !preciseWakeAvailable),
           result.phase == .waiting {
            desired = active.targetPercent
        }
        guard let desired else { return nil }
        return request(desired, currentLimit: input.currentLimit, now: input.now)
    }

    func completeLimitWrite(target: Int, success: Bool, now: Date = Date()) {
        guard writeInFlight == target else { return }
        writeInFlight = nil
        if success {
            retryAfter = nil
            writeError = nil
            if let active = plan, active.restorePending == true, target == active.restoreLimit {
                clearPlan()
            }
        } else {
            retryAfter = now.addingTimeInterval(60)
            writeError = "macOS 沒有套用排程所需的充電上限"
        }
    }

    func consumeReadyNotification() -> Bool {
        guard readyNotificationPending, var active = plan else { return false }
        readyNotificationPending = false
        notifiedReadyFor = active.id
        active.readyNotifiedDeadline = active.deadline
        plan = active
        persistence.save(active)
        return true
    }

    func consumeLateNotification() -> Bool {
        guard lateNotificationPending, var active = plan else { return false }
        lateNotificationPending = false
        notifiedLateFor = active.id
        active.lateNotifiedDeadline = active.deadline
        plan = active
        persistence.save(active)
        return true
    }

    func cancel(currentLimit: Int, now: Date = Date()) -> Int? {
        guard let active = plan else { return nil }
        return beginRestore(active, currentLimit: currentLimit, now: now)
    }

    /// 截圖用示範排程，只存在記憶體，不覆寫使用者的排程。
    func loadPreview(_ value: ChargingPlan) {
        plan = value
        decision = nil
        writeInFlight = nil
        retryAfter = nil
    }

    private func request(_ target: Int, currentLimit: Int, now: Date) -> Int? {
        guard target != currentLimit, writeInFlight == nil else { return nil }
        if let retryAfter, now < retryAfter { return nil }
        writeInFlight = target
        return target
    }

    private func beginRestore(_ value: ChargingPlan, currentLimit: Int, now: Date) -> Int? {
        var active = value
        active.restorePending = true
        plan = active
        decision = nil
        persistence.save(active)
        if active.restoreLimit == currentLimit, writeInFlight == nil {
            clearPlan()
            return nil
        }
        return request(active.restoreLimit, currentLimit: currentLimit, now: now)
    }

    private func setPlan(_ value: ChargingPlan) {
        plan = value
        decision = nil
        writeInFlight = nil
        retryAfter = nil
        notifiedReadyFor = nil
        notifiedLateFor = nil
        readyNotificationPending = false
        lateNotificationPending = false
        persistence.save(value)
    }

    private func clearPlan() {
        plan = nil
        decision = nil
        writeInFlight = nil
        retryAfter = nil
        readyNotificationPending = false
        lateNotificationPending = false
        persistence.save(nil)
    }
}
