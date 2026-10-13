import Foundation
final class CPULeaseTests {
    func run() {
        var leases = CPUSamplingLeases()
        let a = UUID(), b = UUID()
        XCTAssertTrue(!leases.isActive(at: 10))
        leases.set(a, active: true, at: 10)
        XCTAssertTrue(leases.isActive(at: 14.9))
        XCTAssertTrue(!leases.isActive(at: 15))
        leases.set(b, active: true, at: 14)
        leases.set(a, active: false, at: 14)
        XCTAssertTrue(leases.isActive(at: 16))
        leases.remove(b)
        XCTAssertTrue(!leases.isActive(at: 16))
        leases.set(a, active: true, at: 20)
        XCTAssertTrue(!leases.isActive(at: 19))
        let reading = CPUPowerReading(watts: 17.5, uptime: 10)
        XCTAssertEqual(reading.freshWatts(at: 12.9), 17.5)
        XCTAssertNil(reading.freshWatts(at: 14))
        XCTAssertNil(reading.freshWatts(at: 9))
        XCTAssertNil(CPUPowerReading(watts: .nan, uptime: 10).freshWatts(at: 11))
        XCTAssertNil(CPUPowerReading(watts: -1, uptime: 10).freshWatts(at: 11))
    }

    /// 服務只接受 1、2、5、10 秒；更新頻率較慢時租約與資料有效期限跟著拉長
    func testIntervalAndPowerSavingFreshness() {
        XCTAssertEqual(CPUHelperConstants.samplingInterval(1), 1)
        XCTAssertEqual(CPUHelperConstants.samplingInterval(2), 2)
        XCTAssertEqual(CPUHelperConstants.samplingInterval(3), 2)
        XCTAssertEqual(CPUHelperConstants.samplingInterval(7), 5)
        XCTAssertEqual(CPUHelperConstants.samplingInterval(60), 10)
        XCTAssertEqual(CPUHelperConstants.samplingInterval(0), 1)
        XCTAssertEqual(CPUHelperConstants.samplingInterval(-5), 1)
        XCTAssertEqual(CPUHelperConstants.leaseDuration(interval: 1), 5)
        XCTAssertEqual(CPUHelperConstants.leaseDuration(interval: 10), 21)
        var leases = CPUSamplingLeases()
        let client = UUID()
        leases.set(client, active: true, at: 100, duration: CPUHelperConstants.leaseDuration(interval: 10))
        XCTAssertTrue(leases.isActive(at: 115))
        XCTAssertTrue(!leases.isActive(at: 121))
        let reading = CPUPowerReading(watts: 4.2, uptime: 10)
        XCTAssertNil(reading.freshWatts(at: 13.5))
        XCTAssertEqual(reading.freshWatts(at: 13.5, maxAge: 4), 4.2)
        XCTAssertNil(reading.freshWatts(at: 14.5, maxAge: 4))
    }

    func testWakeValidationAndHelperRetention() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(WakeRequestValidator.validate(epoch: now.addingTimeInterval(60).timeIntervalSince1970,
                                                     now: now, identifier: CPUHelperConstants.wakeIdentifier, uid: 501))
        XCTAssertTrue(WakeRequestValidator.validate(epoch: now.addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970,
                                                     now: now, identifier: CPUHelperConstants.wakeIdentifier, uid: 501))
        XCTAssertTrue(!WakeRequestValidator.validate(epoch: now.addingTimeInterval(59).timeIntervalSince1970,
                                                      now: now, identifier: CPUHelperConstants.wakeIdentifier, uid: 501))
        XCTAssertTrue(!WakeRequestValidator.validate(epoch: now.addingTimeInterval(7 * 24 * 3600 + 1).timeIntervalSince1970,
                                                      now: now, identifier: CPUHelperConstants.wakeIdentifier, uid: 501))
        XCTAssertTrue(!WakeRequestValidator.validate(epoch: .nan, now: now,
                                                      identifier: CPUHelperConstants.wakeIdentifier, uid: 501))
        XCTAssertTrue(!WakeRequestValidator.validate(epoch: now.addingTimeInterval(600).timeIntervalSince1970,
                                                      now: now, identifier: "other", uid: 501))
        XCTAssertTrue(!WakeRequestValidator.validate(epoch: now.addingTimeInterval(600).timeIntervalSince1970,
                                                      now: now, identifier: CPUHelperConstants.wakeIdentifier, uid: 0))
        XCTAssertTrue(HelperRetentionPolicy.shouldKeep(cpuSampling: true, preciseCharging: false))
        XCTAssertTrue(HelperRetentionPolicy.shouldKeep(cpuSampling: false, preciseCharging: true))
        XCTAssertTrue(!HelperRetentionPolicy.shouldKeep(cpuSampling: false, preciseCharging: false))
        let wake = now.addingTimeInterval(3600)
        XCTAssertTrue(WakeSchedulePolicy.shouldReplace(existing: nil, candidate: wake))
        XCTAssertTrue(!WakeSchedulePolicy.shouldReplace(existing: wake, candidate: wake.addingTimeInterval(299)))
        XCTAssertTrue(WakeSchedulePolicy.shouldReplace(existing: wake, candidate: wake.addingTimeInterval(300)))
    }
}
