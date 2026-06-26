# easy_clipboard 專案慣例

## 跨裝置備忘錄(Memo Sync)
- 獨立「備忘錄」分頁,與剪貼簿功能在同一視窗以底部 `NavigationBar` 切換(`lib/features/root_page.dart`,`home:` 由 main 指向 `RootPage`)。
- 資料層 `lib/memos/memo_store.dart`:`Memo`(id / text / todos / updatedAt / deleted)、`MemoTodo`、`MemoStore extends ChangeNotifier`。持久化為 appSupport 下的 `memos.json`(沿用 identity / last_target 的「檔案存 appSupport」pattern,不引資料庫)。
- 同步為**雙向合併**(非一次性傳送):Last-Write-Wins 比 `updatedAt`(epoch ms),刪除用 `deleted=true` 墓碑保留避免復活。
- 協定:HTTP `POST /memos/sync`(`lan_transport.dart`),body 為發起方完整清單 JSON,接收端 `mergeJson` 後回傳自己的完整清單,一次往返雙方收斂。transport 介面新增 `syncMemos` 與 `start(...onMemoSync)`。
- 觸發點(`AppController.syncMemosWithAll`,`_syncing` 去抖):discovery onChanged、桌面 15 秒 timer、回前景、本地編輯(`MemoStore.onLocalChange`)。`mergeJson` 內**不可**再呼叫 `onLocalChange`,否則兩台無限互推。
- iPhone 不需特殊處理,任兩台同網即合併,iPhone 隨身帶著自然成為 macOS↔Windows 橋樑。
- `Memo` 另有 `colorValue`(ARGB,null=預設黃 `0xFFFFF8C4`)與 `sortKey`(排序鍵)兩欄,皆進 JSON 隨 LWW 同步。色票常數在 `memos_page.dart` 的 `kMemoColors`。
- **排序看 `sortKey`(升冪),不是 `updatedAt`**:`visibleMemos` 先比 sortKey、相等再比 updatedAt 降冪(舊資料 sortKey 皆 0,維持新到舊)。`add()` 取最小 sortKey-1 置頂;拖曳由 `reorder(orderedIds)` 重指派並 touch。因此 `toggleTodo` 雖 touch updatedAt,**不會**改變列表順序。
- 列表用 `ReorderableListView.builder` 拖曳排序;待辦只有 checkbox 用 `InkWell` 可點(整列不可點),待辦列尾端有緊湊複製鈕(貼齊右側內距)。
- 待辦文字若為網址(`memos_page.dart` 的 `_isUrl`:以 `http(s)://` 開頭且 `Uri.hasAuthority`),改用 `Text.rich`+`TapGestureRecognizer` 顯示為藍字(`Colors.blue.shade700`)加同色底線,點擊以 `_openUrl`(`launchUrl` 外部瀏覽器)開啟。
- 拖曳:`buildDefaultDragHandles: false` 關掉桌面預設的橫槓把手,每列包 `ReorderableDelayedDragStartListener` 改整列長按拖曳(桌面/手機一致);`proxyDecorator` 用透明 `Material`+圓角,浮起時只留卡片陰影不出現白邊。
- 刪除:仿 Line,自製 `_SwipeRevealDelete`(非 `Dismissible`)。整列向左滑只露出固定寬度(76px)紅色刪除鈕(滑超過一半自動吸附),**點紅色區才**跳 confirm,取消則收回。紅色鈕與卡片同 `vertical margin(6)`/圓角(12)貼齊,且未滑動(`_dx==0`)時不繪製,避免卡片右側圓角透出紅色。水平拖曳與長按拖曳排序、卡片 `InkWell` 點擊編輯三者並存。
- 編輯器刪待辦:編輯對話框內每列的 `×` 鈕走 `_removeTodo`(async),先跳 `_confirmRemoveTodo` 二次確認(顯示該待辦文字),按「刪除」才移除,與整則備忘錄刪除一致。
- 收合:卡片右上角(原刪除鈕位置)為收合/展開鈕,僅有待辦時顯示;收合只隱藏待辦、保留標題。收合狀態存 `_MemosPageState._collapsed`(只存本機記憶體,**不持久化、不同步**)。標題列(文字+收合鈕)與待辦列分開,待辦列全寬使複製鈕貼齊右側。
- 分頁切換記憶:`root_page.dart` 把 index 寫入 appSupport 的 `last_tab` 檔(沿用 last_target pattern),各裝置分開記,啟動還原。
- iOS 分享**全為網址**時,`runShareFlow`(`home_page.dart`)先跳「加入備忘錄／傳到裝置」對話框;選備忘錄則 `_addUrlsToMemo` 跳 memo picker(選現有或 `c.memos.add()` 新建),把 URL 以 `MemoTodo.create` 加為待辦。

