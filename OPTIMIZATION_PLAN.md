# SyncNest 優化計畫

> 2026-07-03 全平台審查（畫面+功能）結果，共 28 項，每項可獨立執行。
> 已勾選（優先）排前面，未勾選排後面。執行時注意**分支**欄：共通功能切到 `main` 做，鬧鐘專屬留在 `feat/alarm-tab`。
> 完成一項就把 `[ ]` 改 `[x]`。

## 進度總覽

### 已勾選（優先執行）

- [x] T01 備忘錄卡片標題文字溢出修正
- [x] T02 編輯器 dialog 響應式寬高
- [x] T03 待辦編輯 Enter/Tab 鍵盤操作
- [x] T04 左滑刪除與長按拖曳的視覺區分
- [x] T05 刪除 Undo（待辦＋整則備忘錄）
- [x] T06 傳送錯誤分類與失敗回饋
- [x] T07 狀態訊息自動清除
- [x] T08 裝置清單在線狀態指示
- [ ] T09 傳檔獨立逾時＋取消按鈕
- [ ] T10 接收檔案完整性校驗
- [ ] T11 MemoWidget 深色背景文字對比
- [x] T12 Live Activity 殭屍活動清理
- [ ] T13 Share Extension 喚醒主 App 失敗回饋
- [x] T14 macOS 縮到系統匣（tray）
- [x] T15 開機自啟時隱藏視窗背景執行
- [ ] T16 Windows 背景到點替代提醒
- [x] T17 memos.json 損毀防護與自動備份
- [x] T18 墓碑過期清理
- [ ] T19 同步失敗使用者可見提示
- [ ] T20 備忘錄手動匯出/匯入 UI
- [ ] T21 LWW 時鐘偏移防護
- [ ] T22 深色模式主題（darkTheme＋硬編碼顏色清理）
- [ ] T23 無障礙 Semantics 標籤
- [ ] T24 字級跟隨系統縮放
- [ ] T25 桌面最小視窗寬度調整

### 未勾選（之後再說）

- [ ] T26 鬧鐘 Firebase 離線視覺回饋
- [x] T27 鬧鐘停止按鈕 await＋防重複點擊
- [ ] T28 倒數時長常用快速按鈕

---

## 一、備忘錄分頁（分支：main）

### T01 備忘錄卡片標題文字溢出修正
- **影響 高／工作量 小**
- 檔案：`lib/features/memos_page.dart:264-271`
- 現況：卡片標題 `Text` 在 `Row > Expanded` 內無 `maxLines`/`overflow` 設定，超長 URL 或無空格字串會撐破卡片排版。
- 做法：加 `maxLines`（例如 2）＋ `overflow: TextOverflow.ellipsis`；待辦列文字同步檢查。

### T02 編輯器 dialog 響應式寬高
- **影響 高／工作量 小**
- 檔案：`lib/features/memos_page.dart:604` 附近（`_MemoEditor`）
- 現況：`SizedBox(width: 360)` 寫死——桌面大螢幕太窄浪費空間；iPad/橫向可能超出邊界；content 無 `maxHeight`，長待辦清單會把 actions 按鈕擠出螢幕外點不到。
- 做法：寬度改 `min(螢幕寬-邊距, 桌面 520~600)`；content 外包 `ConstrainedBox(maxHeight: 螢幕高*0.7)`，內部維持 `SingleChildScrollView`。

### T03 待辦編輯 Enter/Tab 鍵盤操作
- **影響 中／工作量 中**
- 檔案：`lib/features/memos_page.dart:642-648`（待辦輸入框）
- 現況：待辦文字框無 `textInputAction`/`onSubmitted`，桌面只能用滑鼠點「新增待辦」，效率差。同檔 111-119 行群組碼對話框已有 `onSubmitted` 範例。
- 做法：Enter 送出目前列並自動新增下一列聚焦；`FocusTraversalGroup` 讓 Tab 依序跳欄。

### T04 左滑刪除與長按拖曳的視覺區分
- **影響 中／工作量 中**
- 檔案：`lib/features/memos_page.dart`（`_SwipeRevealDelete` 382-458 行、`ReorderableDelayedDragStartListener` 209 行）
- 現況：同一張卡片左滑刪除、長按拖曳並存，無任何視覺/游標提示，新用戶易誤觸。
- 做法：桌面加 `MouseRegion` 游標提示（grab）；拖曳啟動時卡片加陰影/縮放回饋；可考慮左滑露出時同步顯示 icon 動畫強化「這是刪除」。

