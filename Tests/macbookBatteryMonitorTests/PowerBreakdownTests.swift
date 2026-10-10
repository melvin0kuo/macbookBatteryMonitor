import Foundation
final class PowerBreakdownTests {
    func testCompleteBreakdown() {
        let sample = ComponentPowerSample(uptime: 10, interval: 1, backlightWatts: 3, cpuWatts: 2, gpuWatts: 1, aneWatts: 0)
        let result = PowerBreakdown.make(systemWatts: 12, components: sample, now: 10)
        XCTAssertEqual(result.chipWatts, 3)
        XCTAssertEqual(result.otherWatts, 6)
        XCTAssertEqual(result.status, .available)
    }
    func testMissingAndNegativeResidual() {
        var sample = ComponentPowerSample(uptime: 10, interval: 1, backlightWatts: 3, cpuWatts: 2, gpuWatts: 1)
        XCTAssertNil(PowerBreakdown.make(systemWatts: 12, components: sample, now: 10).otherWatts)
        sample.aneWatts = 0
        let result = PowerBreakdown.make(systemWatts: 4, components: sample, now: 10)
        XCTAssertNil(result.otherWatts)
        XCTAssertEqual(result.status, .inconsistent)
        XCTAssertNil(PowerBreakdown.make(systemWatts: .nan, components: sample, now: 10).otherWatts)
    }
    func testStaleAndSampling() {
        var sample = ComponentPowerSample(uptime: 10, interval: 1, backlightWatts: 3, cpuWatts: 2, gpuWatts: 1, aneWatts: 0)
        let result = PowerBreakdown.make(systemWatts: 12, components: sample, now: 14)
        XCTAssertNil(result.otherWatts)
        XCTAssertNil(result.chipWatts)
        XCTAssertEqual(result.status, .stale)
        sample.sampling = true
        XCTAssertEqual(PowerBreakdown.make(systemWatts: 12, components: sample, now: 10).status, .sampling)
    }
    func testNegativeComponentRejected() {
        let sample = ComponentPowerSample(uptime: 10, interval: 1, backlightWatts: -1, cpuWatts: 2, gpuWatts: 1, aneWatts: 0)
        XCTAssertNil(PowerBreakdown.make(systemWatts: 12, components: sample, now: 10).otherWatts)
    }
    func testSamplingGateRejectsOldCompletionsAndOverlap() {
        var gate = SamplingGate()
        XCTAssertNil(gate.begin())
        gate.setActive(true)
        let first = gate.begin()!
        XCTAssertNil(gate.begin())
        gate.setActive(false)
        XCTAssertTrue(!gate.finish(first))
        gate.setActive(true)
        let next = gate.begin()!
        XCTAssertTrue(!gate.finish(first))
        XCTAssertNil(gate.begin())
        XCTAssertTrue(gate.finish(next))
        XCTAssertTrue(gate.begin() != nil)
    }
}
