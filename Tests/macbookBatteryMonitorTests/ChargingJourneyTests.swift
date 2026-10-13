import Foundation

final class ChargingJourneyTests {
    func run() {
        testInactiveAndWaitingPresentation()
        testChargingReadyLateAndUnsupportedMoods()
    }

    func testInactiveAndWaitingPresentation() {
        let state = ChargingJourneyPresentation.make(snapshot: snapshot(percent: 72), estimates: estimates(.pluggedIdle), decision: nil)
        XCTAssertEqual(state.title, "智慧充電")
        XCTAssertEqual(state.mood, .resting)
        XCTAssertEqual(state.progress, 0.72)
        let waiting = ChargingJourneyPresentation.make(snapshot: snapshot(percent: 80), estimates: estimates(.limitReached),
                                                        decision: decision(.waiting, target: 100))
        XCTAssertEqual(waiting.title, "保養中 · 等待充電")
        XCTAssertEqual(waiting.mood, .sleeping)
        XCTAssertTrue(waiting.detail.contains("開始"))
    }

    func testChargingReadyLateAndUnsupportedMoods() {
        let charging = ChargingJourneyPresentation.make(snapshot: snapshot(percent: 84), estimates: estimates(.charging),
                                                         decision: decision(.charging, target: 100))
        XCTAssertEqual(charging.mood, .charging)
        XCTAssertTrue(charging.title.contains("100%"))
        XCTAssertEqual(ChargingJourneyPresentation.make(snapshot: snapshot(percent: 100), estimates: estimates(.full),
                                                         decision: decision(.ready, target: 100)).mood, .happy)
        XCTAssertEqual(ChargingJourneyPresentation.make(snapshot: snapshot(percent: 70), estimates: estimates(.pluggedIdle),
                                                         decision: decision(.late, target: 100)).mood, .worried)
        XCTAssertEqual(ChargingJourneyPresentation.make(snapshot: snapshot(percent: 70), estimates: estimates(.pluggedIdle),
                                                         decision: decision(.unsupported, target: 100)).tint, .neutral)
    }

    private func snapshot(percent: Int) -> BatterySnapshot {
        var value = BatterySnapshot()
        value.percent = percent
        value.externalConnected = true
        return value
    }

    private func estimates(_ state: PowerState) -> Estimates {
        Estimates(state: state, batteryWatts: state == .charging ? 12 : 0)
    }

    private func decision(_ phase: ChargingPlanPhase, target: Int) -> ChargingPlanDecision {
        let deadline = Date(timeIntervalSince1970: 1_800_010_000)
        return ChargingPlanDecision(phase: phase, targetPercent: target, deadline: deadline,
                                    startAt: deadline.addingTimeInterval(-3600), wakeAt: nil,
                                    desiredLimit: target, requiredMinutes: 45,
                                    notifyReady: phase == .ready, notifyLate: phase == .late)
    }
}