### T05 刪除 Undo（待辦＋整則備忘錄）
- **影響 高／工作量 中**
- 檔案：`lib/features/memos_page.dart:561-570`（`_removeTodo`）、`lib/memos/memo_store.dart:221-227`（`delete()`）
- 現況：確認刪除後即不可逆；整則刪除已寫墓碑持久化，退出編輯器也救不回。
- 做法：整則刪除改為先刪＋Snackbar「已刪除，復原」5 秒（復原＝清掉墓碑還原內容）；編輯器內刪待辦保留最後一筆可 undo（或同樣 Snackbar）。注意復原要走 `onLocalChange` 觸發同步。

## 二、剪貼簿/傳檔（分支：main）

### T06 傳送錯誤分類與失敗回饋
- **影響 高／工作量 小**
- 檔案：`lib/features/home_page.dart:154, 776, 928-960`、`lib/app_controller.dart:279-320`、`lib/transport/lan_transport.dart:129-240`
- 現況：失敗只顯示原始 exception 字串；`_sendWithProgress` 未 catch；手機端傳剪貼簿（home_page.dart:154）完全無 try-catch，失敗無感。
- 做法：在 transport 層把 `DioException` 分類（連線被拒/逾時/主機不可達/其他），轉成繁中訊息；所有傳送路徑統一 try-catch → SnackBar。

### T07 狀態訊息自動清除
- **影響 中／工作量 小**
- 檔案：`lib/app_controller.dart:413-416`（`_setStatus`）、`lib/features/home_page.dart:427-432`
- 現況：狀態訊息設定後永遠掛在 DevicePage 頂部，不清除，看不出是哪次操作的結果。
- 做法：成功類訊息 N 秒後自動清空（timer 設 `status=null` notify）；或改用 SnackBar 呈現一次性結果、頂部橫幅只留進行中狀態。

### T08 裝置清單在線狀態指示
- **影響 中／工作量 小**
- 檔案：`lib/features/home_page.dart:400-403`（`_DeviceTile`）、`lib/core/models.dart:30`（`isReachable`）
- 現況：`isReachable` 已存在但 UI 完全沒用；host 未解析的裝置照常可點，只能等 timeout 才知道失敗（`lan_transport.dart:253` `_url` 也無 null check）。
- 做法：tile 加狀態小圓點；`!isReachable` 置灰＋禁點或點擊即提示「裝置未解析，請稍候/重新整理」；`_url` 補 null 防護。

### T09 傳檔獨立逾時＋取消按鈕
- **影響 高／工作量 中**
- 檔案：`lib/transport/lan_transport.dart:32-35`（dio 設定）、`lib/features/home_page.dart:928-960`（`_sendWithProgress`）
- 現況：無獨立傳檔逾時（預設 30 分鐘），大檔中途對方離線會卡進度條，使用者不知該等還是關 App。
- 做法：dio 加 `connectTimeout`＋合理 `sendTimeout`；傳送進度 dialog 加「取消」（`CancelToken`）；進度停滯偵測（例如 30 秒無 bytes 進展提示可取消）。

### T10 接收檔案完整性校驗
- **影響 中／工作量 中**
- 檔案：`lib/transport/lan_transport.dart:82-124`（`_receiveFile`/`_receiveClipboard`）、`lib/app_controller.dart:193, 224-230`
- 現況：邊收邊寫完成即標「已接收」，中途斷線的截斷檔照樣入庫；`copyReceivedImage` 開損壞檔無容錯。
- 做法：envelope 帶 `sizeBytes`（必要再加 hash），接收完比對；不符即刪檔並回報失敗；`copyReceivedImage` 加 try-catch。**注意雙端協定要同版本相容（缺欄位就跳過校驗）**。

## 三、iOS 原生（分支：main，T12 除外）

### T11 MemoWidget 深色背景文字對比
- **影響 高／工作量 中**
- 檔案：`ios/MemoWidget/MemoWidgetViews.swift`
- 現況：文字硬編碼 `.black.opacity(...)`，選深色便利貼底色時對比不足難以閱讀。
- 做法：依背景色亮度（luminance）動態選黑/白文字；Flutter 端 `kMemoColors` 若新增深色票更要有此機制。

### T12 Live Activity 殭屍活動清理（分支：feat/alarm-tab）
- **影響 高／工作量 小**
- 檔案：`ios/Runner/LiveActivityManager.swift`
- 現況：`apply()` 啟動新 Activity 前，曾被 `end(immediate:)` 但仍殘留在 `Activity.activities` 清單的舊活動可能擋住新活動建立/造成重複卡片。
- 做法：`apply()` 開頭先遍歷 `Activity<CountdownAttributes>.activities` 把非目標狀態的全部 `end`，再啟動新活動（CLAUDE.md 已載明「改碼要重開新活動才生效」，此處補程式面清理）。

