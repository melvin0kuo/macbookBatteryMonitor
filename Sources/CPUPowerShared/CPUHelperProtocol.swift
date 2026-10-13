import Foundation

public enum CPUHelperConstants {
    public static let label = "com.kuan.batterymonitor.cpu"
    public static let directory = "/Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu"
    public static let executable = directory + "/CPUPowerHelper"
    public static let configuration = directory + "/config.json"
    public static let wakeRecord = directory + "/wake.json"
    public static let launchDaemon = "/Library/LaunchDaemons/" + label + ".plist"
    /// 通訊協定改變時加一；舊版服務會被視為未安裝，需要重新授權
    public static let version = 4
    public static let wakeIdentifier = "com.kuan.batterymonitor.charging-plan"
    /// 沒有任何取樣租約多久後服務自行結束（launchd 會在下次連線時再啟動）
    public static let idleExit: TimeInterval = 30

    /// 只接受與 App 更新頻率相同的 1、2、5、10 秒；其他值取不超過它的最近一檔
    public static let samplingIntervals = [1, 2, 5, 10]
    public static func samplingInterval(_ requested: Int) -> Int { samplingIntervals.last { $0 <= requested } ?? 1 }

    /// 取樣租約的有效時間：至少 5 秒，且要比兩次要求的間隔長，App 每次更新續約
    public static func leaseDuration(interval: Int) -> TimeInterval { TimeInterval(max(5, samplingInterval(interval) * 2 + 1)) }
}

public enum WakeRequestValidator {
    public static func validate(epoch: TimeInterval, now: Date, identifier: String, uid: UInt32) -> Bool {
        guard epoch.isFinite, uid != 0, identifier == CPUHelperConstants.wakeIdentifier else { return false }
        let interval = epoch - now.timeIntervalSince1970
        return interval >= 60 && interval <= 7 * 24 * 3600
    }
}

public enum HelperRetentionPolicy {
    public static func shouldKeep(cpuSampling: Bool, preciseCharging: Bool) -> Bool {
        cpuSampling || preciseCharging
    }
}

public enum WakeSchedulePolicy {
    /// 小幅估算波動不重寫系統事件；相差五分鐘以上才更新。
    public static func shouldReplace(existing: Date?, candidate: Date) -> Bool {
        guard let existing else { return true }
        return abs(candidate.timeIntervalSince(existing)) >= 5 * 60
    }
}

public struct CPUHelperConfiguration: Codable {
    public let uid: UInt32
    public let version: Int
    public init(uid: UInt32) { self.uid = uid; version = CPUHelperConstants.version }
}

public struct CPUHelperReply: Codable {
    public let version: Int
    public let reading: CPUPowerReading?
    public let error: String?
    public init(reading: CPUPowerReading?, error: String? = nil) {
        version = CPUHelperConstants.version
        self.reading = reading
        self.error = error
    }
}

/// 不接受指令、路徑或 PID；取樣間隔只能是 1、2、5、10 秒。唯一高權限工作是固定的 CPU 功耗讀取。
@objc public protocol CPUHelperProtocol {
    func sample(active: Bool, interval: Int, withReply reply: @escaping (Data) -> Void)
    func scheduleWake(at epoch: TimeInterval, identifier: String, withReply reply: @escaping (String?) -> Void)
    func cancelWake(identifier: String, withReply reply: @escaping (String?) -> Void)
    func uninstall(withReply reply: @escaping (String?) -> Void)
}
