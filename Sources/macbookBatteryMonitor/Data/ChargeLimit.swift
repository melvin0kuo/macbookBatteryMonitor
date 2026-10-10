import Foundation

/// 系統設定「電池健康度與充電」裡的充電上限。
/// powerd 把目前生效的充電策略存成 NSKeyedArchiver 格式（類別名 ChargeCtrlPolicy），
/// 檔案權限一般使用者可讀，這裡只讀不寫。
/// 注意：這份策略只在接電時存在，拔掉電源後會被清空；使用者設定本身存在一般權限讀不到的地方。
struct ChargeLimit: Codable, Equatable {
    /// 上限 %
    var limit: Int
    /// 例如 manualChargeLimit（使用者手動設定）
    var reason: String
    /// false 表示目前沒在生效（用電池中），數值是上次接電時讀到的
    var active = true
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
    private static let lastKnownKey = "lastKnownChargeLimit"
    /// 接電後等這麼久還沒有生效中的策略，就當作使用者已經關掉充電上限
    private static let clearAfterPlugged: TimeInterval = 120

    /// 用電池時策略會被清空，所以記住最後一次讀到的值。
    /// - Parameter pluggedSince: 這次接上電源的時間；nil 表示不判斷是否已關閉（只讀不清除）
    static func resolve(externalConnected: Bool, pluggedSince: Date?) -> ChargeLimit? {
        let defaults = UserDefaults.standard
        if let live = current() {
            defaults.set(live.limit, forKey: lastKnownKey)
            return live
        }
        let cached = defaults.integer(forKey: lastKnownKey)
        guard cached > 0 else { return nil }
        if externalConnected, let pluggedSince, Date().timeIntervalSince(pluggedSince) > clearAfterPlugged {
            defaults.removeObject(forKey: lastKnownKey)
            return nil
        }
        return ChargeLimit(limit: cached, reason: "lastKnown", active: false)
    }

    /// 給設定頁用：生效中的值，沒有就用上次記住的
    static func lastKnown() -> ChargeLimit? {
        resolve(externalConnected: false, pluggedSince: nil)
    }
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