### T13 Share Extension 喚醒主 App 失敗回饋
- **影響 中／工作量 小**
- 檔案：`ios/Share Extension/ShareViewController.swift`（`redirectToHostApp()`）
- 現況：以 URL scheme 喚醒主 App 未檢查 `open()` 成敗，失敗時分享選單無任何提示直接結束。
- 做法：檢查 openURL 結果，失敗時顯示 alert（「無法開啟 SyncNest」）再 `completeRequest`。

## 四、桌面平台（分支：main，T16 除外）

### T14 macOS 縮到系統匣（tray）
- **影響 高／工作量 中**
- 檔案：`lib/core/desktop_tray_service.dart`
- 現況：minimize-to-tray 只有 Windows（`init()` 只檢查 `isWindows`），macOS 關窗即結束前景體驗。
- 做法：放寬到 macOS——狀態列圖示＋左鍵還原/右鍵選單。**注意與 `feat/alarm-tab` 的 `menu_bar_service.dart`（macOS trayManager 倒數顯示）共用 trayManager 單一 tray，兩分支合併時需整合成同一個圖示（倒數文字＋選單並存），不能各建一個**。macOS 圖示需 template image（`assets/icon/tray_icon.ico` 是 Windows 用）。

### T15 開機自啟時隱藏視窗背景執行
- **影響 中／工作量 中**
- 檔案：`lib/core/autostart.dart`、`lib/main.dart`、`windows/runner/`、`macos/Runner/AppDelegate.swift`
- 現況：開機自啟後直接彈出主視窗，與「背景常駐＋快捷鍵呼出」的使用情境不符。
- 做法：Windows 註冊 `Run` 時帶 `--hidden` 參數，`main()` 偵測到就啟動即隱藏到匣；macOS `SMAppService` 同理（偵測登入啟動或加設定開關「自啟時隱藏視窗」）。依賴 T14（macOS 要先有 tray 才能隱藏後找得回來）。

### T16 Windows 背景到點替代提醒（分支：feat/alarm-tab）
- **影響 中／工作量 小**
- 檔案：`lib/alarm/notification_service.dart`、`lib/core/desktop_tray_service.dart`、`lib/alarm/alarm_page.dart`
- 現況：Windows 不支援排程通知（CLAUDE.md 已載明），App 在背景/最小化時到點無任何提示，也沒告知使用者此限制。
- 做法：App 尚在執行但視窗隱藏時，到點用 tray 氣泡/閃爍＋還原視窗＋前景響鈴；鬧鐘頁加一次性說明「Windows 需保持 App 執行才會提醒」。

## 五、同步可靠性（分支：main）

### T17 memos.json 損毀防護與自動備份
- **影響 高／工作量 中**
- 檔案：`lib/memos/memo_store.dart:155`（`load()` 空 catch）、`:281`（`mergeJson` 空 catch）
- 現況：JSON 解析失敗默默載入空清單，磁碟半寫/外部程式弄壞檔案＝資料無聲消失，且無備份。
- 做法：寫檔改「寫 temp → rename」原子寫入；每次成功 load 後留一份 `memos.json.bak`；解析失敗時嘗試 .bak 並跳提示，不再靜默。

### T18 墓碑過期清理
- **影響 高／工作量 中**
- 檔案：`lib/memos/memo_store.dart`
- 現況：`deleted=true` 墓碑永久保留，memos.json 無限長大，每次同步整包傳輸越來越慢。
- 做法：load/merge 時清掉 `deleted && updatedAt 超過 N 天`（例如 30 天）的墓碑。N 要遠大於裝置最長離線間隔，避免復活；寫進 CLAUDE.md 記錄取捨。

### T19 同步失敗使用者可見提示
- **影響 高／工作量 小**
- 檔案：`lib/app_controller.dart:116`（`syncMemosWithAll` 空 catch）、`:138`（群組碼更新後同步）
- 現況：同步逾時/網路錯誤全吞，使用者不知道兩台早就沒在同步；改群組碼後同步失敗也無提示。
- 做法：記錄每裝置最後成功同步時間；連續失敗在備忘錄頁顯示非侵入式提示（icon/badge＋上次成功時間）；改群組碼失敗顯示 SnackBar。

