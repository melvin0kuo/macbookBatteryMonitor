import SwiftUI

struct ChargingPlanView: View {
    let store: BatteryStore
    let settings: AppSettings
    let ui: PanelState

    private let weekdays = [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text("智慧充電").font(.headline)
                HStack {
                    Button { ui.page = .main } label: { Label("返回", systemImage: "chevron.left") }
                        .buttonStyle(.borderless)
                    Spacer()
                }
            }

            if let plan = store.chargingPlan.plan {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            CardTitle("目前旅程", systemImage: phaseSymbol)
                            Spacer()
                            Text(store.chargingPlan.decision?.phase.title ?? "準備中")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(phaseColor)
                        }
                        Text(plan.deadline.formatted(date: .abbreviated, time: .shortened))
                            .font(.title2.weight(.semibold)).monospacedDigit()
                        Text("目標 \(plan.targetPercent)% · 保養上限 \(plan.holdPercent)%")
                            .font(.callout).foregroundStyle(.secondary)
                        if let decision = store.chargingPlan.decision, let start = decision.startAt {
                            Label("預計 \(start.formatted(date: .omitted, time: .shortened)) 開始充電",
                                  systemImage: "bolt.badge.clock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = store.chargingPlan.writeError {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }
                        Button("取消並還原充電上限", role: .destructive) { store.cancelChargingPlan() }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle("快速完成", systemImage: "timer")
                    HStack(spacing: 8) {
                        quickButton("1 小時", hours: 1)
                        quickButton("2 小時", hours: 2)
                        quickButton("3 小時", hours: 3)
                    }
                    Divider()
                    DatePicker("自訂完成時間", selection: ui.binding(\.customChargingDeadline),
                               displayedComponents: [.date, .hourAndMinute])
                    Button("使用自訂時間") { saveCustom() }
                    Text("Mac 會先維持保養上限，到了需要開始充電的時間再交給 macOS 充到目標。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle("每週排程", systemImage: "calendar")
                    HStack(spacing: 6) {
                        ForEach(weekdays, id: \.0) { day, label in
                            Button { toggle(day) } label: {
                                Text(label)
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 25, height: 22)
                                    .background(ui.chargingWeekdays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.13),
                                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .foregroundStyle(ui.chargingWeekdays.contains(day) ? Color.white : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("星期\(label)")
                            .accessibilityValue(ui.chargingWeekdays.contains(day) ? "已選取" : "未選取")
                        }
                    }
                    DatePicker("完成時間", selection: ui.binding(\.chargingTime), displayedComponents: .hourAndMinute)
                    Button("儲存每週排程") { saveRecurring() }
                        .buttonStyle(.borderedProminent)
                        .disabled(ui.chargingWeekdays.isEmpty)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle("充電策略", systemImage: "slider.horizontal.3")
                    Picker("保養上限", selection: binding(\.chargingHoldPercent)) {
                        ForEach(validOptions.filter { $0 <= settings.chargingTargetPercent }, id: \.self) {
                            Text("\($0)%").tag($0)
                        }
                    }
                    Picker("完成目標", selection: binding(\.chargingTargetPercent)) {
                        ForEach(validOptions, id: \.self) { Text("\($0)%").tag($0) }
                    }
                    Picker("睡眠時", selection: binding(\.chargingSleepStrategy)) {
                        Text("優先準時完成").tag(ChargingSleepStrategy.readinessFirst)
                        Text("精準喚醒").tag(ChargingSleepStrategy.preciseWake)
                    }
                    if settings.chargingSleepStrategy == .preciseWake {
                        Toggle("允許排程喚醒", isOn: binding(\.preciseChargingScheduling))
                            .toggleStyle(.switch)
                        Text(store.chargingWake.status)
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("睡眠前若仍在等待，會先解除保養上限，讓 macOS 在睡眠期間自行完成。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .onAppear {
            settings.chargingTargetPercent = normalizedTarget
            settings.chargingHoldPercent = normalizedHold
        }
    }

    private func quickButton(_ title: String, hours: Double) -> some View {
        Button(title) {
            store.chargingPlan.startQuick(hours: hours, target: normalizedTarget,
                                          hold: normalizedHold,
                                          restore: store.chargeLimit.limit,
                                          sleepStrategy: settings.chargingSleepStrategy)
            store.syncChargingWake()
            ui.page = .main
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
    }

    private func toggle(_ weekday: Int) {
        if ui.chargingWeekdays.contains(weekday) { ui.chargingWeekdays.remove(weekday) }
        else { ui.chargingWeekdays.insert(weekday) }
    }

    private func saveRecurring() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: ui.chargingTime)
        let minute = (parts.hour ?? 8) * 60 + (parts.minute ?? 0)
        store.chargingPlan.saveRecurring(weekdays: ui.chargingWeekdays, minuteOfDay: minute,
                                         target: normalizedTarget,
                                         hold: normalizedHold,
                                         restore: store.chargeLimit.limit,
                                         sleepStrategy: settings.chargingSleepStrategy)
        store.syncChargingWake()
        ui.page = .main
    }

    private func saveCustom() {
        let hours = max(0.25, ui.customChargingDeadline.timeIntervalSinceNow / 3600)
        store.chargingPlan.startQuick(hours: hours, target: normalizedTarget,
                                      hold: normalizedHold,
                                      restore: store.chargeLimit.limit,
                                      sleepStrategy: settings.chargingSleepStrategy)
        store.syncChargingWake()
        ui.page = .main
    }

    private var phaseSymbol: String {
        switch store.chargingPlan.decision?.phase {
        case .ready: return "checkmark.circle.fill"
        case .late: return "exclamationmark.triangle.fill"
        case .charging, .starting: return "bolt.fill"
        default: return "clock.fill"
        }
    }

    private var validOptions: [Int] {
        store.chargeLimit.supported ? store.chargeLimit.options : ChargeLimitLogic.defaultOptions
    }

    private var normalizedTarget: Int {
        validOptions.min(by: { abs($0 - settings.chargingTargetPercent) < abs($1 - settings.chargingTargetPercent) }) ?? 100
    }

    private var normalizedHold: Int {
        let choices = validOptions.filter { $0 <= normalizedTarget }
        return choices.min(by: { abs($0 - settings.chargingHoldPercent) < abs($1 - settings.chargingHoldPercent) })
            ?? normalizedTarget
    }

    private var phaseColor: Color {
        switch store.chargingPlan.decision?.phase {
        case .ready: return .green
        case .late, .systemPaused: return .orange
        default: return .secondary
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}

private extension ChargingPlanPhase {
    var title: String {
        switch self {
        case .unsupported: return "僅提醒"
        case .unplugged: return "等待電源"
        case .waiting: return "等待開始"
        case .starting: return "準備充電"
        case .charging: return "充電中"
        case .systemPaused: return "系統暫停"
        case .ready: return "已準備好"
        case .late: return "可能延遲"
        }
    }
}
