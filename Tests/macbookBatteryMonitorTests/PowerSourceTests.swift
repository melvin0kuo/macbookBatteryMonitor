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
        XCTAssertEqual(estimates.batteryWatts, 1) // 輸入 18 − 系統 17
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
    /// M1 MacBook Air 實測：充電時 PPBR 只有 1.35 W，實際充入約 13.5 W
    func testChargingBatteryPowerBalancesInputAndSystem() {
        var snapshot = BatterySnapshot(percent: 88, isCharging: true, externalConnected: true,
            voltage_mV: 12593, amperage_mA: 1189)
        snapshot.applyLivePower(battery: 1.35, adapter: 20.44, system: 6.98)
        snapshot.reconcilePowerSource(inputMilliwatts: 20303)
        let estimates = Estimator.estimates(snapshot, avgDischarge_mA: nil, avgCharge_mA: 1069)
        XCTAssertEqual(estimates.state, .charging)
        XCTAssertTrue(abs(estimates.batteryWatts - 13.46) < 0.001)
        XCTAssertTrue(abs((estimates.adapterInputWatts ?? 0) - (estimates.systemWatts ?? 0) - estimates.batteryWatts) < 0.001)
        XCTAssertTrue(abs(snapshot.effectiveAmperage_mA - 1069) <= 1)
    }
    /// M1 MacBook Air 實測：用電池時 PPBR 是正值，Registry 電流也還停在充電的舊值
    func testOnBatteryUsesSystemPowerWhenPPBRIsUnsigned() {
        var snapshot = BatterySnapshot(percent: 88, externalConnected: false,
            voltage_mV: 12593, amperage_mA: 1189)
        snapshot.applyLivePower(battery: 4.4, adapter: 0, system: 3.2)
        snapshot.reconcilePowerSource(inputMilliwatts: 0)
        let estimates = Estimator.estimates(snapshot, avgDischarge_mA: 254, avgCharge_mA: nil)
        XCTAssertEqual(estimates.state, .discharging)
        XCTAssertEqual(estimates.batteryWatts, -3.2)
        XCTAssertEqual(estimates.systemWatts, 3.2)
        XCTAssertTrue(snapshot.effectiveAmperage_mA < -50)
    }
    /// 高於充電上限時 macOS 暫停變壓器供電、讓電池放電，線仍接著
    func testDrainingToChargeLimitStaysPlugged() {
        var snapshot = BatterySnapshot(percent: 100, externalConnected: true, voltage_mV: 12500, amperage_mA: -300)
        snapshot.chargeLimit = ChargeLimit(limit: 95, reason: "manualChargeLimit")
        snapshot.applyLivePower(battery: 3.6, adapter: 0.2, system: 3.5)
        snapshot.reconcilePowerSource(inputMilliwatts: 200)
        XCTAssertTrue(snapshot.externalConnected)
        let estimates = Estimator.estimates(snapshot, avgDischarge_mA: 264, avgCharge_mA: nil)
        XCTAssertEqual(estimates.state, .limitReached)
        XCTAssertTrue(abs(estimates.batteryWatts + 3.3) < 0.001)
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
