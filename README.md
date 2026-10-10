# 電池監控 Full — macbookBatteryMonitor

Full 為完整功能版，提供動畫電力流向、可展開的硬體功耗細項、每秒主面板更新與耗電排行。
macOS 選單列的電池資訊 App。
選單列直接顯示電量，點開就能看到剩餘時間、健康度、充放電功率、充電上限、歷史曲線與耗電排行。

- **只讀取資訊**：不會更動任何充電設定，不需要管理員權限
- **省電**：面板關閉時 CPU 約 0%，不會阻止系統睡眠
- **不需要 Xcode**：只要 Command Line Tools 就能編譯

## 下載與版本選擇

到 [Releases](https://github.com/sgeric910601/macbookBatteryMonitor/releases) 下載編好的 App。v1.2.0 是完整版，可以看到各硬體的耗電；想要較精簡、較省電可以選舊版本：

| 版本 | 電力流向 | 面板開著時 CPU | 面板關閉時 CPU | 適合 |
|---|---|---|---|---|
| [v1.2.0](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.2.0)（最新，完整版） | 動畫流向圖，可展開螢幕背光、晶片運算與 CPU／GPU／ANE，每秒更新 | 尚未實測 | 尚未實測（關閉時停止硬體取樣） | 想看各硬體的耗電 |
| [v1.1.0](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.1.0) | 動畫 Sankey 流向圖，依功率分流 | 約 3% | 約 0% | 想要較生動的介面 |
| [v1.0.0](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.0.0) | 靜態圖示與箭頭 | 約 1% | 約 0% | 想要最精簡、最省電 |

> v1.1.0、v1.0.0 的 CPU 數據為 M1 MacBook Air 實測，面板開著時停在「耗電排行」分頁（含每 5 秒的 `top` 取樣）。

亦可下載 [Full 1.2.0 的獨立建置](https://github.com/melvin0kuo/macbookBatteryMonitor/releases/tag/v1.2.0-full)。App 名稱為 `macbookBatteryMonitor.app`，沿用既有設定與電量歷史。

## 安裝

需求：macOS 14 以上、Apple Silicon 的 MacBook（附的 App 為 arm64 版本）。

1. 從 Releases 下載 `macbookBatteryMonitor-<版本>-macOS-arm64.zip`，解壓縮
2. 把 `macbookBatteryMonitor.app` 拖到「應用程式」資料夾
3. 第一次打開時 macOS 會擋下來（App 沒有 Apple 開發者簽章）。任選一種方式放行：
   - 到「系統設定 → 隱私權與安全性」，在下方找到這個 App，按「強制打開」
   - 或在終端機執行：
     ```bash
     xattr -dr com.apple.quarantine /Applications/macbookBatteryMonitor.app
     ```
4. 第一次啟動會詢問通知權限，並自動加入開機自啟動（可在設定關閉）

要換版本時，結束 App 後用另一個版本的 `.app` 覆蓋即可，設定與歷史資料會保留。

## 功能

**選單列**
- 電池圖示 + 百分比（可切換成只有圖示、只有百分比、剩餘時間）
- 充電中顯示閃電、接電未充電顯示插頭、低電量變紅

**面板**
- 電量、充放電狀態、剩餘時間／充滿時間（有充電上限時顯示充到上限的時間）
- 預估用到 0% 與**用到 10%** 的時間：系統預估 + 依近 3 分鐘平均耗電推算
- 已使用電池多久（這次拔掉電源後）
- 電力流向：變壓器、系統、電池之間的瓦數
- 系統細項：分流顯示螢幕背光、晶片運算、其他（估算）；點晶片展開 CPU／GPU／ANE
- 詳細資訊：電壓、電流、電池功率、系統耗電、系統預估、溫度、健康度、循環次數、容量（mAh）、變壓器、充電上限
- 電量歷史圖表（1 小時／24 小時／7 天，第一次啟動會用 `pmset` 紀錄回填過去幾天）
- 耗電排行：前 5 名 App，同一個 App 的子程序會合併

**其他**
- 顯示 macOS 的充電上限（系統設定 → 電池 → 電池健康度與充電）：已達上限、充到上限的時間、高於上限時降到上限的時間
- 低電量／充電完成通知（門檻可調；到達系統充電上限也會通知）
- 開機自動啟動

## 使用方式

- **左鍵**點選單列圖示：打開面板
- **右鍵**：打開面板、設定、結束
- **設定**：選單列顯示方式、通知門檻、開機自啟動；充電上限由 macOS 控制，App 只讀取顯示，可從設定頁跳到系統設定修改

## 從原始碼編譯

只需要 Command Line Tools（`xcode-select --install`），不需要 Xcode。

```bash
git clone https://github.com/sgeric910601/macbookBatteryMonitor.git
cd macbookBatteryMonitor
git checkout v1.2.0          # 或 v1.1.0、v1.0.0，不指定就是最新的開發版
./build.sh                   # 產生 build/macbookBatteryMonitor.app
./build.sh install           # 安裝到 /Applications 並啟動
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

- 面板主頁每 1 秒更新電池與功耗；關閉面板、進入設定或睡眠時停止硬體細項取樣
- 面板關著時每 30 秒讀一次電池；插拔電源靠系統通知即時更新，不靠輪詢
- 選單列圖示只有在數字或狀態改變時才重畫
- SMC 溫度只在面板開著時讀
- 面板每次打開才建立，關閉就連同視窗整個釋放，背景沒有任何畫面在更新
- 耗電排行（`top`）只在面板開著且停在該分頁時，每 5 秒取樣一次
- v1.1.0 起的流向動畫由 Core Animation 合成（不逐幀更新 SwiftUI），只在面板開著且該線路有供電時播放；支援「減少動態效果」
- 歷史紀錄每 15 分鐘寫一次檔，睡眠前和結束時也會存
- 健康度（`system_profiler`）每 6 小時查一次

## 資料來源

| 項目 | 來源 |
|---|---|
| 電量、電壓、原始電流、容量、循環次數 | IORegistry `AppleSmartBattery` |
| 電池功率、外部輸入、系統功耗、背光 | SMC（唯讀，`PPBR`、`PDTR`、`PSTR`、`PDBR`／`PBwo`） |
| CPU／GPU／ANE 功耗 | IOReport Energy Model 的能量差與實際取樣時間 |
| 系統預估時間、充電狀態 | IOKit Power Sources |
| 健康度（最大容量）、電池狀況 | `system_profiler SPPowerDataType` |
| 溫度 | SMC（唯讀，`TB0T`～`TB2T`） |
| 耗電排行 | `top -o power` |
| 歷史回填、拔電時間 | `pmset -g log` |
| 充電上限 | `/Library/Preferences/com.apple.powerd.charging.plist`（唯讀；macOS 拔電後會清空，App 會記住上次接電時讀到的值） |

## 資料存放位置

- 歷史紀錄：`~/Library/Application Support/BatteryMonitor/history.json`（保留 7 天）
- 設定：`com.kuan.batterymonitor`（UserDefaults）

## 解除安裝

1. 在 App 設定裡關閉「開機時自動啟動」，然後結束 App
2. 刪除 `/Applications/macbookBatteryMonitor.app`
3. （選擇性）清除資料：
   ```bash
   rm -rf ~/Library/Application\ Support/BatteryMonitor
   defaults delete com.kuan.batterymonitor
   ```

## 發布

推送 `v*` tag 後，GitHub Actions 會在 macOS 上測試、編譯、打包，並建立該版本的 Release（說明取自 `.github/release-notes/<tag>.md`）：

```bash
git tag v1.2.0 && git push origin v1.2.0
```

## 開發

除錯用參數：

```bash
APP=/Applications/macbookBatteryMonitor.app/Contents/MacOS/macbookBatteryMonitor
$APP --dump-hardware     # 每秒輸出硬體功耗，共五筆 JSON
$APP --selftest-hardware # 展開晶片、切換設定並確認取樣停止
$APP --dump              # 目前讀到的資料印成 JSON
$APP --snapshot <資料夾>  # 在螢幕外把面板各分頁畫成 PNG
$APP --selftest-panel    # 自動開面板 20 秒再關，量測耗電用
```

只裝 Command Line Tools 時沒有 SwiftUI 的 macro 外掛，所以程式裡不用 `@State`，介面狀態集中在 `PanelState`。

插拔電源時，總覽優先使用 SMC PPBR（電池功率）、PDTR（外部輸入）與 PSTR（系統功耗），避免重插後 Registry 電流和輸入功率仍停留在舊狀態。SMC 可用時，電流由電池功率及電壓換算並以 ≈ 標示；原始電流保留於診斷輸出。插拔通知後會在 1、3、6 秒短暫重讀，之後回到正常更新間隔。
