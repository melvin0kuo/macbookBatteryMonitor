import Foundation

final class HardwarePowerReader {
    private let report = IOReportReader()
    private let smc = SMC()
    private var delta = EnergyDelta()
    private var previousSystem: Double?
    private var previousBacklight: Double?
    private var previousTime: TimeInterval?

    func reset() { delta.reset(); previousTime = nil; previousSystem = nil; previousBacklight = nil }

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
        let system = valid(smc?.read("PSTR"))
        let backlight = valid(smc?.read("PDBR")) ?? valid(smc?.read("PBwo"))
        let windowValid = interval.map { $0 > 0 && $0 <= 3 } ?? false
        let estimated = windowValid && system != nil && previousSystem != nil
            && backlight != nil && previousBacklight != nil
        let systemAverage = estimated ? (system! + previousSystem!) / 2 : system
        let backlightAverage = estimated ? (backlight! + previousBacklight!) / 2 : backlight
        previousSystem = system
        previousBacklight = backlight
        let fallback = BatteryReader.read(includeTemperature: false)?.systemLoad_mW.map { Double($0) / 1000 }
        return ComponentPowerSample(uptime: now, interval: interval,
            backlightWatts: backlightAverage,
            cpuWatts: EnergyCounter.updatedCPUWatts(watts["cpu"]), gpuWatts: watts["gpu"], aneWatts: watts["ane"],
            systemWatts: systemAverage ?? valid(fallback), systemWindowEstimated: estimated,
            systemPowerSource: system != nil ? "SMC PSTR" : "Battery SystemLoad",
            sampling: interval == nil && !energy.isEmpty)
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
