import Foundation
final class PowerSourceTests {
    func testFullBatteryWithStaleACFlagSwitchesToBattery() {
        var snapshot = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true,
            voltage_mV: 12682, amperage_mA: -1021, remaining_mAh: 5275, systemLoad_mW: 14764)
        snapshot.reconcilePowerSource(inputMilliwatts: 0)
        XCTAssertTrue(!snapshot.externalConnected)
        let estimates = Estimator.estimates(snapshot, avgDischarge_mA: 1021, avgCharge_mA: nil)
        XCTAssertEqual(estimates.state, .discharging)
        XCTAssertEqual(estimates.systemWatts, -estimates.batteryWatts)
        XCTAssertTrue(estimates.liveToEmpty != nil)
        XCTAssertNil(estimates.adapterInputWatts)
    }
    func testMixedSupplyIsNotClassifiedAsFull() {
        var snapshot = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true,
            voltage_mV: 12000, amperage_mA: -1000, systemPowerIn_mW: 5000)
        snapshot.reconcilePowerSource(inputMilliwatts: 5000)
        XCTAssertTrue(snapshot.externalConnected)
        XCTAssertEqual(Estimator.state(snapshot), .pluggedIdle)
    }
    func testIdleFullAndMissingTelemetryKeepAC() {
        var snapshot = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true)
        snapshot.reconcilePowerSource(inputMilliwatts: 0)
        XCTAssertTrue(snapshot.externalConnected)
        XCTAssertEqual(Estimator.state(snapshot), .full)
        snapshot.amperage_mA = -1000
        snapshot.reconcilePowerSource(inputMilliwatts: nil)
        XCTAssertTrue(snapshot.externalConnected)
    }
}
