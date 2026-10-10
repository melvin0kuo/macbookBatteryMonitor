import Foundation

struct PowerBreakdown: Equatable {
    enum Status: String { case available, sampling, incomplete, inconsistent, stale }
    var systemWatts: Double?
    var backlightWatts: Double?
    var cpuWatts: Double?
    var gpuWatts: Double?
    var aneWatts: Double?
    var chipWatts: Double?
    var otherWatts: Double?
    var status: Status

    static func make(systemWatts: Double?, components: ComponentPowerSample, now: TimeInterval) -> Self {
        func valid(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0, value < 500 else { return nil }
            return value
        }
        var result = Self(systemWatts: valid(systemWatts), status: .incomplete)
        guard now >= components.uptime, now - components.uptime <= 3 else {
            result.status = .stale
            return result
        }
        result.backlightWatts = valid(components.backlightWatts)
        result.cpuWatts = valid(components.cpuWatts)
        result.gpuWatts = valid(components.gpuWatts)
        result.aneWatts = valid(components.aneWatts)
        let chips = [result.cpuWatts, result.gpuWatts, result.aneWatts].compactMap { $0 }
        result.chipWatts = chips.isEmpty ? nil : chips.reduce(0, +)
        guard !components.sampling else { result.status = .sampling; return result }
        guard let system = result.systemWatts, let backlight = result.backlightWatts,
              let chip = result.chipWatts, chips.count == 3 else { return result }
        let residual = system - backlight - chip
        guard residual >= 0 else { result.status = .inconsistent; return result }
        result.otherWatts = residual
        result.status = .available
        return result
    }

    var message: String {
        switch status {
        case .available: return "晶片＝CPU＋GPU＋ANE・其他為差值估算"
        case .sampling: return "取樣中・正在建立晶片能量基準"
        case .incomplete: return "資料不完整・未取得的項目顯示 —"
        case .inconsistent: return "取樣不同步・暫不計算其他功耗"
        case .stale: return "等待新的功耗樣本"
        }
    }
}

struct SamplingGate {
    private(set) var active = false
    private(set) var generation = 0
    private var busy = false
    mutating func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        generation += 1
        busy = false
    }
    mutating func begin() -> Int? {
        guard active, !busy else { return nil }
        busy = true
        return generation
    }
    mutating func finish(_ ticket: Int) -> Bool {
        guard active, ticket == generation else { return false }
        busy = false
        return true
    }
}
