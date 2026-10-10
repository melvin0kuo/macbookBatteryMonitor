import Foundation

final class HardwarePowerReader {
    private let report = IOReportReader()
    private let smc = SMC()
    private var delta = EnergyDelta()
    private var previousTime: TimeInterval?

    func reset() { delta.reset(); previousTime = nil }

    func sample() -> ComponentPowerSample {
        let now = ProcessInfo.processInfo.systemUptime
        let energy = report?.sampleEnergy() ?? [:]
        let watts = delta.watts(energy: energy, uptime: now)
        let interval = previousTime.map { now - $0 }
        previousTime = now
        func valid(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0, value < 500 else { return nil }
            return value
        }
        let battery = BatteryReader.read(includeTemperature: false)
        let system = battery?.systemLoad_mW.map { Double($0) / 1000 }
        return ComponentPowerSample(uptime: now, interval: interval,
            backlightWatts: valid(smc?.read("PDBR")) ?? valid(smc?.read("PBwo")),
            cpuWatts: watts["cpu"], gpuWatts: watts["gpu"], aneWatts: watts["ane"],
            systemWatts: valid(system), sampling: interval == nil && !energy.isEmpty)
    }
}

actor HardwarePowerWorker {
    private var reader: HardwarePowerReader?
    private var generation = -1
    func sample(generation: Int) -> ComponentPowerSample? {
        guard generation >= self.generation else { return nil }
        if generation != self.generation {
            self.generation = generation
            reader = HardwarePowerReader()
        }
        return reader?.sample()
    }
    func stop(generation: Int) {
        guard generation >= self.generation else { return }
        self.generation = generation
        reader = nil
    }
}
