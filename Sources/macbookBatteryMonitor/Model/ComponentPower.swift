import Foundation

enum EnergyCounter {
    /// 面板顯示期間 CPU 計數沒有前進時，不將凍結的計數顯示成零耗電。
    static func updatedCPUWatts(_ watts: Double?) -> Double? {
        guard let watts, watts.isFinite, watts > 0, watts < 500 else { return nil }
        return watts
    }

    static func joules(_ value: Double, unit: String) -> Double? {
        guard value.isFinite, value >= 0 else { return nil }
        let divisor: Double
        switch unit {
        case "J": divisor = 1
        case "mJ": divisor = 1_000
        case "uJ", "µJ", "μJ": divisor = 1_000_000
        case "nJ": divisor = 1_000_000_000
        default: return nil
        }
        return value / divisor
    }

    static func collect(_ pairs: [(String, Double)]) -> [String: Double] {
        var values: [String: Double] = [:]
        var seen = Set<String>()
        var duplicates = Set<String>()
        for (key, value) in pairs {
            if !seen.insert(key).inserted { duplicates.insert(key) }
            if value.isFinite, value >= 0 { values[key] = value }
        }
        for key in duplicates { values.removeValue(forKey: key) }
        return values
    }
}

struct EnergyDelta {
    private var previous: (energy: [String: Double], uptime: TimeInterval)?
    mutating func reset() { previous = nil }
    mutating func watts(energy: [String: Double], uptime: TimeInterval) -> [String: Double] {
        defer { previous = (energy, uptime) }
        guard let previous else { return [:] }
        let elapsed = uptime - previous.uptime
        guard elapsed > 0, elapsed <= 3 else { return [:] }
        var output: [String: Double] = [:]
        for (key, current) in energy {
            guard let prior = previous.energy[key], current >= prior,
                  current.isFinite, prior.isFinite else { continue }
            let watts = (current - prior) / elapsed
            if watts.isFinite, watts >= 0, watts < 500 { output[key] = watts }
        }
        return output
    }
}

struct ComponentPowerSample: Equatable, Codable {
    var uptime: TimeInterval
    var interval: TimeInterval?
    var backlightWatts: Double?
    var cpuWatts: Double?
    var gpuWatts: Double?
    var aneWatts: Double?
    var systemWatts: Double?
    // SystemLoad 沒有公開時間戳；只有經驗證同步的資料才能計算殘差。
    var systemWindowAligned = false
    var sampling = false
    var chipComplete: Bool { cpuWatts != nil && gpuWatts != nil && aneWatts != nil }
    var chipWatts: Double? {
        let values = [cpuWatts, gpuWatts, aneWatts].compactMap { $0 }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}
