import Foundation

enum PowerState: String, Codable {
    case discharging
    case charging
    /// 接著電源但電池沒在充（最佳化充電暫停、溫度保護等）
    case pluggedIdle
    case full
    /// 接著電源、已達系統設定的充電上限而暫停充電
    case limitReached
}

/// 由快照和平滑後的電流算出來的衍生值。時間單位為分鐘。
struct Estimates: Codable, Equatable {
    var state: PowerState
    /// macOS 自己的預估（和系統選單列顯示的一致）
    var systemToEmpty: Int?
    var systemTo10: Int?
    /// 依近幾分鐘平均耗電推算
    var liveToEmpty: Int?
    var liveTo10: Int?
    var toFull: Int?
    /// 充到系統充電上限的時間（有設上限且充電中才有）
    var toLimit: Int?
    var avgDischarge_mA: Double?
    var avgCharge_mA: Double?
    /// 正值為充入電池，負值為電池放出
    var batteryWatts: Double
    var systemWatts: Double?
    var adapterInputWatts: Double?
    var healthComputed: Double?

    var headlineToEmpty: Int? { systemToEmpty ?? liveToEmpty }
    var headlineToFull: Int? { toLimit ?? toFull }
}

enum Estimator {
    static let reservePercent = 10

    static func state(_ s: BatterySnapshot) -> PowerState {
        guard s.externalConnected else { return .discharging }
        if s.isCharging { return .charging }
        if let limit = s.chargeLimit?.limit, s.percent >= limit - 1 { return .limitReached }
        if s.fullyCharged || s.percent >= 100 { return .full }
        return .pluggedIdle
    }

    static func estimates(_ s: BatterySnapshot, avgDischarge_mA: Double?, avgCharge_mA: Double?) -> Estimates {
        let state = state(s)
        let batteryWatts = Double(s.voltage_mV) * Double(s.amperage_mA) / 1_000_000
        var e = Estimates(state: state, avgDischarge_mA: avgDischarge_mA, avgCharge_mA: avgCharge_mA, batteryWatts: batteryWatts)

        if let load = s.systemLoad_mW {
            e.systemWatts = Double(load) / 1000
        } else if batteryWatts < 0 {
            e.systemWatts = -batteryWatts
        }
        if s.externalConnected, let input = s.systemPowerIn_mW {
            e.adapterInputWatts = Double(input) / 1000
        }
        if let design = s.design_mAh, design > 0, let capacity = s.nominal_mAh ?? s.fullCharge_mAh {
            e.healthComputed = Double(capacity) / Double(design) * 100
        }

        let pct = s.percent
        if state == .discharging {
            e.systemToEmpty = s.psTimeToEmpty ?? s.avgTimeToEmpty
            if let total = e.systemToEmpty, pct > 0 {
                e.systemTo10 = max(0, total * (pct - reservePercent) / pct)
            }
            if let remaining = s.remaining_mAh, let current = avgDischarge_mA, current > 10, pct > 0 {
                let toEmpty = Double(remaining) / current * 60
                e.liveToEmpty = Int(toEmpty.rounded())
                e.liveTo10 = max(0, Int((toEmpty * Double(pct - reservePercent) / Double(pct)).rounded()))
            }
        }

        if state == .charging {
            if let t = s.psTimeToFull ?? s.avgTimeToFull {
                e.toFull = t
            } else if let full = s.fullCharge_mAh, let remaining = s.remaining_mAh, let current = avgCharge_mA, current > 10 {
                e.toFull = Int((Double(max(0, full - remaining)) / current * 60).rounded())
            }
            if let limit = s.chargeLimit?.limit {
                e.toLimit = minutesToCharge(to: limit, snapshot: s, estimates: e)
            }
        }
        return e
    }

    /// 充電中充到指定 % 大約要多久
    static func minutesToCharge(to target: Int, snapshot s: BatterySnapshot, estimates e: Estimates) -> Int? {
        guard e.state == .charging, s.percent < target else { return nil }
        if let full = s.fullCharge_mAh, let current = e.avgCharge_mA, current > 10 {
            let needed = Double(full) * Double(target - s.percent) / 100
            return Int((needed / current * 60).rounded())
        }
        if let toFull = e.toFull, s.percent < 100 {
            return toFull * (target - s.percent) / (100 - s.percent)
        }
        return nil
    }
}
