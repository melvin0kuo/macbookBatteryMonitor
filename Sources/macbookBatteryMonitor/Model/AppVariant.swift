import Foundation

enum AppVariant {
    #if BATTERY_LITE
    static let isLite = true
    #else
    static let isLite = false
    #endif
    static var name: String { isLite ? "Lite 省電版" : "Full 完整版" }
    static var openInterval: TimeInterval { isLite ? 5 : 1 }
    static var historyDirectory: String { isLite ? "BatteryMonitorLite" : "BatteryMonitor" }
}
