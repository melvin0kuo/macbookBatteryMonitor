import Foundation
final class PowerSourceTests {
    func testUnplugIgnoresDelayedPositivePowerReadings() {
        var snapshot = BatterySnapshot(percent: 100, isCharging: true, externalConnected: false,
            voltage_mV: 12678, amperage_mA: -949)
        snapshot.applyLivePower(battery: 0.95, adapter: 18, system: 17)
        snapshot.reconcilePowerSource(inputMilliwatts: 18000)
        XCTAssertTrue(!snapshot.externalConnected)
        XCTAssertTrue(!snapshot.isCharging)
        let estimates = Estimator.estimates(snapshot, avgDischarge_mA: 949, avgCharge_mA: nil)
        XCTAssertEqual(estimates.state, .discharging)
        XCTAssertTrue(estimates.batteryWatts <= 0)
        XCTAssertNil(estimates.adapterInputWatts)
    }
    func testReplugPrefersLiveSMCOverOldRegistryValues() {
        var snapshot = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true,
            voltage_mV: 12678, amperage_mA: -949, systemLoad_mW: 12033)
        snapshot.applyLivePower(battery: 0.95, adapter: 18, system: 17)
        snapshot.reconcilePowerSource(inputMilliwatts: 0)
        XCTAssertTrue(snapshot.externalConnected)
        let estimates = Estimator.estimates(snapshot, avgDischarge_mA: nil, avgCharge_mA: nil)
        XCTAssertEqual(estimates.state, .full)
        XCTAssertEqual(estimates.batteryWatts, 0.95)
        XCTAssertEqual(estimates.adapterInputWatts, 18)
        XCTAssertEqual(estimates.systemWatts, 17)
        XCTAssertTrue(snapshot.effectiveAmperage_mA > 0)
    }
    func testUnplugThenReplugUsesLiveSupply() {
        var snapshot = BatterySnapshot(percent: 100, externalConnected: true, fullyCharged: true,
            voltage_mV: 12678, amperage_mA: -949)
        snapshot.applyLivePower(battery: -12, adapter: 0, system: 12)
        snapshot.reconcilePowerSource(inputMilliwatts: 18000)
        XCTAssertTrue(!snapshot.externalConnected)
        XCTAssertEqual(Estimator.state(snapshot), .discharging)
        snapshot.externalConnected = true // 下一次快照回報重新連接
        snapshot.applyLivePower(battery: 0.95, adapter: 18, system: 17)
        snapshot.reconcilePowerSource(inputMilliwatts: 0)
        XCTAssertTrue(snapshot.externalConnected)
        XCTAssertEqual(Estimator.state(snapshot), .full)
    }
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
