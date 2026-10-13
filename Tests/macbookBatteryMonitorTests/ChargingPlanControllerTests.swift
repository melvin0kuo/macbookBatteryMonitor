import Foundation

final class ChargingPlanControllerTests {
    func run() {
        testQuickPlanPersistsAndRequestsHoldOnce()
        testFailureRetriesAfterCooldown()
        testReadinessFirstReleasesBeforeSleep()
        testCancelAndExpiryRestoreOriginalLimit()
        testRecurringPlanAdvancesAfterDeadline()
        testCompletedOneOffUnplugRestoresLimit()
        testUnsupportedStartupKeepsExpiredPlanForLaterRestore()
        testPreciseWakeFallbackAndOriginalLimitSurvivePlanReplacement()
        testMissedRecurringPlanAdvancesAndNotificationsPersist()
        testCancelDuringWriteRetriesRestoreAfterOldWriteCompletes()
        testLateNotificationRearmsAfterEstimateRecovers()
    }

    func testLateNotificationRearmsAfterEstimateRecovers() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = ChargingPlanController(persistence: MemoryChargingPlanPersistence())
        controller.startQuick(hours: 1, target: 100, hold: 80, restore: 90, now: now)
        var value = input(now: now, percent: 70, currentLimit: 100)
        value.estimatedMinutes = 90
        _ = controller.evaluate(input: value, reason: .refresh)
        XCTAssertTrue(controller.consumeLateNotification())
        value.estimatedMinutes = 30
        value.isCharging = true
        _ = controller.evaluate(input: value, reason: .refresh)
        value.estimatedMinutes = 90
        _ = controller.evaluate(input: value, reason: .refresh)
        XCTAssertTrue(controller.consumeLateNotification())
    }

    func testCancelDuringWriteRetriesRestoreAfterOldWriteCompletes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = ChargingPlanController(persistence: MemoryChargingPlanPersistence())
        controller.startQuick(hours: 3, target: 100, hold: 80, restore: 90, now: now)
        XCTAssertEqual(controller.evaluate(input: input(now: now, percent: 60, currentLimit: 90),
                                           reason: .refresh), 80)
        XCTAssertNil(controller.cancel(currentLimit: 90, now: now))
        XCTAssertEqual(controller.plan?.restorePending, true)
        controller.completeLimitWrite(target: 80, success: true, now: now)
        XCTAssertEqual(controller.evaluate(input: input(now: now.addingTimeInterval(1), percent: 60,
                                                        currentLimit: 80), reason: .refresh), 90)
        controller.completeLimitWrite(target: 90, success: true, now: now.addingTimeInterval(1))
        XCTAssertNil(controller.plan)
    }

    func testPreciseWakeFallbackAndOriginalLimitSurvivePlanReplacement() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = ChargingPlanController(persistence: MemoryChargingPlanPersistence())
        controller.startQuick(hours: 8, target: 100, hold: 80, restore: 90,
                              sleepStrategy: .preciseWake, now: now)
        controller.startQuick(hours: 6, target: 95, hold: 80, restore: 80,
                              sleepStrategy: .preciseWake, now: now)
        XCTAssertEqual(controller.plan?.restoreLimit, 90)
        XCTAssertEqual(controller.evaluate(input: input(now: now, percent: 70, currentLimit: 80),
                                           reason: .willSleep, preciseWakeAvailable: false), 95)
    }

    func testMissedRecurringPlanAdvancesAndNotificationsPersist() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistence = MemoryChargingPlanPersistence()
        let controller = ChargingPlanController(persistence: persistence, calendar: calendar)
        let weekday = calendar.component(.weekday, from: now.addingTimeInterval(24 * 3600))
        let future = calendar.date(byAdding: .day, value: 1, to: now)!
        let minute = calendar.component(.hour, from: future) * 60 + calendar.component(.minute, from: future)
        controller.saveRecurring(weekdays: [weekday], minuteOfDay: minute, target: 100, hold: 80,
                                 restore: 90, now: now)
        let old = controller.plan!.deadline
        _ = controller.evaluate(input: input(now: old.addingTimeInterval(2 * 3600 + 1), percent: 50,
                                             currentLimit: 100), reason: .refresh)
        XCTAssertTrue(controller.plan!.deadline > old)

        var readyInput = input(now: controller.plan!.deadline.addingTimeInterval(-60), percent: 100,
                               currentLimit: 100)
        readyInput.isCharging = true
        _ = controller.evaluate(input: readyInput, reason: .refresh)
        XCTAssertTrue(controller.consumeReadyNotification())
        let restarted = ChargingPlanController(persistence: persistence, calendar: calendar)
        _ = restarted.evaluate(input: readyInput, reason: .refresh)
        XCTAssertTrue(!restarted.consumeReadyNotification())
    }

    func testUnsupportedStartupKeepsExpiredPlanForLaterRestore() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistence = MemoryChargingPlanPersistence()
        let controller = ChargingPlanController(persistence: persistence)
        controller.startQuick(hours: 1, target: 100, hold: 80, restore: 90, now: now)
        var unavailable = input(now: now.addingTimeInterval(4 * 3600), percent: 100, currentLimit: 100)
        unavailable.limitSupported = false
        XCTAssertNil(controller.evaluate(input: unavailable, reason: .refresh))
        XCTAssertTrue(controller.plan != nil)
        XCTAssertEqual(controller.decision?.phase, .unsupported)
        let restoreTime = now.addingTimeInterval(4 * 3600 + 1)
        XCTAssertEqual(controller.evaluate(input: input(now: restoreTime,
                                                        percent: 100, currentLimit: 100), reason: .refresh), 90)
        controller.completeLimitWrite(target: 90, success: true, now: restoreTime)
        XCTAssertNil(controller.plan)
    }

    func testCompletedOneOffUnplugRestoresLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let persistence = MemoryChargingPlanPersistence()
        let controller = ChargingPlanController(persistence: persistence)
        controller.startQuick(hours: 2, target: 100, hold: 80, restore: 90, now: now)
        _ = controller.evaluate(input: input(now: now.addingTimeInterval(3600), percent: 100,
                                             currentLimit: 100), reason: .refresh)
        controller.completeLimitWrite(target: 100, success: true, now: now.addingTimeInterval(3600))
        var unplugged = input(now: now.addingTimeInterval(3700), percent: 100, currentLimit: 100)
        unplugged.connected = false
        XCTAssertEqual(controller.evaluate(input: unplugged, reason: .refresh), 90)
        XCTAssertEqual(controller.plan?.restorePending, true)
        controller.completeLimitWrite(target: 90, success: true, now: unplugged.now)
        XCTAssertNil(controller.plan)
        XCTAssertNil(persistence.value)
    }

    func testQuickPlanPersistsAndRequestsHoldOnce() {
        let memory = MemoryChargingPlanPersistence()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = ChargingPlanController(persistence: memory)
        controller.startQuick(hours: 3, target: 100, hold: 80, restore: 90, now: now)
        XCTAssertEqual(controller.plan?.deadline, now.addingTimeInterval(3 * 3600))
        XCTAssertEqual(memory.value, controller.plan)

        let request = controller.evaluate(input: input(now: now, percent: 60, currentLimit: 90), reason: .refresh)
        XCTAssertEqual(request, 80)
        XCTAssertNil(controller.evaluate(input: input(now: now, percent: 60, currentLimit: 90), reason: .refresh))
        controller.completeLimitWrite(target: 80, success: true, now: now)
        XCTAssertNil(controller.evaluate(input: input(now: now, percent: 60, currentLimit: 80), reason: .refresh))
    }

    func testFailureRetriesAfterCooldown() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = ChargingPlanController(persistence: MemoryChargingPlanPersistence())
        controller.startQuick(hours: 3, target: 100, hold: 80, restore: 90, now: now)
        XCTAssertEqual(controller.evaluate(input: input(now: now, percent: 60, currentLimit: 90), reason: .refresh), 80)
        controller.completeLimitWrite(target: 80, success: false, now: now)
        XCTAssertNil(controller.evaluate(input: input(now: now.addingTimeInterval(59), percent: 60, currentLimit: 90), reason: .refresh))
        XCTAssertEqual(controller.evaluate(input: input(now: now.addingTimeInterval(60), percent: 60, currentLimit: 90), reason: .refresh), 80)
    }

    func testReadinessFirstReleasesBeforeSleep() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = ChargingPlanController(persistence: MemoryChargingPlanPersistence())
        controller.startQuick(hours: 8, target: 100, hold: 80, restore: 80,
                              sleepStrategy: .readinessFirst, now: now)
        XCTAssertEqual(controller.evaluate(input: input(now: now, percent: 70, currentLimit: 80), reason: .willSleep), 100)
    }

    func testCancelAndExpiryRestoreOriginalLimit() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = ChargingPlanController(persistence: MemoryChargingPlanPersistence())
        controller.startQuick(hours: 1, target: 100, hold: 80, restore: 90, now: now)
        XCTAssertEqual(controller.cancel(currentLimit: 80), 90)
        XCTAssertEqual(controller.plan?.restorePending, true)
        controller.completeLimitWrite(target: 90, success: true, now: now)
        XCTAssertNil(controller.plan)
        XCTAssertNil(controller.cancel(currentLimit: 80))

        controller.startQuick(hours: 1, target: 100, hold: 80, restore: 95, now: now)
        let expiry = now.addingTimeInterval(3 * 3600 + 1)
        XCTAssertEqual(controller.evaluate(input: input(now: expiry, percent: 100,
                                                        currentLimit: 100), reason: .refresh), 95)
        controller.completeLimitWrite(target: 95, success: true, now: expiry)
        XCTAssertNil(controller.plan)
    }

    func testRecurringPlanAdvancesAfterDeadline() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weekday = calendar.component(.weekday, from: now.addingTimeInterval(24 * 3600))
        let future = calendar.date(byAdding: .day, value: 1, to: now)!
        let minute = calendar.component(.hour, from: future) * 60 + calendar.component(.minute, from: future)
        let controller = ChargingPlanController(persistence: MemoryChargingPlanPersistence(), calendar: calendar)
        controller.saveRecurring(weekdays: [weekday], minuteOfDay: minute, target: 100, hold: 80,
                                 restore: 85, now: now)
        let oldDeadline = controller.plan!.deadline
        _ = controller.evaluate(input: input(now: oldDeadline.addingTimeInterval(1), percent: 100,
                                             currentLimit: 100), reason: .refresh)
        XCTAssertTrue((controller.plan?.deadline ?? .distantPast) > oldDeadline)
    }

    private func input(now: Date, percent: Int, currentLimit: Int) -> ChargingPlanInput {
        ChargingPlanInput(now: now, percent: percent, connected: true, limitSupported: true,
                          currentLimit: currentLimit, estimatedMinutes: 60, isCharging: false,
                          systemPaused: true)
    }
}

private final class MemoryChargingPlanPersistence: ChargingPlanPersistence {
    var value: ChargingPlan?
    func load() -> ChargingPlan? { value }
    func save(_ plan: ChargingPlan?) { value = plan }
}
