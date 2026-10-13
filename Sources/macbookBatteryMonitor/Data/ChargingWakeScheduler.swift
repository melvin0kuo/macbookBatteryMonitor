import Foundation
import Observation
import CPUPowerShared

@MainActor
@Observable
final class ChargingWakeScheduler {
    private(set) var status = "使用一般睡眠策略"
    private(set) var scheduledAt: Date?
    private(set) var authorizing = false

    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var installLease: URL?
    @ObservationIgnored private var requestedAt: Date?
    @ObservationIgnored private var cancellationSynced = false
    @ObservationIgnored private var previousEnabled: Bool?
    @ObservationIgnored private let helperBundle: Bundle
    @ObservationIgnored private let enabledInThisProcess: Bool

    init(bundle: Bundle = .main) {
        helperBundle = bundle
        enabledInThisProcess = bundle.bundleIdentifier == "com.kuan.batterymonitor"
            && !CommandLine.arguments.contains { $0.hasPrefix("--snapshot") || $0.hasPrefix("--screenshots") }
    }

    var hasUsableScheduledWake: Bool {
        scheduledAt.map { $0.timeIntervalSinceNow >= 30 } ?? false
    }

    func sync(decision: ChargingPlanDecision?, enabled: Bool) {
        guard enabledInThisProcess else { return }
        let launching = previousEnabled == nil
        previousEnabled = enabled
        guard enabled else {
            guard !cancellationSynced else { return }
            cancel(uninstallIfUnused: true)
            cancellationSynced = true
            status = "使用一般睡眠策略"
            return
        }
        guard CPUHelperInstaller.installed else {
            if launching {
                AppSettings.shared.preciseChargingScheduling = false
                status = "排程服務尚未授權，暫用優先準時完成；請在設定重新開啟"
                return
            }
            cancellationSynced = false
            guard process == nil else { return }
            install()
            return
        }
        guard let wakeAt = decision?.wakeAt, wakeAt.timeIntervalSinceNow >= 60 else {
            guard !cancellationSynced else { return }
            cancel(uninstallIfUnused: false)
            cancellationSynced = true
            status = decision == nil ? "等待充電排程" : "目前不需要安排喚醒"
            return
        }
        guard WakeSchedulePolicy.shouldReplace(existing: requestedAt, candidate: wakeAt) else { return }
        cancellationSynced = false
        schedule(wakeAt)
    }

    func stop() {
        connection?.invalidate()
        connection = nil
        if let installLease { try? FileManager.default.removeItem(at: installLease) }
        installLease = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        authorizing = false
    }

    private func install() {
        do {
            let lease = FileManager.default.temporaryDirectory.appendingPathComponent("wake-install-\(UUID().uuidString)")
            try Data().write(to: lease, options: .atomic)
            installLease = lease
            let task = try CPUHelperInstaller.makeProcess(bundle: helperBundle, lease: lease)
            task.terminationHandler = { [weak self] task in
                Task { @MainActor in
                    guard let self else { return }
                    self.process = nil
                    if let lease = self.installLease { try? FileManager.default.removeItem(at: lease) }
                    self.installLease = nil
                    self.authorizing = false
                    guard AppSettings.shared.preciseChargingScheduling else {
                        self.cancellationSynced = false
                        self.sync(decision: nil, enabled: false)
                        return
                    }
                    guard task.terminationStatus == 0, CPUHelperInstaller.installed else {
                        AppSettings.shared.preciseChargingScheduling = false
                        self.status = "授權已取消或服務安裝失敗，已改用一般睡眠策略"
                        return
                    }
                    self.status = "服務已授權，等待充電排程"
                }
            }
            process = task
            authorizing = true
            status = "等待系統管理員授權"
            try task.run()
        } catch {
            process = nil
            authorizing = false
            AppSettings.shared.preciseChargingScheduling = false
            status = "無法安裝排程服務：\(error.localizedDescription)"
        }
    }

    private func connect() -> CPUHelperProtocol? {
        if connection == nil {
            let value = NSXPCConnection(machServiceName: CPUHelperConstants.label, options: .privileged)
            value.remoteObjectInterface = NSXPCInterface(with: CPUHelperProtocol.self)
            value.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            connection = value
            value.resume()
        }
        return connection?.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in
                self?.connection?.invalidate()
                self?.connection = nil
                self?.status = "排程服務暫時無法連線，已改用一般睡眠策略"
            }
        } as? CPUHelperProtocol
    }

    private func schedule(_ date: Date) {
        guard let proxy = connect() else { return }
        requestedAt = date
        cancellationSynced = false
        proxy.scheduleWake(at: date.timeIntervalSince1970, identifier: CPUHelperConstants.wakeIdentifier) { [weak self] error in
            Task { @MainActor in
                guard let self, self.requestedAt == date else { return }
                if let error {
                    self.scheduledAt = nil
                    self.status = "\(error)，已改用一般睡眠策略"
                } else {
                    self.scheduledAt = date
                    self.status = "已安排喚醒"
                }
            }
        }
    }

    private func cancel(uninstallIfUnused: Bool) {
        requestedAt = nil
        scheduledAt = nil
        guard CPUHelperInstaller.installed, let proxy = connect() else { return }
        proxy.cancelWake(identifier: CPUHelperConstants.wakeIdentifier) { error in
            Task { @MainActor in
                guard error == nil, uninstallIfUnused,
                      !HelperRetentionPolicy.shouldKeep(cpuSampling: AppSettings.shared.adminCPUSampling,
                                                        preciseCharging: AppSettings.shared.preciseChargingScheduling) else { return }
                proxy.uninstall { _ in }
            }
        }
    }
}
