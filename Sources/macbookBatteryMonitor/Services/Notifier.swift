import Foundation
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var lowFired = false
    private var fullFired = false

    /// 沒打包成 .app（例如直接 swift run）時沒有 bundle id，通知中心會直接 crash
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func setup() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 每次跨過門檻只通知一次，離開門檻一段距離後才會再通知
    func evaluate(_ s: BatterySnapshot, state: PowerState, settings: AppSettings) {
        let pct = s.percent

        if state == .discharging, pct <= settings.lowThreshold {
            if settings.lowAlertEnabled, !lowFired {
                post(title: "電量偏低：\(pct)%", body: "電量已低於 \(settings.lowThreshold)%，建議接上電源。")
            }
            lowFired = true
        } else if state != .discharging || pct > settings.lowThreshold + 2 {
            lowFired = false
        }

        // 有系統充電上限時，充到上限就不會再往上，所以到上限也算充電完成
        let limit = s.chargeLimit?.limit
        let target = min(settings.fullThreshold, limit ?? 100)
        if s.externalConnected, pct >= settings.fullThreshold || state == .limitReached {
            if settings.fullAlertEnabled, !fullFired {
                let body: String
                if state == .limitReached, let limit {
                    body = "已達充電上限 \(limit)%，電池暫停充電。"
                } else if settings.fullThreshold >= 100 {
                    body = "電池已充飽，可以拔掉電源。"
                } else {
                    body = "已充到 \(settings.fullThreshold)%，可以拔掉電源。"
                }
                post(title: "充電完成：\(pct)%", body: body)
            }
            fullFired = true
        } else if !s.externalConnected || pct < target - 5 {
            fullFired = false
        }
    }

    func sendTest() {
        post(title: "電池監控", body: "通知功能正常 👍")
    }

    private func post(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
