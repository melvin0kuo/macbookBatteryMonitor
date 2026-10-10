import Foundation

/// `macbookBatteryMonitor --dump`：把目前讀到的資料印成 JSON，方便和 pmset / system_profiler 對照
enum DumpCommand {
    static func runHardware() {
        guard !AppVariant.isLite else {
            print(#"{"error":"Lite 版本不提供硬體分層取樣"}"#)
            return
        }
        let reader = HardwarePowerReader()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for index in 0..<5 {
            let sample = reader.sample()
            if let data = try? encoder.encode(sample), let line = String(data: data, encoding: .utf8) {
                print(line)
            }
            if index < 4 { Thread.sleep(forTimeInterval: 1) }
        }
    }

    private struct Output: Encodable {
        var variant: String
        var snapshot: BatterySnapshot
        var estimates: Estimates
        var systemHealth: SystemHealth?
        var lastUnplugged: Date?
        var topProcesses: [EnergyProcess]
        var loginItem: String
    }

    static func run() {
        guard var s = BatteryReader.read() else {
            print(#"{"error": "找不到電池"}"#)
            return
        }
        s.chargeLimit = ChargeLimitReader.resolve(externalConnected: s.externalConnected, pluggedSince: nil)
        let current = Double(abs(s.effectiveAmperage_mA))
        let e = Estimator.estimates(
            s,
            avgDischarge_mA: s.effectiveAmperage_mA < 0 ? current : nil,
            avgCharge_mA: s.effectiveAmperage_mA > 0 ? current : nil
        )
        let output = Output(
            variant: AppVariant.name,
            snapshot: s,
            estimates: e,
            systemHealth: SystemProfiler.readSync(),
            lastUnplugged: e.state == .discharging ? PowerLog.lastUnpluggedDateSync() : nil,
            topProcesses: AppVariant.isLite ? [] : ProcessEnergy.sampleSync(),
            loginItem: "\(LoginItem.status)"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(output), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
}
