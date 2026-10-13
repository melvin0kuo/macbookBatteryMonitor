import Foundation

final class ChargingPlanNotificationTests {
    func run() {
        testOnlyReadyAndLateTransitionsNotify()
        testRecapPresentationHandlesEmptyAndBusyDays()
    }

    func testOnlyReadyAndLateTransitionsNotify() {
        XCTAssertNil(ChargingPlanNotificationGate.evaluate(previous: nil, current: .charging))
        XCTAssertEqual(ChargingPlanNotificationGate.evaluate(previous: .charging, current: .ready), .ready)
        XCTAssertNil(ChargingPlanNotificationGate.evaluate(previous: .ready, current: .ready))
        XCTAssertEqual(ChargingPlanNotificationGate.evaluate(previous: .charging, current: .late), .late)
        XCTAssertNil(ChargingPlanNotificationGate.evaluate(previous: .late, current: .late))
        XCTAssertNil(ChargingPlanNotificationGate.evaluate(previous: .ready, current: nil))
    }

    func testRecapPresentationHandlesEmptyAndBusyDays() {
        let empty = DailyRecapPresentation.make(DailyBatteryRecap(usedPercent: 0, chargedPercent: 0,
            plugInCount: 0, unpluggedMinutes: 0, longestUnpluggedMinutes: 0,
            startPercent: nil, endPercent: nil))
        XCTAssertEqual(empty.headline, "今天還沒有足夠資料")
        XCTAssertEqual(empty.netChange, "—")
        let busy = DailyRecapPresentation.make(DailyBatteryRecap(usedPercent: 55, chargedPercent: 70,
            plugInCount: 2, unpluggedMinutes: 310, longestUnpluggedMinutes: 180,
            startPercent: 40, endPercent: 55))
        XCTAssertTrue(busy.headline.contains("55%"))
        XCTAssertEqual(busy.netChange, "+15%")
    }
}
