import AppKit
import IOKit.ps
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = BatteryStore()
    private let settings = AppSettings.shared
    private let ui = PanelState()
    private var statusItem: NSStatusItem!
    /// 每次打開都建立新的，關閉後整個釋放（連同視窗和 SwiftUI 畫面）
    private var popover: NSPopover?
    private var refreshTimer: Timer?
    private var processTimer: Timer?
    private var timers: [Timer] = []
    /// 上次畫到選單列的內容，沒變就不重畫
    private var lastStatusKey = ""
    private var sleeping = false

    /// 面板關著時的更新間隔。插拔電源由 IOPS 通知即時更新，不靠這個計時器
    private static let idleInterval: TimeInterval = 30
    private static let openInterval: TimeInterval = 1
    private static let processInterval: TimeInterval = 5

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageTrailing
        }

        settings.onChange = { [weak self] in self?.updateStatusItem() }
        Notifier.shared.setup()

        refresh()
        store.recordHistory()
        store.refreshHealth()
        store.resolveUnpluggedDateIfNeeded()
        store.backfillHistory()
        scheduleRefresh(every: Self.idleInterval)
        timers.append(repeating(every: 60) { $0.store.recordHistory() })
        timers.append(repeating(every: 6 * 3600) { $0.store.refreshHealth() })

        observePowerSourceChanges()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil
        )
        registerLoginItemIfNeeded()
        runPanelSelfTestIfRequested()
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
        store.history.save()
    }

    // MARK: - Refresh

    private func refresh() {
        store.refresh()
        store.setHardwareSampling(active: ui.isVisible && ui.page == .main && !sleeping)
        updateStatusItem()
        if let s = store.snapshot, let e = store.estimates {
            Notifier.shared.evaluate(s, state: e.state, settings: settings)
        }
    }

    private func scheduleRefresh(every interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = repeating(every: interval) { $0.refresh() }
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
            MainActor.assumeIsolated { delegate.refresh() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    @objc private func willSleep() {
        sleeping = true
        store.setHardwareSampling(active: false)
        store.history.save()
    }

    @objc private func didWake() {
        sleeping = false
        refresh()
        store.recordHistory()
    }

    // MARK: - Status item

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        guard let s = store.snapshot, let e = store.estimates else {
            button.image = NSImage(systemSymbolName: "battery.0percent", accessibilityDescription: "找不到電池")
            button.title = ""
            lastStatusKey = ""
            return
        }
        let low = e.state == .discharging && s.percent <= settings.lowThreshold
        let minutes = e.state == .charging ? e.headlineToFull : e.headlineToEmpty
        let key = "\(s.percent)|\(e.state)|\(low)|\(settings.display)|\(settings.display == .iconAndTime ? minutes ?? -1 : 0)"
        guard key != lastStatusKey else { return }
        lastStatusKey = key

        button.image = settings.display == .percentOnly ? nil : StatusIconRenderer.image(percent: s.percent, state: e.state, low: low)
        let text: String
        switch settings.display {
        case .iconAndPercent:
            text = "\(s.percent)%"
        case .percentOnly:
            text = e.state == .charging ? "⚡\(s.percent)%" : "\(s.percent)%"
        case .iconOnly:
            text = ""
        case .iconAndTime:
            switch e.state {
            case .discharging: text = Format.clock(e.headlineToEmpty) ?? "\(s.percent)%"
            case .charging: text = Format.clock(e.headlineToFull) ?? "\(s.percent)%"
            case .pluggedIdle, .full, .limitReached: text = "\(s.percent)%"
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
        refresh()
        // 面板每次打開才建立、關掉就釋放，關著時不會有任何 SwiftUI 畫面在背景更新
        let hosting = NSHostingController(rootView: RootView(store: store, settings: settings, ui: ui))
        hosting.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .transient
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
        menu.addItem(withTitle: "結束電池監控", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        scheduleRefresh(every: Self.openInterval)
        processTimer?.invalidate()
        processTimer = repeating(every: Self.processInterval) { delegate in
            guard delegate.ui.page == .main, delegate.ui.tab == .processes else { return }
            Task { await delegate.store.refreshProcesses() }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        store.panelVisible = false
        store.setHardwareSampling(active: false)
        processTimer?.invalidate()
        processTimer = nil
        scheduleRefresh(every: Self.idleInterval)
        ui.page = .main
        ui.isVisible = false
        // 等這次 delegate 回呼結束再釋放
        DispatchQueue.main.async { [weak self] in
            self?.popover?.contentViewController = nil
            self?.popover = nil
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
        defaults.set(path, forKey: LoginItem.registeredPathKey)
        try? LoginItem.setEnabled(true)
    }
}
