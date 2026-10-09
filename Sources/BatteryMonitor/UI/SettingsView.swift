import SwiftUI

struct SettingsView: View {
    let settings: AppSettings
    let ui: PanelState

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
                    CardTitle("選單列", systemImage: "menubar.rectangle")
                    Picker("顯示方式", selection: binding(\.display)) {
                        ForEach(MenuBarDisplay.allCases) { Text($0.title).tag($0) }
                    }
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
                        Text(ChargeLimitReader.current().map { "\($0.limit)%" } ?? "未設定")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Text("充電上限由 macOS 控制，這個 App 只讀取並顯示。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            HStack {
                Text("電池監控 1.0")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("結束電池監控") {
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
        do {
            try LoginItem.setEnabled(enabled)
            ui.loginError = nil
        } catch {
            ui.loginError = "設定失敗：\(error.localizedDescription)"
        }
        ui.loginStatus = LoginItem.status
    }
}
