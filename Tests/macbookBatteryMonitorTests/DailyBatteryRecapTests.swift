import Foundation

final class DailyBatteryRecapTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return value
    }

    func run() {
        testEmptyHistory()
        testMidnightClippingTransitionsAndCharging()
        testMissingGapCapsDurationButKeepsPercentChange()
        testOppositeOnePointJitterIsIgnored()
    }

    func testEmptyHistory() {
        let recap = DailyBatteryRecap.make(samples: [], day: date(2026, 10, 13, 12, 0), calendar: calendar)
        XCTAssertEqual(recap.usedPercent, 0)
        XCTAssertEqual(recap.chargedPercent, 0)
        XCTAssertEqual(recap.plugInCount, 0)
        XCTAssertEqual(recap.unpluggedMinutes, 0)
        XCTAssertEqual(recap.longestUnpluggedMinutes, 0)
        XCTAssertNil(recap.startPercent)
        XCTAssertNil(recap.endPercent)
    }

    func testMidnightClippingTransitionsAndCharging() {
        let day = date(2026, 10, 13, 12, 0)
        let samples = [
            sample(2026, 10, 12, 23, 50, 90, plugged: false),
            sample(2026, 10, 13, 0, 10, 88, plugged: false),
            sample(2026, 10, 13, 0, 40, 85, plugged: false),
            sample(2026, 10, 13, 1, 0, 85, plugged: true),
            sample(2026, 10, 13, 1, 30, 90, plugged: true, charging: true),
            sample(2026, 10, 13, 2, 0, 95, plugged: true, charging: true),
        ]
        let recap = DailyBatteryRecap.make(samples: samples, day: day, calendar: calendar)
        XCTAssertEqual(recap.startPercent, 90)
        XCTAssertEqual(recap.endPercent, 95)
        XCTAssertEqual(recap.usedPercent, 5)
        XCTAssertEqual(recap.chargedPercent, 10)
        XCTAssertEqual(recap.plugInCount, 1)
        XCTAssertEqual(recap.unpluggedMinutes, 60)
        XCTAssertEqual(recap.longestUnpluggedMinutes, 60)
    }

    func testMissingGapCapsDurationButKeepsPercentChange() {
        let day = date(2026, 10, 13, 12, 0)
        let samples = [
            sample(2026, 10, 13, 8, 0, 80, plugged: false),
            sample(2026, 10, 13, 12, 0, 60, plugged: false),
        ]
        let recap = DailyBatteryRecap.make(samples: samples, day: day, calendar: calendar)
        XCTAssertEqual(recap.usedPercent, 20)
        XCTAssertEqual(recap.unpluggedMinutes, 30)
        XCTAssertEqual(recap.longestUnpluggedMinutes, 30)
    }

    func testOppositeOnePointJitterIsIgnored() {
        let day = date(2026, 10, 13, 12, 0)
        let samples = [
            sample(2026, 10, 13, 8, 0, 80, plugged: false),
            sample(2026, 10, 13, 8, 10, 81, plugged: false),
            sample(2026, 10, 13, 8, 20, 79, plugged: false),
            sample(2026, 10, 13, 8, 30, 50, plugged: true, charging: true),
            sample(2026, 10, 13, 8, 40, 49, plugged: true, charging: true),
            sample(2026, 10, 13, 8, 50, 51, plugged: true, charging: true),
        ]
        let recap = DailyBatteryRecap.make(samples: samples, day: day, calendar: calendar)
        XCTAssertEqual(recap.usedPercent, 1)
        XCTAssertEqual(recap.chargedPercent, 1)
        XCTAssertEqual(recap.plugInCount, 1)
    }

    private func sample(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
                        _ percent: Int, plugged: Bool, charging: Bool = false) -> HistorySample {
        HistorySample(t: date(year, month, day, hour, minute), pct: percent, watts: nil,
                      plugged: plugged, charging: charging)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
