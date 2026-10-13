import Foundation

final class ChargingPlanTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    func run() {
        testOneOffAndRecurringDeadlines()
        testRecurringDeadlineKeepsWallClockAcrossDST()
        testRateEstimatorAndFallback()
        testWaitingReleaseChargingPausedReadyAndLate()
        testUnsupportedAndUnpluggedDoNotWriteLimit()
        testEstimateBoundsAndRestoreLimitSurvivesCoding()
    }

    func testOneOffAndRecurringDeadlines() {
        let now = date(2026, 10, 13, 9, 0)
        let deadline = date(2026, 10, 13, 12, 0)
        XCTAssertEqual(ChargingSchedule.oneOff(deadline).nextDeadline(after: now, calendar: calendar), deadline)
        XCTAssertNil(ChargingSchedule.oneOff(deadline).nextDeadline(after: deadline, calendar: calendar))

        let recurring = ChargingSchedule.recurring(weekdays: [2, 4], minuteOfDay: 8 * 60)
        XCTAssertEqual(recurring.nextDeadline(after: date(2026, 10, 13, 9, 0), calendar: calendar),
                       date(2026, 10, 14, 8, 0))
    }

    func testRecurringDeadlineKeepsWallClockAcrossDST() {
        let recurring = ChargingSchedule.recurring(weekdays: [1], minuteOfDay: 8 * 60 + 30)
        let next = recurring.nextDeadline(after: date(2026, 3, 7, 12, 0), calendar: calendar)
        XCTAssertEqual(next, date(2026, 3, 8, 8, 30))
        XCTAssertEqual(next.map { calendar.component(.hour, from: $0) }, 8)
    }

    func testRateEstimatorAndFallback() {
        let now = date(2026, 10, 13, 12, 0)
        let samples = [
            HistorySample(t: now.addingTimeInterval(-3600), pct: 20, watts: 20, plugged: true, charging: true),
            HistorySample(t: now.addingTimeInterval(-1800), pct: 30, watts: 20, plugged: true, charging: true),
            HistorySample(t: now, pct: 40, watts: 20, plugged: true, charging: true),
        ]
        XCTAssertTrue(abs((ChargingRateEstimator.percentPerHour(samples: samples, now: now) ?? -1) - 20) < 0.01)
        XCTAssertNil(ChargingRateEstimator.percentPerHour(samples: [], now: now))
        XCTAssertEqual(ChargingRateEstimator.fallbackPercentPerHour, 20)
        let outlier = samples + [
            HistorySample(t: now.addingTimeInterval(300), pct: 90, watts: 40, plugged: true, charging: true)
        ]
        XCTAssertTrue((ChargingRateEstimator.percentPerHour(samples: outlier, now: now.addingTimeInterval(300)) ?? 0) < 100)
    }

    func testWaitingReleaseChargingPausedReadyAndLate() {
        let now = date(2026, 10, 13, 9, 0)
        let plan = ChargingPlan(schedule: .oneOff(date(2026, 10, 13, 12, 0)),
                                deadline: date(2026, 10, 13, 12, 0), targetPercent: 100,
                                holdPercent: 80, restoreLimit: 85, sleepStrategy: .readinessFirst,
                                createdAt: now)
        let waiting = ChargingPlanEngine.evaluate(plan, input: input(now: now, percent: 60, minutes: 60))
        XCTAssertEqual(waiting.phase, .waiting)
        XCTAssertEqual(waiting.desiredLimit, 80)
        XCTAssertEqual(waiting.startAt, date(2026, 10, 13, 10, 45))

        let charging = ChargingPlanEngine.evaluate(plan, input: input(now: date(2026, 10, 13, 11, 0), percent: 70,
                                                                       minutes: 45, charging: true))
        XCTAssertEqual(charging.phase, .charging)
        XCTAssertEqual(charging.desiredLimit, 100)

        let paused = ChargingPlanEngine.evaluate(plan, input: input(now: date(2026, 10, 13, 11, 0), percent: 70,
                                                                     minutes: 45, charging: false, paused: true))
        XCTAssertEqual(paused.phase, .systemPaused)

        let ready = ChargingPlanEngine.evaluate(plan, input: input(now: date(2026, 10, 13, 11, 20), percent: 100,
                                                                    minutes: 0))
        XCTAssertEqual(ready.phase, .ready)
        XCTAssertTrue(ready.notifyReady)

        let late = ChargingPlanEngine.evaluate(plan, input: input(now: date(2026, 10, 13, 12, 1), percent: 75,
                                                                   minutes: 50))
        XCTAssertEqual(late.phase, .late)
        XCTAssertTrue(late.notifyLate)
        let predictedLate = ChargingPlanEngine.evaluate(plan, input: input(now: date(2026, 10, 13, 11, 30),
                                                                           percent: 75, minutes: 45,
                                                                           charging: true))
        XCTAssertEqual(predictedLate.phase, .late)
    }

    func testUnsupportedAndUnpluggedDoNotWriteLimit() {
        let now = date(2026, 10, 13, 9, 0)
        let plan = ChargingPlan(schedule: .oneOff(date(2026, 10, 13, 12, 0)),
                                deadline: date(2026, 10, 13, 12, 0), targetPercent: 100,
                                holdPercent: 80, restoreLimit: 95, sleepStrategy: .preciseWake,
                                createdAt: now)
        var unsupported = input(now: now, percent: 50, minutes: 60)
        unsupported.limitSupported = false
        XCTAssertEqual(ChargingPlanEngine.evaluate(plan, input: unsupported).phase, .unsupported)
        XCTAssertNil(ChargingPlanEngine.evaluate(plan, input: unsupported).desiredLimit)

        var unplugged = input(now: now, percent: 50, minutes: 60)
        unplugged.connected = false
        XCTAssertEqual(ChargingPlanEngine.evaluate(plan, input: unplugged).phase, .unplugged)
        XCTAssertNil(ChargingPlanEngine.evaluate(plan, input: unplugged).desiredLimit)
    }

    func testEstimateBoundsAndRestoreLimitSurvivesCoding() {
        let now = date(2026, 10, 13, 9, 0)
        let plan = ChargingPlan(schedule: .oneOff(date(2026, 10, 14, 12, 0)),
                                deadline: date(2026, 10, 14, 12, 0), targetPercent: 100,
                                holdPercent: 80, restoreLimit: 90, sleepStrategy: .preciseWake,
                                createdAt: now)
        let decision = ChargingPlanEngine.evaluate(plan, input: input(now: now, percent: 0, minutes: 100_000))
        XCTAssertEqual(decision.requiredMinutes, 24 * 60)
        XCTAssertEqual(decision.wakeAt, decision.startAt?.addingTimeInterval(-60))
        let roundTrip = try! JSONDecoder().decode(ChargingPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(roundTrip.restoreLimit, 90)
        XCTAssertEqual(roundTrip, plan)
    }

    private func input(now: Date, percent: Int, minutes: Int?, charging: Bool = false,
                       paused: Bool = false) -> ChargingPlanInput {
        ChargingPlanInput(now: now, percent: percent, connected: true, limitSupported: true,
                          currentLimit: 80, estimatedMinutes: minutes, isCharging: charging,
                          systemPaused: paused)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
