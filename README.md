# 電池監控 macbookBatteryMonitor

macOS 選單列電池資訊 App 。只讀取資訊，不會更動任何充電設定。

## 功能
- 選單列：電池圖示 + 百分比（可切換成只有圖示、只有百分比、剩餘時間）；充電中顯示閃電、低電量變紅
- 點開面板：
  - 電量、充放電狀態、剩餘時間／充滿時間
  - 預估用到 0% 與 **用到 10%** 的時間（系統預估 + 依近 3 分鐘耗電推算）
  - 已使用電池多久（這次拔掉電源後）
  - 電力流向：灰色帶狀圖，充電分流至系統與電池，放電由電池供應系統（瓦數）
  - 系統細項：分流顯示螢幕背光、晶片運算、其他（估算）；點晶片展開 CPU／GPU／ANE
  - 詳細資訊：電壓、電流、功率、溫度、健康度、循環次數、容量（mAh）、變壓器
  - 電量歷史圖表（1 小時／24 小時／7 天，第一次啟動會用 `pmset` 紀錄回填）
  - 耗電排行（前 5 名 App）
- 顯示 macOS 的充電上限（系統設定 → 電池 → 電池健康度與充電）：已達上限、充到上限的時間、高於上限時降到上限的時間
- 低電量／充電完成通知（門檻可調；到達系統充電上限也會通知）
- 開機自動啟動（從「應用程式」資料夾第一次啟動時自動開啟，可在設定關閉）

## 編譯與安裝
只需要 Command Line Tools，不需要 Xcode。

```bash
./build.sh            # 產生 build/macbookBatteryMonitor.app
./build.sh install    # 安裝到 /Applications 並啟動
```

## 除錯用參數
```bash
/Applications/macbookBatteryMonitor.app/Contents/MacOS/macbookBatteryMonitor --dump-hardware     # 每秒輸出硬體功耗，共五筆 JSON
/Applications/macbookBatteryMonitor.app/Contents/MacOS/macbookBatteryMonitor --selftest-hardware # 展開晶片、切換設定並確認取樣停止
/Applications/macbookBatteryMonitor.app/Contents/MacOS/macbookBatteryMonitor --dump            # 目前資料印成 JSON
/Applications/macbookBatteryMonitor.app/Contents/MacOS/macbookBatteryMonitor --snapshot <資料夾> # 面板畫成 PNG
/Applications/macbookBatteryMonitor.app/Contents/MacOS/macbookBatteryMonitor --selftest-panel    # 自動開面板 20 秒再關，測耗電用
```

## 硬體功耗
面板主頁每 1 秒取樣一次；實際硬體與系統能量模型可能以較慢的頻率更新。CPU／GPU／ANE 是能量差除以實際時間窗的系統模型估算；系統總功耗優先讀取 SMC PSTR，背光讀取 SMC 感測器；兩者以相鄰讀值平均近似取樣窗。晶片合計只涵蓋取得的 CPU、GPU、ANE，不代表完整 SoC 功耗；不含外接螢幕。

缺通道顯示「—」，首次取樣建立基準，CPU 能量計數未前進時顯示 0 W（代表取樣能量差為零）。使用 SMC PSTR 時，將總功耗扣除背光與已取得的晶片功耗，顯示非負差值估算；缺晶片細項時改標示「未分類（估算）」，其中包含缺失項目，不能視為純粹的其他硬體耗電。SMC 與能量模型的實際更新窗可能不同。PSTR 不可用時退回 SystemLoad；此來源沒有公開量測時間戳，故不計算殘差。

讀取不需管理員權限。IOReport 為系統私有介面，可用性依晶片與 macOS 版本而異；目前只在 M2 Pro 驗證 PSTR 總功耗、背光與 GPU 讀值，CPU 通道在目前系統未持續更新，依能量差顯示 0 W。ANE 閒置時可為 0 W。

## 測試
```bash
Scripts/test-power.sh  # Command Line Tools 可執行的換算、生命週期與動畫測試
```

## 省電設計
實測（M1 MacBook Air）：面板關著時 CPU 約 0.02%，90 秒內只用 0.02 秒 CPU，不會阻止系統睡眠。
- 面板主頁：每 1 秒更新電池／功耗，關閉面板、進入設定或睡眠時停止硬體細項取樣
- 面板關著：每 30 秒讀一次電池；插拔電源靠系統通知即時更新，不靠輪詢
- 選單列圖示只有在數字或狀態改變時才重畫
- SMC 溫度只在面板開著時讀
- 面板每次打開才建立，關閉就連同視窗整個釋放，背景沒有任何 SwiftUI 畫面
- 耗電排行（`top`）只在面板開著且停在該分頁時，每 5 秒取樣一次
- 電力流向使用 Core Animation 灰色流帶動畫（由系統合成，無逐幀 SwiftUI 更新），帶寬依相對功率調整，僅在面板開啟且對應電路有供電時播放；支援 macOS「減少動態效果」，面板關閉即釋放動畫
- 歷史紀錄每 15 分鐘寫一次檔，睡眠前和結束時也會存
- 健康度（`system_profiler`）每 6 小時查一次

## 資料來源
| 項目 | 來源 |
|---|---|
| 電量、電壓、電流、容量、循環次數 | IORegistry `AppleSmartBattery` |
| 系統預估時間、充電狀態 | IOKit Power Sources |
| 健康度（最大容量）、電池狀況 | `system_profiler SPPowerDataType` |
| 溫度 | SMC（唯讀，`TB0T`～`TB2T`） |
| 耗電排行 | `top -o power` |
| 歷史回填、拔電時間 | `pmset -g log` |
| 充電上限 | `/Library/Preferences/com.apple.powerd.charging.plist`（唯讀） |

歷史資料存在 `~/Library/Application Support/BatteryMonitor/history.json`（保留 7 天）。

## 注意
只裝 Command Line Tools 時沒有 SwiftUI 的 macro 外掛，所以程式裡不用 `@State`，介面狀態集中在 `PanelState`。

插拔電源時，總覽優先使用 SMC PPBR（電池功率）、PDTR（外部輸入）與 PSTR（系統功耗），避免重插後 Registry 電流和輸入功率仍停留在舊狀態。SMC 可用時，電流由電池功率及電壓換算並以 ≈ 標示；原始電流保留於診斷輸出。插拔通知後會在 1、3、6 秒短暫重讀，之後回到正常更新間隔。
