import Foundation

/// `BatteryMonitor --dump`：把目前讀到的資料印成 JSON，方便和 pmset / system_profiler 對照
enum DumpCommand {
    private struct Output: Encodable {
        var snapshot: BatterySnapshot
        var estimates: Estimates
        var systemHealth: SystemHealth?
        var lastUnplugged: Date?
        var topProcesses: [EnergyProcess]
        var loginItem: String
    }

    static func run() {
        guard let s = BatteryReader.read() else {
            print(#"{"error": "找不到電池"}"#)
            return
        }
        let current = Double(abs(s.amperage_mA))
        let e = Estimator.estimates(
            s,
            avgDischarge_mA: s.amperage_mA < 0 ? current : nil,
            avgCharge_mA: s.amperage_mA > 0 ? current : nil
        )
        let output = Output(
            snapshot: s,
            estimates: e,
            systemHealth: SystemProfiler.readSync(),
            lastUnplugged: e.state == .discharging ? PowerLog.lastUnpluggedDateSync() : nil,
            topProcesses: ProcessEnergy.sampleSync(),
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
