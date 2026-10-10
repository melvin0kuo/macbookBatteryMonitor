import Foundation
import IOKit
import IOKit.ps

struct AdapterInfo: Codable, Equatable {
    var watts: Int?
    var voltage_mV: Int?
    var current_mA: Int?
    var name: String?
}

/// 某一時間點讀到的原始電池資料。時間單位都是分鐘，nil 代表系統沒提供或還在計算。
struct BatterySnapshot: Codable, Equatable {
    var date = Date()
    var percent = 0
    var isCharging = false
    var externalConnected = false
    var fullyCharged = false
    var voltage_mV = 0
    /// 負值代表放電
    var amperage_mA = 0
    var cycleCount = 0
    var designCycleCount: Int?
    var remaining_mAh: Int?
    var fullCharge_mAh: Int?
    var nominal_mAh: Int?
    var design_mAh: Int?
    var avgTimeToEmpty: Int?
    var avgTimeToFull: Int?
    var psTimeToEmpty: Int?
    var psTimeToFull: Int?
    var temperature_C: Double?
    var notChargingReason: Int?
    var adapter: AdapterInfo?
    var systemLoad_mW: Int?
    var systemPowerIn_mW: Int?
    var lowPowerMode = false
    var serial: String?
    /// 系統設定的充電上限（沒設定時為 nil）
    var chargeLimit: ChargeLimit?

    /// AC／滿電旗標可能在停止供電後仍保留；只在有明確零輸入且放電時覆寫。
    mutating func reconcilePowerSource(inputMilliwatts: Int?) {
        if externalConnected, !isCharging, amperage_mA < -50, inputMilliwatts == 0 {
            externalConnected = false
        }
        if !externalConnected {
            isCharging = false
            adapter = nil
            systemPowerIn_mW = nil
        }
    }
}

enum BatteryReader {
    private static let smc = SMC()

    static func read(includeTemperature: Bool = true) -> BatterySnapshot? {
        guard let reg = registryProperties() else { return nil }
        let data = reg["BatteryData"] as? [String: Any] ?? [:]
        let telemetry = reg["PowerTelemetryData"] as? [String: Any] ?? [:]
        let charger = reg["ChargerData"] as? [String: Any] ?? [:]
        let ps = internalBatteryDescription() ?? [:]

        // 新舊系統的 key 位置不同：有的在頂層，有的在 BatteryData 裡
        func lookup(_ keys: String...) -> Int? {
            for key in keys {
                if let v = int(reg[key]) ?? int(data[key]) { return v }
            }
            return nil
        }

        var s = BatterySnapshot()
        if let cur = int(ps["Current Capacity"]), let max = int(ps["Max Capacity"]), max > 0 {
            s.percent = cur * 100 / max
        } else if let cur = int(reg["CurrentCapacity"]), let max = int(reg["MaxCapacity"]), max > 0 {
            s.percent = cur * 100 / max
        }
        s.isCharging = bool(ps["Is Charging"]) ?? bool(reg["IsCharging"]) ?? false
        if let state = ps["Power Source State"] as? String {
            s.externalConnected = state == "AC Power"
        } else {
            s.externalConnected = bool(reg["ExternalConnected"]) ?? false
        }
        s.fullyCharged = bool(reg["FullyCharged"]) ?? bool(ps["Is Charged"]) ?? false
        s.voltage_mV = int(reg["Voltage"]) ?? int(reg["AppleRawBatteryVoltage"]) ?? 0
        s.amperage_mA = int(reg["Amperage"]) ?? int(reg["InstantAmperage"]) ?? 0
        s.cycleCount = int(reg["CycleCount"]) ?? 0
        s.designCycleCount = int(reg["DesignCycleCount9C"]) ?? int(reg["DesignCycleCount"])
        s.remaining_mAh = lookup("AppleRawCurrentCapacity", "RemainingCapacity")
        s.fullCharge_mAh = lookup("AppleRawMaxCapacity", "FullChargeCapacity")
        s.nominal_mAh = lookup("NominalChargeCapacity")
        s.design_mAh = lookup("DesignCapacity")
        s.avgTimeToEmpty = validMinutes(int(reg["AvgTimeToEmpty"]))
        s.avgTimeToFull = validMinutes(int(reg["AvgTimeToFull"]))
        s.psTimeToEmpty = validMinutes(int(ps["Time to Empty"]))
        s.psTimeToFull = validMinutes(int(ps["Time to Full Charge"]))
        s.notChargingReason = int(charger["NotChargingReason"]) ?? int(reg["NotChargingReason"])
        s.systemLoad_mW = positive(int(telemetry["SystemLoad"]))
        s.systemPowerIn_mW = positive(int(telemetry["SystemPowerIn"]))
        s.reconcilePowerSource(inputMilliwatts: int(telemetry["SystemPowerIn"]))
        s.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        s.serial = reg["Serial"] as? String
        s.chargeLimit = ChargeLimitReader.current()

        if let t = int(reg["Temperature"]) ?? int(data["Temperature"]) ?? int(reg["VirtualTemperature"]), t > 0 {
            s.temperature_C = Double(t) / 100
        } else if includeTemperature {
            s.temperature_C = smc?.batteryTemperature()
        }

        if s.externalConnected, let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            s.adapter = AdapterInfo(
                watts: int(details["Watts"]),
                voltage_mV: int(details["AdapterVoltage"]) ?? int(details["Voltage"]),
                current_mA: int(details["Current"]),
                name: (details["Name"] as? String) ?? (details["Description"] as? String)
            )
        }
        return s
    }

    private static func registryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    private static func internalBatteryDescription() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if desc["Type"] as? String == "InternalBattery" { return desc }
        }
        return nil
    }

    /// 負數會以 64-bit 補數存在 registry 裡，用 int64Value 取回帶正負號的值
    private static func int(_ any: Any?) -> Int? {
        guard let n = any as? NSNumber else { return nil }
        return Int(truncatingIfNeeded: n.int64Value)
    }

    private static func bool(_ any: Any?) -> Bool? {
        (any as? NSNumber)?.boolValue
    }

    private static func validMinutes(_ v: Int?) -> Int? {
        guard let v, v > 0, v < 65535 else { return nil }
        return v
    }

    private static func positive(_ v: Int?) -> Int? {
        guard let v, v > 0 else { return nil }
        return v
    }
}
