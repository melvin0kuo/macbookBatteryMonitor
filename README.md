# 電池監控 BatteryMonitor

macOS 選單列電池資訊 App（參考 Stats / AlDente）。只讀取資訊，不會更動任何充電設定。

## 功能
- 選單列：電池圖示 + 百分比（可切換成只有圖示、只有百分比、剩餘時間）；充電中顯示閃電、低電量變紅
- 點開面板：
  - 電量、充放電狀態、剩餘時間／充滿時間
  - 預估用到 0% 與 **用到 10%** 的時間（系統預估 + 依近 3 分鐘耗電推算）
  - 已使用電池多久（這次拔掉電源後）
  - 電力流向：變壓器 → 系統 ⇄ 電池（瓦數）
  - 詳細資訊：電壓、電流、功率、溫度、健康度、循環次數、容量（mAh）、變壓器
  - 電量歷史圖表（1 小時／24 小時／7 天，第一次啟動會用 `pmset` 紀錄回填）
  - 耗電排行（前 5 名 App）
- 顯示 macOS 的充電上限（系統設定 → 電池 → 電池健康度與充電）：已達上限、充到上限的時間、高於上限時降到上限的時間
- 低電量／充電完成通知（門檻可調；到達系統充電上限也會通知）
- 開機自動啟動（從「應用程式」資料夾第一次啟動時自動開啟，可在設定關閉）

## 編譯與安裝
只需要 Command Line Tools，不需要 Xcode。

```bash
./build.sh            # 產生 build/BatteryMonitor.app
./build.sh install    # 安裝到 /Applications 並啟動
```

## 除錯用參數
```bash
/Applications/BatteryMonitor.app/Contents/MacOS/BatteryMonitor --dump            # 目前資料印成 JSON
/Applications/BatteryMonitor.app/Contents/MacOS/BatteryMonitor --snapshot <資料夾> # 面板畫成 PNG
/Applications/BatteryMonitor.app/Contents/MacOS/BatteryMonitor --selftest-panel    # 自動開面板 20 秒再關，測耗電用
```

## 省電設計
實測（M1 MacBook Air）：面板關著時 CPU 約 0.02%，90 秒內只用 0.02 秒 CPU，不會阻止系統睡眠。
- 面板關著：每 30 秒讀一次電池；插拔電源靠系統通知即時更新，不靠輪詢
- 選單列圖示只有在數字或狀態改變時才重畫
- SMC 溫度只在面板開著時讀
- 面板每次打開才建立，關閉就連同視窗整個釋放，背景沒有任何 SwiftUI 畫面
- 耗電排行（`top`）只在面板開著且停在該分頁時，每 5 秒取樣一次
- 介面沒有持續播放的動畫（之前的箭頭脈動動畫會讓 CPU 一直維持在 12% 左右，已移除）
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
