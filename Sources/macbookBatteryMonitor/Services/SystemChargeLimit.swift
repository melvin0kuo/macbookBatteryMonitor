import Foundation
import Observation
import notify

/// 主面板的充電上限滑桿：讀取與調整 macOS 系統設定「電池 → 充電」裡的充電上限（兩邊是同一個設定）。
/// 不需要管理者權限；不支援的 Mac 不顯示滑桿
@MainActor
@Observable
final class SystemChargeLimit {
    enum Status: Equatable {
        case idle
        case applying
        case failed(String)
    }

    /// 讀到系統的上限之後才為 true（不支援的 Mac 一直是 false）
    private(set) var supported = false
    /// 系統目前設定的上限，100 表示不限制
    private(set) var limit = 100
    /// false 表示有設定上限但系統目前沒有套用
    private(set) var enabled = true
    private(set) var options = ChargeLimitLogic.defaultOptions
    private(set) var status: Status = .idle
    /// 拖動中的位置；放開滑桿（或停下 0.6 秒）才寫入系統
    private(set) var draft: Int?
    /// 上限改變（在這裡或系統設定調整）後讓 App 立即重新整理
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private let service = PowerUIChargeLimit()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var notifyToken: Int32 = 0
    @ObservationIgnored private var editing = false
    @ObservationIgnored private var commitTask: Task<Void, Never>?
    @ObservationIgnored private var automatedWriteTail: Task<Void, Never>?

    /// 滑桿與數字顯示的值
    var shown: Int { draft ?? limit }

    /// App 啟動時呼叫：讀一次，並在系統設定改了上限時重新讀取（系統設定的電池頁也是聽這個通知）
    func start() {
        guard !started else { return }
        started = true
        notify_register_dispatch("com.apple.powerui.mclstatuschanged", &notifyToken, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// 面板打開時重新讀取，順便清掉上次的錯誤訊息
    func panelOpened() {
        if case .failed = status { status = .idle }
        refresh()
    }

    func refresh() {
        guard status != .applying else { return }
        Task {
            if let reading = await service.read() { apply(reading) }
        }
    }

    func drag(to value: Int) {
        if case .failed = status { status = .idle }
        guard draft != value else { return }
        draft = value
        commitTask?.cancel()
        commitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    func setEditing(_ editing: Bool) {
        self.editing = editing
        if !editing { commit() }
    }

    /// 智慧充電排程使用的確認式寫入；只有系統回讀到目標值才回傳成功。
    func apply(_ target: Int) async -> Bool {
        guard supported, options.contains(target) else { return false }
        let previous = automatedWriteTail
        let operation = Task { @MainActor [weak self] () -> Bool in
            if let previous { await previous.value }
            guard let self else { return false }
            // 滑桿可能剛好正在寫入；等它完成後再套用排程的最新目標，避免取消／還原被吃掉。
            for _ in 0..<100 where self.status == .applying {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard self.status != .applying else { return false }
            return await self.performAutomatedWrite(target)
        }
        automatedWriteTail = Task { @MainActor in _ = await operation.value }
        return await operation.value
    }

    private func performAutomatedWrite(_ target: Int) async -> Bool {
        guard supported, options.contains(target) else { return false }
        if target == limit { return true }
        status = .applying
        let outcome = await service.set(target)
        switch outcome {
        case .applied(let reading):
            apply(reading)
            status = .idle
            if draft != nil { commit() }
            return reading.limit == target
        case .rejected(let code, let after):
            if let after { apply(after) }
            status = .failed("macOS 沒有套用新的充電上限\(code.map { "（錯誤 \($0)）" } ?? "")，請改在系統設定中調整。")
            return false
        }
    }

    /// 開發用截圖：不讀系統，直接用示範值
    func loadPreview(limit: Int) {
        supported = true
        self.limit = limit
    }

    private func commit() {
        guard !editing, status != .applying, let target = draft else { return }
        commitTask?.cancel()
        commitTask = nil
        guard target != limit else {
            draft = nil
            return
        }
        status = .applying
        Task {
            let outcome = await service.set(target)
            finish(outcome, target: target)
        }
    }

    private func finish(_ outcome: PowerUIChargeLimit.SetOutcome, target: Int) {
        status = .idle
        if draft == target { draft = nil }
        switch outcome {
        case .applied(let reading):
            apply(reading)
        case .rejected(let code, let after):
            if let after { apply(after) }
            draft = nil
            status = .failed("macOS 沒有套用新的充電上限\(code.map { "（錯誤 \($0)）" } ?? "")，請改在系統設定中調整。")
        }
        // 寫入期間又拖到別的位置
        if draft != nil { commit() }
    }

    private func apply(_ reading: PowerUIChargeLimit.Reading) {
        let changed = !supported || limit != reading.limit || enabled != reading.enabled
        supported = true
        limit = reading.limit
        enabled = reading.enabled
        options = reading.options
        ChargeLimitReader.updateFromSystem(limit: reading.limit, enabled: reading.enabled)
        if changed { onChange?() }
    }
}
