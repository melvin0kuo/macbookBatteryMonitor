import Foundation
import Darwin

/// 私有介面可用時才訂閱 Energy Model；所有權與取樣均限制在同一背景佇列。
final class IOReportReader {
    private typealias Copy = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias Subscribe = @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary?, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?) -> Unmanaged<CFTypeRef>?
    private typealias Sample = @convention(c) (CFTypeRef?, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias Label = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias Value = @convention(c) (CFDictionary, Int32) -> Int64
    private static let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY)
    private let channels: CFMutableDictionary
    private let subscription: CFTypeRef
    private let sample: Sample
    private let name: Label
    private let unit: Label
    private let value: Value

    init?() {
        guard let library = Self.library else { return nil }
        func function<T>(_ key: String, as type: T.Type) -> T? {
            guard let address = dlsym(library, key) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        guard let copy = function("IOReportCopyChannelsInGroup", as: Copy.self),
              let subscribe = function("IOReportCreateSubscription", as: Subscribe.self),
              let sample = function("IOReportCreateSamples", as: Sample.self),
              let name = function("IOReportChannelGetChannelName", as: Label.self),
              let unit = function("IOReportChannelGetUnitLabel", as: Label.self),
              let value = function("IOReportSimpleGetIntegerValue", as: Value.self),
              let original = copy("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let channels = CFDictionaryCreateMutableCopy(nil, 0, original) else {
            return nil
        }
        var selected: Unmanaged<CFMutableDictionary>?
        guard let subscription = subscribe(nil, channels, &selected, 0, nil)?.takeRetainedValue() else {
            _ = selected?.takeRetainedValue()
            return nil
        }
        self.channels = selected?.takeRetainedValue() ?? channels
        self.subscription = subscription
        self.sample = sample
        self.name = name
        self.unit = unit
        self.value = value
    }

    // 系統 library 保持載入，CF 訂閱釋放時仍可執行其析構函數。
    func sampleEnergy() -> [String: Double] {
        guard let report = sample(subscription, channels, nil)?.takeRetainedValue(),
              let list = (report as NSDictionary)["IOReportChannels"] as? NSArray else { return [:] }
        var pairs: [(String, Double)] = []
        for raw in list {
            guard let dictionary = raw as? NSDictionary else { continue }
            // IOReport 的 accessor 會寫回快取，必須保留其原生 dictionary。
            let channel = unsafeBitCast(dictionary, to: CFDictionary.self)
            guard let label = name(channel)?.takeUnretainedValue() as String?,
                  let unit = unit(channel)?.takeUnretainedValue() as String? else { continue }
            let component: String
            switch label {
            case let label where label.hasSuffix("CPU Energy"): component = "cpu"
            case let label where label.hasSuffix("GPU Energy"): component = "gpu"
            case let label where label.hasPrefix("ANE"): component = "ane"
            default: continue
            }
            if let joules = EnergyCounter.joules(Double(value(channel, 0)), unit: unit) {
                pairs.append((component, joules))
            }
        }
        return EnergyCounter.collect(pairs)
    }
}
