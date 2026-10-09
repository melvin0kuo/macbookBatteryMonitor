import Foundation

/// 系統設定「電池健康度與充電」裡的充電上限。
/// powerd 把目前生效的充電策略存成 NSKeyedArchiver 格式（類別名 ChargeCtrlPolicy），
/// 檔案權限一般使用者可讀，這裡只讀不寫。
struct ChargeLimit: Codable, Equatable {
    /// 上限 %
    var limit: Int
    /// 例如 manualChargeLimit（使用者手動設定）
    var reason: String
}

/// 對應系統的 ChargeCtrlPolicy，只解出需要的欄位
@objc(BMChargeCtrlPolicy)
private final class ChargeCtrlPolicyStub: NSObject, NSCoding {
    let soclimit: Int
    let reason: String?
    let terminated: Bool

    init?(coder: NSCoder) {
        soclimit = coder.decodeInteger(forKey: "soclimit")
        reason = coder.decodeObject(forKey: "reason") as? String
        terminated = coder.decodeBool(forKey: "terminated")
    }

    func encode(with coder: NSCoder) {}
}

enum ChargeLimitReader {
    private static let url = URL(fileURLWithPath: "/Library/Preferences/com.apple.powerd.charging.plist")
    private static var cachedDate: Date?
    private static var cached: ChargeLimit?

    /// 檔案沒變就用上次的結果，不重複解析
    static func current() -> ChargeLimit? {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let modified, modified == cachedDate { return cached }
        cachedDate = modified
        cached = read()
        return cached
    }

    private static func read() -> ChargeLimit? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let archive = plist["policies"] as? Data,
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: archive) else { return nil }
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(ChargeCtrlPolicyStub.self, forClassName: "ChargeCtrlPolicy")
        let policies = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [Any] ?? []
        unarchiver.finishDecoding()

        // 可能同時有多個策略（例如最佳化充電暫停），取生效中且上限最低的
        let active = policies
            .compactMap { $0 as? ChargeCtrlPolicyStub }
            .filter { !$0.terminated && $0.soclimit > 0 && $0.soclimit < 100 }
            .min { $0.soclimit < $1.soclimit }
        guard let active else { return nil }
        return ChargeLimit(limit: active.soclimit, reason: active.reason ?? "")
    }
}
