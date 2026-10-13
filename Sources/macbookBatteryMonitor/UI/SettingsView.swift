import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let ui: PanelState
    let adminCPU: AdminCPUSampler
    let updater: Updater
    let chargeLimit: SystemChargeLimit
    let chargingWake: ChargingWakeScheduler

    private var limitText: String {
        if chargeLimit.supported { return chargeLimit.limit >= 100 ? "不限制（100%）" : "\(chargeLimit.limit)%" }
        return ChargeLimitReader.lastKnown().map { "\($0.limit)%" } ?? "未設定"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Text("設定").font(.headline)
                HStack {
                    Button {
                        ui.page = .main
                    } label: {
                        Label("返回", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("智慧充電", systemImage: "clock.badge.checkmark")
                    Picker("旅程外觀", selection: binding(\.chargingVisualStyle)) {
                        ForEach(ChargingVisualStyle.allCases) { Text($0.title).tag($0) }
                    }
                    SwitchRow("允許精準排程喚醒", isOn: binding(\.preciseChargingScheduling))
                    Text("開啟一次並授權後會保持啟用。App 只安排固定的充電喚醒事件；關閉後會取消事件，且沒有其他管理員功能使用時移除服務。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(chargingWake.status).font(.caption).foregroundStyle(.secondary)
                    Button("設定充電完成時間…") { ui.page = .chargingPlan }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("選單列", systemImage: "menubar.rectangle")
                    Picker("顯示方式", selection: binding(\.display)) {
                        ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                    }
                    Button("選擇面板顯示的項目…") { ui.page = .displayItems }
                        .help("電力流向細項（螢幕背光、晶片、CPU／GPU／ANE）與詳細資訊欄位")
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("App 圖示", systemImage: "app.badge")
                    HStack(spacing: 14) {
                        ForEach(AppIconColor.allCases) { color in
                            Button {
                                settings.appIconColor = color
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(LinearGradient(colors: color.swatch, startPoint: .top, endPoint: .bottom))
                                        .frame(width: 40, height: 40)
                                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(settings.appIconColor == color ? Color.accentColor : Color.primary.opacity(0.15),
                                                          lineWidth: settings.appIconColor == color ? 2.5 : 1))
                                    Text(color.title)
                                        .font(.caption)
                                        .foregroundStyle(settings.appIconColor == color ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("App 圖示：\(color.title)")
                        }
                    }
                    Text(settings.appIconError ?? "應用程式資料夾、Finder、Launchpad 裡的圖示；通知與登入項目仍顯示內建的薄荷綠。")
                        .font(.caption)
                        .foregroundStyle(settings.appIconError == nil ? Color.secondary : Color.orange)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("更新頻率與省電", systemImage: "leaf")
                    Picker("更新頻率", selection: binding(\.updateInterval)) {
                        ForEach(AppSettings.updateIntervals, id: \.self) { Text(AppSettings.updateText(seconds: $0)).tag($0) }
                    }
                    SwitchRow("省電模式", isOn: binding(\.powerSaving))
                    Text(settings.powerSaving && settings.updateInterval < 2
                         ? "省電模式：電力流向改用靜態圖示、不播放動畫，更新頻率至少每 2 秒（目前\(settings.updateText)）。"
                         : "省電模式：電力流向改用靜態圖示、不播放動畫，更新頻率至少每 2 秒。更新越慢越省電。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if AppEdition.current.hasSystemMonitors {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        CardTitle("系統監控", systemImage: "gauge.with.dots.needle.33percent")
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                SwitchRow("CPU／GPU", isOn: binding(\.monitorCPU))
                                SwitchRow("記憶體", isOn: binding(\.monitorMemory))
                            }
                            GridRow {
                                SwitchRow("磁碟", isOn: binding(\.monitorDisk))
                                SwitchRow("網路", isOn: binding(\.monitorNetwork))
                            }
                        }
                        Text("開啟的模組在選單列各有一個圖示，\(settings.updateText)。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("CPU 功耗", systemImage: "cpu")
                    SwitchRow("管理員 CPU 取樣", isOn: binding(\.adminCPUSampling))
                    Text("選用功能，預設關閉。開啟時需輸入管理員密碼，安裝只讀取 CPU 功耗的系統服務；只在主面板開啟時取樣（\(settings.updateText)），面板關閉後不通訊，服務閒置會自行結束。關閉此選項會移除服務。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(adminCPU.status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("通知", systemImage: "bell")
                    SwitchRow("低電量提醒", isOn: binding(\.lowAlertEnabled))
                    Stepper("電量低於 \(settings.lowThreshold)% 時提醒", value: binding(\.lowThreshold), in: 5...50, step: 5)
                        .disabled(!settings.lowAlertEnabled)
                    Divider()
                    SwitchRow("充電完成提醒", isOn: binding(\.fullAlertEnabled))
                    Stepper("充到 \(settings.fullThreshold)% 時提醒", value: binding(\.fullThreshold), in: 50...100, step: 5)
                        .disabled(!settings.fullAlertEnabled)
                    Button("傳送測試通知") {
                        Notifier.shared.sendTest()
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("充電上限", systemImage: "checkmark.shield")
                    HStack {
                        Text("系統充電上限")
                        Spacer()
                        Text(limitText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if chargeLimit.supported {
                        Text("可在主面板電量下方的滑桿調整（80–100%），與系統設定「電池」裡的充電上限是同一個設定，改哪一邊都會同步。實際停在上限由 macOS 控制，這個 App 不會另外控制充電。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        if ChargeLimitReader.lastKnown()?.active == false {
                            Text("用電池時 macOS 不會套用上限，數值是上次接電時讀到的。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("這台 Mac 或系統版本無法從 App 調整充電上限，這裡只讀取並顯示。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("在系統設定中修改") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle("啟動", systemImage: "power")
                    SwitchRow("開機時自動啟動", isOn: Binding(
                        get: { ui.loginStatus != .disabled },
                        set: { setLoginItem($0) }
                    ))
                    if ui.loginStatus == .requiresApproval {
                        Text("需要在系統設定的「登入項目」中允許。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("打開「登入項目」設定") {
                            LoginItem.openSystemSettings()
                        }
                    }
                    if !LoginItem.isInApplications {
                        Text("建議先把 App 放到「應用程式」資料夾，再開啟這個選項。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let loginError = ui.loginError {
                        Text(loginError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            UpdateCard(updater: updater, settings: settings)

            HStack {
                Text("\(AppEdition.current.appName) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("結束\(AppEdition.current.appName)") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .onAppear {
            ui.loginStatus = LoginItem.status
        }
    }

    private struct SwitchRow: View {
        let title: String
        let isOn: Binding<Bool>

        init(_ title: String, isOn: Binding<Bool>) {
            self.title = title
            self.isOn = isOn
        }

        var body: some View {
            HStack {
                Text(title)
                Spacer()
                Toggle(title, isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func setLoginItem(_ enabled: Bool) {
        UserDefaults.standard.set(!enabled, forKey: LoginItem.disabledByUserKey)
        do {
            try LoginItem.setEnabled(enabled)
            ui.loginError = nil
        } catch {
            ui.loginError = "設定失敗：\(error.localizedDescription)"
        }
        ui.loginStatus = LoginItem.status
    }
}
