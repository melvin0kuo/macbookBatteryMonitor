import AppKit
import SwiftUI

/// `BatteryMonitor --snapshot <資料夾>`：在螢幕外把面板各分頁和選單列圖示畫成 PNG，開發時檢查版面用
@MainActor
enum SnapshotCommand {
    static func run(directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = BatteryStore()
        let ui = PanelState()
        ui.isVisible = true
        store.panelVisible = true
        store.refresh()
        store.refreshHealth()
        store.resolveUnpluggedDateIfNeeded()
        store.backfillHistory()
        wait(3)

        let pages: [(String, () -> Void)] = [
            ("details", { ui.page = .main; ui.tab = .details }),
            ("history", { ui.page = .main; ui.tab = .history }),
            ("processes", { ui.page = .main; ui.tab = .processes }),
            ("settings", { ui.page = .settings }),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for (name, configure) in pages {
                configure()
                let view = RootView(store: store, settings: .shared, ui: ui)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, appearance == .aqua ? .light : .dark)
                render(view, appearance: appearance, settle: name == "processes" ? 3 : 0.5,
                       to: dir.appendingPathComponent("panel-\(name)-\(suffix).png"))
            }
            renderStatusIcons(appearance: appearance, to: dir.appendingPathComponent("icons-\(suffix).png"))
        }
        print("已輸出到 \(dir.path)")
    }

    private static func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance.Name, settle: TimeInterval, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(x: -5000, y: 0, width: 380, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.setFrameSize(hosting.fittingSize)
        window.setContentSize(hosting.fittingSize)
        window.orderFrontRegardless()
        wait(settle)
        hosting.setFrameSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        save(view: hosting, to: url)
        window.orderOut(nil)
    }

    private static func renderStatusIcons(appearance: NSAppearance.Name, to url: URL) {
        let cases: [(Int, PowerState, Bool)] = [(82, .discharging, false), (15, .discharging, true), (55, .charging, false), (80, .pluggedIdle, false), (95, .limitReached, false), (100, .full, false)]
        let stack = NSStackView(views: cases.map { pct, state, low in
            let button = NSButton(title: "\(pct)%", image: StatusIconRenderer.image(percent: pct, state: state, low: low), target: nil, action: nil)
            button.isBordered = false
            button.imagePosition = .imageTrailing
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
            return button
        })
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        stack.wantsLayer = true
        stack.appearance = NSAppearance(named: appearance)
        stack.layer?.backgroundColor = (appearance == .aqua ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.12, alpha: 1)).cgColor
        let window = NSWindow(contentRect: NSRect(x: -5000, y: 0, width: 500, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = stack
        stack.setFrameSize(stack.fittingSize)
        window.orderFrontRegardless()
        wait(0.3)
        save(view: stack, to: url)
        window.orderOut(nil)
    }

    private static func save(view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
