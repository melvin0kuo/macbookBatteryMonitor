import AppKit
import IOKit.ps
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = BatteryStore()
    private let settings = AppSettings.shared
    private let ui = PanelState()
    /// CPU／GPU、記憶體、磁碟、網路模組
    private let monitors = ModuleCoordinator()
    private var statusItem: NSStatusItem!
    /// 每次打開都建立新的，關閉後整個釋放（連同視窗和 SwiftUI 畫面）
    private var popover: NSPopover?
    private var refreshTimer: Timer?
    /// 更新頻率慢於每秒時，下一次更新前 1 秒先讀變壓器輸入（見 BatteryReader.recordAdapterInput）
    private var adapterPreReadTimer: Timer?
    private var processTimer: Timer?
    private var timers: [Timer] = []
    /// 上次畫到選單列的內容，沒變就不重畫
    private var lastStatusKey = ""
    private var sleeping = false
    private var powerTransitionTask: Task<Void, Never>?

    /// 所有資訊依設定的更新頻率更新（預設每秒，省電模式至少 2 秒）；面板關著時也一樣（插拔電源另由 IOPS 通知立即更新）。
    /// 同一個間隔也用來檢查耗電排行分頁是否顯示中，以決定要不要持續取樣
    private var interval: TimeInterval { settings.sampleInterval }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 已經有一個在執行（例如登入項目與舊的 LaunchAgent 同時啟動）就直接結束，避免兩個圖示、兩份通知
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != NSRunningApplication.current }) {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageTrailing
        }

        settings.onChange = { [weak self] in self?.updateStatusItem() }
        settings.onIntervalChange = { [weak self] in self?.applySampleInterval() }
        settings.onPreciseChargingChange = { [weak self] in self?.store.syncChargingWake() }
        // 電池版不建立任何系統監控圖示與計時器
        if AppEdition.current.hasSystemMonitors {
            settings.onMonitorsChange = { [weak self] in self?.monitors.syncItems() }
            monitors.openSettings = { [weak self] in self?.showPopover(page: .settings) }
            monitors.start()
        }
        store.adminCPU.authorizationChanged = { [weak self] pending in
            self?.popover?.behavior = pending ? .applicationDefined : .transient
        }
        Notifier.shared.setup()
        // 藍牙權限還沒決定時 macOS 會跳出詢問（第一次啟動時問一次）；已經允許就直接在背景讀；拒絕過就不再問
        if !BLEBatteryReader.denied { store.peripherals.startBluetoothLE() }
        // 用新版覆蓋 App 後，自訂的 App 圖示會消失，套回使用者選的顏色
        AppIconChanger.restoreIfNeeded(settings.appIconColor)

        refresh()
        store.recordHistory()
        store.refreshHealth()
        store.resolveUnpluggedDateIfNeeded()
        store.backfillHistory()
        scheduleRefresh(every: interval)
        timers.append(repeating(every: 60) { $0.store.recordHistory() })
        timers.append(repeating(every: 6 * 3600) { $0.store.refreshHealth() })
        // 周邊設備電量變化很慢，每 60 秒查一次；面板停在周邊設備分頁時連所有藍牙設備一起查
        store.peripherals.refresh()
        // 系統充電上限：啟動時讀一次，之後由系統通知、打開面板時重新讀取；在面板上調整後立即更新選單列與面板
        store.chargeLimit.onChange = { [weak self] in
            guard let self, !self.sleeping else { return }
            self.refresh()
        }
        store.chargeLimit.start()
        // 自動檢查更新：啟動 15 秒後與之後每 6 小時看一次，距離上次檢查超過一天才真的連線
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.settings.autoCheckUpdates else { return }
            self.store.updater.checkIfDue()
        }
        timers.append(repeating(every: 6 * 3600) { delegate in
            guard delegate.settings.autoCheckUpdates, !delegate.sleeping else { return }
            delegate.store.updater.checkIfDue()
        })
        timers.append(repeating(every: PeripheralStore.interval) { delegate in
            guard !delegate.sleeping else { return }
            delegate.store.peripherals.refresh(includeAllBluetooth: delegate.ui.isVisible && delegate.ui.page == .main && delegate.ui.tab == .peripherals)
        })

        observePowerSourceChanges()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil
        )
        registerLoginItemIfNeeded()
        runPanelSelfTestIfRequested()
        runUpdateSelfTestIfRequested()
    }

    /// 開發用：`--selftest-update` 檢查 GitHub 上的新版本，有就直接一鍵更新（App 會結束並由安裝程序重新開啟）
    private func runUpdateSelfTestIfRequested() {
        guard CommandLine.arguments.contains("--selftest-update") else { return }
        Task { [weak self] in
            guard let updater = self?.store.updater else { return }
            print("selftest: 目前版本 \(updater.currentVersion)，可以安裝：\(updater.canInstall)")
            await updater.check(userInitiated: true)
            print("selftest: 檢查結果 \(updater.state)")
            guard updater.available != nil else { return }
            await updater.install()
            print("selftest: 安裝結果 \(updater.state)")
        }
    }

    /// 開發用：`--selftest-panel` 會打開面板（耗電排行分頁）20 秒後自動關閉，用來確認關閉後取樣會停
    private func runPanelSelfTestIfRequested() {
        let hardware = CommandLine.arguments.contains("--selftest-hardware")
        guard hardware || CommandLine.arguments.contains("--selftest-panel") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            ui.tab = hardware ? .details : .processes
            ui.powerFlowLevel = hardware ? .components : .overview
            showPopover(page: .main)
            if hardware {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                    self?.ui.powerFlowLevel = .chip
                    print("selftest: chip expanded")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                    self?.ui.page = .settings
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                    print("selftest: settings sampling stopped \(self?.store.componentPower == nil)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 11) { [weak self] in
                    self?.ui.page = .main
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self] in
                    print("selftest: hardware sampling resumed \(self?.store.componentPower != nil)")
                    // 管理員 CPU 取樣開著時，確認讀得到 powermetrics 的 CPU 功耗
                    let cpu = self?.store.componentPower?.cpuWatts.map { String(format: "%.2f W", $0) } ?? "—"
                    print("selftest: cpu \(cpu)（管理員 CPU 取樣：\(self?.store.adminCPU.status ?? "")）")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 22) { [weak self] in
                    print("selftest: closed sampling stopped \(self?.store.componentPower == nil)")
                }
            }
            print("selftest: opened \(popover?.contentSize ?? .zero)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.popover?.performClose(nil)
                print("selftest: closed")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.adminCPU.stop()
        store.chargingWake.stop()
        store.history.save()
    }

    // MARK: - Refresh

    private func refresh() {
        store.refresh()
        scheduleAdapterPreRead()
        store.setHardwareSampling(active: ui.isVisible && ui.page == .main && !sleeping)
        updateStatusItem()
        if let s = store.snapshot, let e = store.estimates {
            Notifier.shared.evaluate(s, state: e.state, settings: settings)
        }
        if let plan = store.chargingPlan.plan {
            if store.chargingPlan.consumeReadyNotification() {
                Notifier.shared.notifyChargingPlan(.ready, target: plan.targetPercent, deadline: plan.deadline)
            } else if store.chargingPlan.consumeLateNotification() {
                Notifier.shared.notifyChargingPlan(.late, target: plan.targetPercent, deadline: plan.deadline)
            }
        }
    }

    /// 更新頻率或省電模式改變後，所有計時器與 top 改用新的間隔
    private func applySampleInterval() {
        scheduleRefresh(every: interval)
        if processTimer != nil { scheduleProcessCheck() }
        if AppEdition.current.hasSystemMonitors { monitors.applySampleInterval() }
    }

    private func scheduleRefresh(every interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = repeating(every: interval) { $0.refresh() }
        // 誤差不超過 0.3 秒，下一次更新才配得到 1 秒前預先讀的變壓器輸入
        refreshTimer?.tolerance = min(interval * 0.2, 0.3)
    }

    private func scheduleAdapterPreRead() {
        adapterPreReadTimer?.invalidate()
        adapterPreReadTimer = nil
        guard interval > 1, !sleeping else { return }
        let timer = Timer(fire: Date().addingTimeInterval(interval - 1), interval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { BatteryReader.recordAdapterInput() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        adapterPreReadTimer = timer
    }

    private func repeating(every interval: TimeInterval, _ action: @escaping (AppDelegate) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// 插拔電源時馬上更新，不用等計時器
    private func observePowerSourceChanges() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.powerSourceChanged() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// 插拔通知可能比 Registry／SMC 資料早到；短暫重讀後恢復正常間隔。
    private func powerSourceChanged() {
        powerTransitionTask?.cancel()
        refresh()
        powerTransitionTask = Task { [weak self] in
            for delay in [1, 2, 3] {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, !sleeping else { return }
                refresh()
            }
        }
    }

    @objc private func willSleep() {
        store.prepareChargingPlanForSleep()
        sleeping = true
        powerTransitionTask?.cancel()
        store.setHardwareSampling(active: false)
        store.setProcessSampling(active: false)
        monitors.setSleeping(true)
        store.history.save()
    }

    @objc private func didWake() {
        sleeping = false
        monitors.setSleeping(false)
        refresh()
        store.reevaluateChargingPlanAfterWake()
        store.peripherals.refresh()
        store.recordHistory()
    }

    // MARK: - Status item

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        guard let s = store.snapshot, let e = store.estimates else {
            guard lastStatusKey != "noBattery" else { return }
            button.image = NSImage(systemSymbolName: "battery.0percent", accessibilityDescription: "找不到電池")
            button.title = ""
            lastStatusKey = "noBattery"
            return
        }
        let low = e.state == .discharging && s.percent <= settings.lowThreshold
        let minutes = e.state == .charging ? e.headlineToFull : e.headlineToEmpty
        let showsTime = settings.display == .iconAndTime || settings.display == .iconPercentAndTime
        let key = "\(s.percent)|\(e.state)|\(low)|\(settings.display)|\(showsTime ? minutes ?? -1 : 0)"
        guard key != lastStatusKey else { return }
        lastStatusKey = key

        let inlinePercent = settings.display == .iconPercentAndTime
        button.imagePosition = inlinePercent ? .imageLeading : .imageTrailing
        button.image = settings.display == .percentOnly ? nil : StatusIconRenderer.image(percent: s.percent, state: e.state, low: low, showsPercent: inlinePercent)
        let text: String
        switch settings.display {
        case .iconAndPercent:
            text = "\(s.percent)%"
        case .percentOnly:
            text = e.state == .charging ? "⚡\(s.percent)%" : "\(s.percent)%"
        case .iconOnly:
            text = ""
        case .iconAndTime, .iconPercentAndTime:
            let fallback = inlinePercent ? "—" : "\(s.percent)%"
            switch e.state {
            case .discharging: text = Format.clock(e.headlineToEmpty) ?? fallback
            case .charging: text = Format.clock(e.headlineToFull) ?? fallback
            case .full: text = inlinePercent ? "已充飽" : fallback
            case .pluggedIdle: text = e.drainingOnAC ? (Format.clock(e.headlineToEmpty) ?? fallback) : (inlinePercent ? "接電" : fallback)
            case .limitReached: text = inlinePercent ? "已達上限" : fallback
            }
        }
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)]
        )
        button.toolTip = tooltip(s, e)
    }

    private func tooltip(_ s: BatterySnapshot, _ e: Estimates) -> String {
        switch e.state {
        case .discharging:
            return "電池 \(s.percent)% · 剩餘 \(Format.duration(e.headlineToEmpty))"
        case .charging:
            if let limit = s.chargeLimit?.limit, s.percent < limit {
                return "電池 \(s.percent)% · 充到 \(limit)% 還要 \(Format.duration(e.toLimit))"
            }
            return "電池 \(s.percent)% · 充滿還要 \(Format.duration(e.toFull))"
        case .limitReached:
            return "電池 \(s.percent)% · 已達充電上限 \(s.chargeLimit?.limit ?? 100)%"
        case .pluggedIdle, .full:
            return "電池 \(s.percent)% · \(e.state.title)"
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(page: .main)
        }
    }

    private func showPopover(page: PanelPage) {
        guard let button = statusItem.button else { return }
        if let popover, popover.isShown {
            ui.page = page
            return
        }
        ui.page = page
        ui.isVisible = true
        store.panelVisible = true
        store.chargeLimit.panelOpened()
        refresh()
        // 面板每次打開才建立、關掉就釋放，關著時不會有任何 SwiftUI 畫面在背景更新
        let hosting = NSHostingController(rootView: RootView(store: store, settings: settings, ui: ui))
        hosting.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = store.adminCPU.authorizing ? .applicationDefined : .transient
        popover.delegate = self
        popover.contentViewController = hosting
        // 先算好尺寸再顯示，避免面板從 0 大小長出來
        popover.contentSize = hosting.view.fittingSize
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打開面板", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "結束\(AppEdition.current.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanel() {
        showPopover(page: .main)
    }

    @objc private func openSettings() {
        showPopover(page: .settings)
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        scheduleRefresh(every: interval)
        scheduleProcessCheck()
    }

    private func scheduleProcessCheck() {
        processTimer?.invalidate()
        processTimer = repeating(every: interval) { delegate in
            delegate.store.setProcessSampling(active: !delegate.sleeping && delegate.ui.page == .main && delegate.ui.tab == .processes)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover, closed === popover else { return }
        store.panelVisible = false
        store.setHardwareSampling(active: false)
        store.setProcessSampling(active: false)
        processTimer?.invalidate()
        processTimer = nil
        scheduleRefresh(every: interval)
        ui.page = .main
        ui.isVisible = false
        // 等這次 delegate 回呼結束再釋放；這段時間若又打開新面板，不要動到它
        DispatchQueue.main.async { [weak self] in
            closed.contentViewController = nil
            if self?.popover === closed { self?.popover = nil }
        }
    }

    // MARK: - Login item

    /// 從 /Applications 啟動、而且這個位置還沒註冊過開機自啟動時（第一次安裝、App 改名或搬移）自動註冊。
    /// 使用者在設定裡關掉後就不再自動開啟。
    private func registerLoginItemIfNeeded() {
        let defaults = UserDefaults.standard
        let path = Bundle.main.bundlePath
        guard LoginItem.isInApplications,
              !defaults.bool(forKey: LoginItem.disabledByUserKey),
              defaults.string(forKey: LoginItem.registeredPathKey) != path else { return }
        // 登錄成功才記下位置，失敗的話下次啟動會再試
        if (try? LoginItem.setEnabled(true)) != nil {
            defaults.set(path, forKey: LoginItem.registeredPathKey)
        }
    }
}