### T20 備忘錄手動匯出/匯入 UI
- **影響 中／工作量 中**
- 檔案：`lib/features/memos_page.dart`（三點選單）、`lib/memos/memo_store.dart`（`exportJson()` 已實作未暴露）
- 現況：只有區網自動同步，全部裝置同時出事＝無救；`exportJson()` 有碼無入口。
- 做法：三點選單加「匯出備忘錄」（file_saver/share_plus 存 JSON）與「匯入」（走 `mergeJson` 合併不覆蓋）。

### T21 LWW 時鐘偏移防護
- **影響 高／工作量 中**
- 檔案：`lib/memos/memo_store.dart`（merge 邏輯）、`lib/transport/lan_transport.dart`（sync 協定）
- 現況：LWW 全靠各機 `DateTime.now()`，某台時鐘快幾分鐘，其他機的新編輯會被舊資料蓋掉。
- 做法：sync 請求/回應帶發送端當下時間戳，接收端算偏移超過門檻（如 2 分鐘）時提示使用者校時；本地 touch 時間戳保證單調遞增（不小於自身已知最大 updatedAt）。不動協定核心、向後相容。

## 六、全域畫面（分支：main）

### T22 深色模式主題
- **影響 高／工作量 中**
- 檔案：`lib/main.dart`（只有 light 主題）、`memos_page.dart`/`home_page.dart`/`alarm_page.dart`（13+ 處硬編碼 `Colors.black87`、`Colors.blue.shade700` 等）
- 現況：無 `darkTheme`，系統深色模式下仍亮色；硬編碼顏色無法自適應。
- 做法：`MaterialApp` 加 `darkTheme`（同 seed）＋`themeMode: system`；硬編碼顏色改 `Theme.of(context).colorScheme` 對應色。便利貼底色（`kMemoColors`）在深色下的前景對比一併處理（與 T11 邏輯一致）。alarm_page 的部分到 feat/alarm-tab 補。

### T23 無障礙 Semantics 標籤
- **影響 中／工作量 小**
- 檔案：`lib/features/memos_page.dart:301-313`（待辦 Checkbox）、`:689-707`（色票 GestureDetector）
- 現況：Checkbox、色票無 Semantics，螢幕閱讀器讀不出用途。
- 做法：Checkbox 加 semanticLabel（「標記完成/取消標記」）；色票 GestureDetector 包 `Semantics(label: '選擇顏色 X', button: true)`。

### T24 字級跟隨系統縮放
- **影響 中／工作量 中**
- 檔案：`memos_page.dart`、`home_page.dart`、`alarm_page.dart`（12+ 處硬編碼 fontSize）
- 現況：硬編碼 fontSize 不隨系統文字縮放，放大字體的使用者看不清。
- 做法：改用 `Theme.of(context).textTheme` 對應樣式；必須固定尺寸處（倒數大字 72）確認 `textScaler` 下不破版即可。

### T25 桌面最小視窗寬度調整
- **影響 中／工作量 小**
- 檔案：`lib/core/window_bounds_service.dart`（最小 360×480）
- 現況：360px 寬時備忘錄卡片收合鈕、待辦 Checkbox/複製鈕擠壓重疊。
- 做法：桌面最小寬提到 ~480px；或維持 360 但把擠壓列改響應式（優先前者，工作量小）。

## 七、未勾選項目（之後再說，分支：feat/alarm-tab）

### T26 鬧鐘 Firebase 離線視覺回饋
- **影響 高／工作量 中**
- 檔案：`lib/alarm/alarm_page.dart:49-53`（listen 無 onError）、`lib/alarm/timer_repository.dart:39-45`
- 現況：Firestore 斷線無 error 處理，UI 凍在舊狀態無提示。
- 做法：`listen` 加 `onError` 追蹤連線狀態，AppBar 顯示離線 icon，恢復時自動重訂。

### T27 鬧鐘停止按鈕 await＋防重複點擊
- **影響 中／工作量 小**
- 檔案：`lib/alarm/alarm_page.dart:447-451`
- 現況：停止鈕未 `await`（同檔 61/112/127/252 行都有 await，此處為遺漏），寫入失敗無感、可重複點擊。
- 做法：改 async ＋ await，執行中禁用按鈕顯示 loading。

### T28 倒數時長常用快速按鈕
- **影響 低／工作量 小**
- 檔案：`lib/alarm/duration_picker.dart`
- 現況：只能逐欄調時分秒。
- 做法：picker 上方加 5/10/15/30 分鐘快速 chip。

---

## 備註（審查中另發現、未列入選單的低優先項）

- macOS 設定頁因 `HotkeyService.supported=false` 直接隱藏「呼出視窗快捷鍵」，無任何說明；若做了 T14/T15 可順手在 macOS 顯示「僅 Windows 支援」或乾脆補 macOS 全域快捷鍵。
