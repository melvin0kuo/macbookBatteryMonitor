import Foundation
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(b), got \(a)") }
func XCTAssertNil<T>(_ a: T?) { precondition(a == nil, "Expected nil, got \(String(describing: a))") }
func XCTAssertTrue(_ a: Bool) { precondition(a) }

final class ComponentPowerTests {
    func testUnchangedCPUCounterIsZero() {
        XCTAssertEqual(EnergyCounter.updatedCPUWatts(0), 0)
        XCTAssertNil(EnergyCounter.updatedCPUWatts(nil))
        XCTAssertEqual(EnergyCounter.updatedCPUWatts(1.5), 1.5)
    }
    func testEnergyUnits() {
        XCTAssertEqual(EnergyCounter.joules(1000, unit: "mJ"), 1)
        XCTAssertEqual(EnergyCounter.joules(1_000_000, unit: "uJ"), 1)
        XCTAssertEqual(EnergyCounter.joules(1_000_000_000, unit: "nJ"), 1)
        XCTAssertNil(EnergyCounter.joules(10, unit: "unknown"))
        XCTAssertNil(EnergyCounter.joules(.nan, unit: "J"))
        XCTAssertNil(EnergyCounter.joules(-1, unit: "J"))
    }
    func testFirstSampleAndDelta() {
        var meter = EnergyDelta()
        XCTAssertNil(meter.watts(energy: ["cpu": 10], uptime: 1)["cpu"])
        XCTAssertEqual(meter.watts(energy: ["cpu": 12], uptime: 2)["cpu"], 2)
    }
    func testClockRollbackCounterRollbackAndReset() {
        var meter = EnergyDelta()
        _ = meter.watts(energy: ["cpu": 10], uptime: 1)
        XCTAssertTrue(meter.watts(energy: ["cpu": 12], uptime: 1).isEmpty)
        XCTAssertTrue(meter.watts(energy: ["cpu": 2], uptime: 2).isEmpty)
        meter.reset()
        XCTAssertTrue(meter.watts(energy: ["cpu": 4], uptime: 3).isEmpty)
    }
    func testMissingChannelIsNotZero() {
        var meter = EnergyDelta()
        _ = meter.watts(energy: ["cpu": 1], uptime: 1)
        let sample = meter.watts(energy: ["cpu": 2, "gpu": 10], uptime: 2)
        XCTAssertEqual(sample["cpu"], 1)
        XCTAssertNil(sample["gpu"])
        XCTAssertNil(sample["ane"])
    }
    func testDuplicateChannelRejected() {
        let values = EnergyCounter.collect([("cpu", 1.0), ("cpu", 2.0), ("gpu", 3.0)])
        XCTAssertNil(values["cpu"])
        XCTAssertEqual(values["gpu"], 3)
    }
}
