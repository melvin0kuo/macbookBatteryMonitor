# 分層硬體功耗實作計畫

**目標：**加入螢幕背光、晶片運算及其他功耗分流，晶片可展開 CPU／GPU／ANE；面板開啟時每 1 秒更新。

**架構：**唯讀 SMC 與 IOReport 資料讀取器提供獨立功耗快照，由 BatteryStore 管理生命週期。分流數據模型處理缺值與估算，介面只顯示有效數據；動畫由獨立圖層維持播放相位。

**技術：**Swift、SwiftUI、AppKit、Core Animation、IOKit、動態載入 IOReport。

**設計：**[hardware-power-flow.md](hardware-power-flow.md)

## 共通限制
- macOS 14 以上；僅使用 Command Line Tools，不新增第三方套件。
- 不要求管理員權限，不安裝 helper，不使用 sudo。
- 主頁顯示時每 1 秒取樣；背景電池總覽維持 30 秒，耗電排行維持 5 秒。
- 光流每 3.6 秒一輪、相隔 1.2 秒，不隨數字更新重新起跑。
- 僅使用者作為提交作者，不加入生成標記、共同作者或其他產品名稱。

## 審查重點
- 不同晶片缺通道時顯示缺值，不顯示假的零或完整 SoC 功率。
- 能量回捲、睡眠與重新開啟後，先重建基準再產生瓦數。
- 更新跨越面板關閉或頁面切換時，舊結果不能回寫。
- 總功耗與細項不同步或差值為負時，不顯示偽造的閉合分流。
- 380 pt 面板與小尺寸螢幕上，展開後仍可閱讀及返回總覽。

## 1. 能量換算與硬體快照
**檔案：**新增 Model/ComponentPower.swift、Data/IOReportReader.swift、Data/HardwarePowerReader.swift，修改 Data/SMC.swift；路徑皆位於 Sources/macbookBatteryMonitor/。新增 Tests/macbookBatteryMonitorTests/ComponentPowerTests.swift 及獨立測試執行器。

**介面：**ComponentPowerSample 包含 uptime、背光及可選 CPU/GPU/ANE 瓦數、資料狀態。IOReportReader.sample() 提供累積焦耳值；HardwarePowerReader.sample() 計算時間窗平均瓦數，reset() 清除基準。

- [ ] 先加入能量換算測試：1,000 mJ／1 秒為 1 W；1,000,000 µJ／1 秒為 1 W；未知單位、非有限值與重複通道不產生瓦數。
- [ ] 加入首樣本、時間差小於等於零、能量回捲、缺 CPU/GPU/ANE 通道的測試；第一次只建立基準。
- [ ] 執行 Scripts/test-power.sh，確認測試因尚無實作失敗。
- [ ] 實作換算與唯讀讀取器；動態驗證 IOReport 符號，保持原生可變 CFDictionary，避免 Swift 橋接後破壞 API 要求。
- [ ] 本機取得至少三個連續樣本，檢查背光與晶片能量單位、時間窗、功耗量級及總功耗範圍。
- [ ] 執行 Scripts/test-power.sh，確認全部通過後提交此步。

## 2. 取樣生命週期與分流計算
**檔案：**修改 Model/BatteryStore.swift、AppDelegate.swift；新增 Model/PowerBreakdown.swift 與 Tests/macbookBatteryMonitorTests/PowerBreakdownTests.swift。

**介面：**PowerBreakdown.make(systemWatts: Double?, components: ComponentPowerSample, now: TimeInterval) 提供背光、晶片合計、其他殘差及有效性。BatteryStore.setHardwareSampling(active: Bool) 控制訂閱，提供 componentPower 與 breakdown。

- [ ] 先加入測試：總功耗 12 W、背光 3 W、CPU 2 W、GPU 1 W、ANE 0 W，晶片合計 3 W、其他 6 W；缺細項、負殘差及超過 3 秒未更新的樣本不能生成有效殘差。
- [ ] 加入可測的採樣狀態／世代控制測試，確認關閉、重開、切換設定頁、睡眠後，舊樣本被丟棄。
- [ ] 執行 Scripts/test-power.sh，確認新測試失敗。
- [ ] 實作狀態控制與殘差計算；讀取在背景序列佇列執行，主執行緒只發佈有效結果；不重疊取樣。
- [ ] 將 AppDelegate.openInterval 改為 1 秒；關閉／設定頁／睡眠停止硬體採樣，重開／喚醒建立新基準。
- [ ] 執行 Scripts/test-power.sh，確認全部通過後提交此步。

## 3. 分層介面與持續動畫
**檔案：**修改 UI/PowerFlowView.swift、UI/PanelView.swift、UI/PanelState.swift；新增 UI/ComponentPowerFlowView.swift，將持續動畫圖層集中於 UI/PowerFlowLayers.swift。

**介面：**PanelState 增加 powerFlowLevel（overview／components／chip）；ComponentPowerFlowView(breakdown: PowerBreakdown, ui: PanelState) 顯示目前層級。

- [ ] 保留電源總覽，提供系統端的展開按鈕；第一層顯示背光、晶片運算、其他，晶片按鈕切換 CPU／GPU／ANE 層。
- [ ] 節點顯示名稱、瓦數與狀態；缺值為「—」、首樣本為「取樣中」；其他註明估算，晶片註明合計範圍與資料完整性。
- [ ] 使用按鈕、返回操作與 VoiceOver 標籤；保持 380 pt 面板寬度，檢查展開後高度。
- [ ] 分離路徑、數字與動畫圖層；一般數字更新只修改字串與路徑，動畫 beginTime 固定；拓撲改變才新增／移除流帶。
- [ ] 零值與缺值不播放光流；減少動態效果時無動畫；離開主頁或關閉面板即釋放。
- [ ] 以連續一秒更新確認流光不重啟，檢查鍵盤、VoiceOver、展開／返回與深淺色後提交此步。

## 4. 驗證與本機安裝
**檔案：**修改 Snapshot.swift、Dump.swift、README.md。

- [ ] 快照涵蓋總覽、硬體分流、晶片展開、缺值與資料不同步；充電／放電／混合供電各使用固定資料並輸出深淺色。
- [ ] Dump 輸出硬體功耗來源、有效性與時間窗，供核對讀值。
- [ ] 執行 Scripts/test-power.sh、./build.sh、git diff --check 與 codesign --verify --deep --strict。
- [ ] 檢視快照，實測展開與收合；量測面板開／關 CPU，確認面板關閉後無硬體取樣。
- [ ] README 更新每 1 秒取樣、硬體來源、估算與相容性說明；僅報告實際驗證過的機型。
- [ ] 執行 ./build.sh install 更新本機 App，確認已啟動；新功能不直接加入既有 PR #1。

## 實機驗證紀錄

已完成分層介面、每秒取樣、持續動畫及生命週期控制。Command Line Tools 未提供 XCTest，因此使用獨立 Swift 測試執行器；14 項測試通過。深淺色與完整面板快照已檢視，設定頁及關閉面板後停止採樣、返回主頁恢復均通過實測。Apple M2 Pro 的 CPU 能量計數器未更新，故保留缺值；系統總功耗沒有可核對的時間窗，故不生成其他殘差。CPU 使用率量測期間有互動干擾，未作背景效能比較結論。