## macOS 建置
- 編譯 macOS release 版後，**一律**把產出的 `.app` 複製一份到使用者的下載資料夾，方便取用：
  ```bash
  flutter build macos --release
  rm -rf ~/Downloads/easy_clipboard.app
  cp -R build/macos/Build/Products/Release/easy_clipboard.app ~/Downloads/easy_clipboard.app
  ```
- `flutter` 不在預設 PATH，需先 `export PATH="$PATH:$HOME/development/flutter/bin"`。
- iOS 部署目標因 `gal` 套件需求為 **11.0**；macOS 部署目標因開機自啟動用 `SMAppService` 已提高到 **13.0**（`macos/Podfile` 與 `project.pbxproj` 的 `MACOSX_DEPLOYMENT_TARGET`）。

## iOS 系統分享選單(Share Extension)
- 目標:在其他 App 的分享選單顯示 easy_clipboard,接收圖片 / 文字 / 網址後自動送到上次使用的裝置(離線跳裝置選單)。
- 相關套件:`receive_sharing_intent: 1.8.1`(主 App 端讀取)、`url_launcher`(接收端開網址)。
- `Share Extension` target 為**自包含原生 Swift**,**不可** `import receive_sharing_intent` 或 Flutter(擴充無 Flutter engine,會找不到 `Flutter/Flutter.h`)。`ShareViewController.swift` 自行把內容寫進 App Group,資料契約(`SharedMediaFile` 欄位、`ShareKey` / `ShareMessageKey`、URL scheme `ShareMedia-<bundleId>:share`)必須與 receive_sharing_intent 1.8.1 完全一致。
- 主 App 與擴充共用 App Group `group.com.philio.easyClipboard`(雙方 entitlements 都要有);主 App `Info.plist` 需有 `CFBundleURLTypes` 含 `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`。
- Dart 端:`lib/core/share_handler.dart` 監聽傳入內容 → `runShareFlow`(`home_page.dart`)送出;`models.dart` 的 `SharedPayload` / `PayloadKind.url`。
- 擴充 `MinimumOSVersion` 為 13.0(主 App iOS 部署目標仍 11.0)。
- Runner target 的 build phases 順序:**Embed Foundation Extensions 必須在 Thin Binary、[CP] Embed Pods Frameworks 之前**,否則會出現 "Cycle inside Runner" 建置循環。
- Xcode 26.5 專案格式 objectVersion=70,舊版 xcodeproj gem 會 pod install 失敗;需手動在 `xcodeproj/constants.rb` 補 `70 => 'Xcode 16.0'`。

## Windows 系統匣(Minimize to Tray)
- 實作在 `lib/core/desktop_tray_service.dart`，僅 Windows 啟用。
- 套件：`tray_manager`（匣圖示與選單）、`window_manager`（視窗攔截與控制）。
- 行為：點 X 或最小化 → 隱藏到系統匣（不結束程式）；左鍵點匣圖示 → 還原視窗；右鍵 → 選單（顯示視窗 / 結束）。
- 匣圖示檔：`assets/icon/tray_icon.ico`（從 `app_icon.png` 轉換）。
- `main.dart` 在 `runApp()` 前呼叫 `DesktopTrayService.ensureInitialized()` 初始化 window_manager。
- 視窗還原時會觸發 `AppController.refreshDiscovery()` 立即重新掃描 mDNS。

## mDNS 探索(桌面端)
- 桌面端（Windows / macOS）每 15 秒自動呼叫 `_discovery.refresh()` 重新掃描，解決 iOS 切背景再回來後桌面端找不到的問題。
- 定時器在 `AppController.init()` 中建立，`dispose()` 時取消。

## 開機自啟動
- 設定入口：首頁 AppBar 齒輪圖示 → 設定對話框的「開機自動啟動」開關（僅 macOS / Windows 顯示）。
- 實作在 `lib/core/autostart.dart`：
  - macOS：透過 `easy_clipboard/autostart` method channel 呼叫原生 `SMAppService.mainApp`（`MainFlutterWindow.swift`），需 macOS 13+。
  - Windows：寫入 `HKCU\...\CurrentVersion\Run` 登錄機碼（`win32_registry` 套件）。
