# SyncNest 專案慣例

## 分支工作流程(重要)
- **共通功能(備忘錄 memo、剪貼簿等)只在 `main` 改;鬧鐘專屬功能(alarm)只在 `feat/alarm-tab` 改。**
- `feat/alarm-tab` 拿 `main` 更新:`git checkout feat/alarm-tab && git merge main`。

## 設定檔持久化 pattern(共通)
- identity、last_target、last_tab、`hotkey.json`、`storage_dir` 等小設定一律以純文字或 JSON 存 **appSupport**(不寫資料庫/登錄),各裝置分開記、啟動還原。下面各功能只列檔名,不再重述此 pattern。

## 跨裝置備忘錄(Memo Sync)
- 「備忘錄」分頁與剪貼簿同視窗,底部 `NavigationBar` 切換(`root_page.dart`,`home:` 指向 `RootPage`);切換 index 存 appSupport `last_tab`。
- 資料層 `lib/memos/memo_store.dart`:`Memo`(id/text/todos/updatedAt/deleted/colorValue/sortKey)、`MemoTodo`、`MemoStore extends ChangeNotifier`,持久化 `memos.json`(無資料庫)。
- **桌面(macOS/Windows)存 `Downloads/SyncNest/`**(見「自訂儲存資料夾」),不放 appSupport——appSupport 是沙盒 Container 重裝會清;Downloads 靠 entitlement `files.downloads.read-write` 重裝保留。iOS 等仍存 appSupport(重裝必清,靠區網同步補回)。`load()` 開頭 `_migrateFromAppSupport()` 一次性搬舊檔。
- 同步為**雙向合併**:Last-Write-Wins 比 `updatedAt`,刪除留 `deleted=true` 墓碑避免復活;`colorValue`(null=預設黃)、`sortKey` 也隨 LWW 同步。協定 HTTP `POST /memos/sync`(`lan_transport.dart`):送完整清單 JSON,接收端 `mergeJson` 後回傳自己清單,一次往返收斂。
- 觸發點(`AppController.syncMemosWithAll`,`_syncing` 去抖):discovery onChanged、桌面 15 秒 timer、回前景、本地編輯(`MemoStore.onLocalChange`)。**`mergeJson` 內不可再呼叫 `onLocalChange`**,否則兩台無限互推。iPhone 同網即合併,天然當 macOS↔Windows 橋樑。
- **排序看 `sortKey`(升冪)不是 updatedAt**(`visibleMemos` 先比 sortKey、相等再 updatedAt 降冪;舊資料 sortKey=0 維持新到舊):`add()` 取最小 sortKey-1 置頂、`reorder(orderedIds)` 重指派並 touch,故 `toggleTodo` 雖 touch updatedAt 不改順序。
- UI(`memos_page.dart`):`ReorderableListView` 整列長按拖曳排序(關預設把手、透明 proxyDecorator);自製 `_SwipeRevealDelete`(仿 Line 左滑露 76px 紅鈕、點紅區才 confirm,與長按拖曳、點擊編輯並存);卡片右上收合鈕(僅本機記憶體,**不持久化/不同步**);待辦網址(`_isUrl`)顯示藍字底線可點 `_openUrl`;編輯器刪待辦走 `_removeTodo` 二次確認。色票常數 `kMemoColors`。
- iOS 分享**全為網址**時 `runShareFlow`(`home_page.dart`)先問「加入備忘錄／傳到裝置」,選備忘錄則 `_addUrlsToMemo` 跳 picker(選現有或新建)把 URL 加為待辦。
- **同步群組碼**(區網多使用者分辨):空碼=維持現狀(與所有同網裝置互通),要隔離才在自己各裝置填同一組碼。`sync_group` 持久化撐過重裝(與鬧鐘 `alarm_group` 同機制,`identity.dart`):**iOS 存 Keychain**(`flutter_secure_storage`)、**桌面(macOS/Windows)存 `StorageLocation.baseDir()` 檔**(預設 Downloads/SyncNest,靠 entitlement 重裝保留)、其餘存 appSupport;空字串清除回未設定。mDNS TXT 多帶 `group` 欄位、discovery 解析寫進 `DeviceInfo.groupCode`。**過濾放同步層**:`syncMemosWithAll` 只同步 `d.groupCode==本機` 的裝置(裝置清單仍完整,剪貼簿/傳檔手動選不受影響);server 端 `memos/sync` 二次比對 header `x-group-code`,不符回 403。改碼走 `AppController.updateGroupCode`(存檔→`copyWith`→`transport.updateLocal`→重新 `register` 帶新 TXT→重同步)。入口在**備忘錄頁 AppBar 右上三點選單**「同步群組碼」(`memos_page.dart`,與「重設並重新同步」並列,屬備忘錄功能不放齒輪設定)。**僅備忘錄自動同步受群組碼影響,鬧鐘的 `alarm_group` 為另一分支獨立機制。**
- **重設並重新同步**(救援被污染的本機資料):入口在**備忘錄頁 AppBar 右上三點選單**(`memos_page.dart`,全平台一致)「重設備忘錄並重新同步」→ `resetMemosAndResync()`:`clearLocal()` 整包清空(連墓碑)再 `syncMemosWithAll()` 純拉回。空清單在 LWW 不參與(不像刪除會留新時間戳墓碑反向覆蓋),故 100% 以他機為準;`clearLocal()` 刻意不呼叫 `onLocalChange`。前提:來源裝置開著且同網。

## 鬧鐘分頁(跨裝置倒數計時,整合自 cross_platform_alarm)
- 第三分頁「鬧鐘」是**跨裝置共用的單一倒數計時器**(非多組),程式 `lib/alarm/`,`root_page.dart` NavigationBar index 2。
- **同步走 Firebase Firestore**(與本專案區網 P2P 無關):`TimerRepository`(`timer_repository.dart`)讀寫,`TimerState`(`timer_state.dart`)只存絕對 `deadline`+長度本地算剩餘,LWW 靠 transaction。接 Firebase 專案 `cross-platform-alarm-app`,bundleId `com.philio.easyClipboard`。設定檔 `firebase_options.dart`、`ios|macos/Runner/GoogleService-Info.plist`(皆 git 追蹤)。
- **群組代碼分組 `timers/{code}`**(`AlarmGroup`,`alarm_group.dart`,單例+ChangeNotifier):同代碼共用同一筆倒數,別人各自一組。`TimerRepository.setTimerId(code)`;`AlarmPage` 監聽 `AlarmGroup`,代碼變更即取消舊訂閱、清舊群組通知/響鈴/Live Activity、重訂。入口 AppBar `Icons.group_work_outlined`(檢視/複製/輸入代碼)。`main()` 在 `StorageLocation.load()` 後(桌面要先有 baseDir)、建 `AlarmServices` 前 `await AlarmGroup.instance.load()`。
- **代碼持久化撐過重裝**:桌面存檔案 `alarm_group` 於 `baseDir()`(Downloads);iOS 用 `flutter_secure_storage` 存 Keychain(重裝保留)。首次無碼產生 uuid 前 8 hex。**因此預設不再與獨立版「跨平台鬧鐘」App 共用 `shared`**;要連動手動把代碼設成 `shared`。
- 服務 holder `AlarmServices`(`alarm_services.dart`)於 `Firebase.initializeApp()` 後建,`Provider.value` 注入;`AlarmPage` `initState` `context.read`(不在 dispose 釋放這些 App 生命週期單例)。
- 通知 `notification_service.dart`(`flutter_local_notifications`,channel `timer_done` id 1001):iOS/macOS/Android 支援 `zonedSchedule`,**Windows 不支援排程**(只前景 `showNow`)。前景響鈴 `audioplayers` 播 `assets/sounds/alarm.wav`(`alarm_sound_service.dart`)。
- macOS 選單列倒數 `menu_bar_service.dart`(`trayManager`,僅 macOS,與 Windows tray 不衝突)。**未搬**鬧鐘原本的 `desktop_tray_service.dart`/`launch_at_startup`(會與既有 window_manager/autostart 重複)。
- **iOS Live Activity(動態島)**:`live_activity_service.dart` 經 MethodChannel `easy_clipboard/live_activity` 接原生(`ios/Runner/LiveActivityChannel.swift`、`LiveActivityManager.swift`,在 `AppDelegate.didInitializeImplicitFlutterEngine` 註冊)。Widget Extension `ios/CountdownWidget/`(target `CountdownWidgetExtension`,bundleId `com.philio.easyClipboard.CountdownWidget`,部署 16.1)。`Info.plist` `NSSupportsLiveActivities=true`。Widget 用 xcodeproj gem 加進 Runner.xcodeproj(objectVersion 54),`.appex` 掛既有 Embed Foundation Extensions phase(在 Thin Binary/Embed Pods 前避免 Cycle)。
- **`CountdownAttributes.swift` 必須同屬 Runner 與 CountdownWidgetExtension 兩 target**(Live Activity 靠檔案 membership 共用 Attributes,非 import):pbxproj 同一 fileRef 要有兩個 PBXBuildFile 各掛一 target 的 Sources phase;只掛 Widget 會讓 Runner 報 `Cannot find 'CountdownAttributes' in scope`。
- **Firebase 版本鎖(別亂升,否則啟動黑/白屏)**:`firebase_core` 釘 `4.10.0`(原生 Pigeon `FirebaseOptions` 14 欄);但 transitive `firebase_core_web` 拉 `firebase_core_platform_interface ^7.1.0`(Dart 解碼 15 欄)→ `initializeApp` 報 `RangeError`、到不了 `runApp`。修法:`pubspec.yaml` `dependency_overrides: firebase_core_platform_interface: 7.0.1`。**別為消 override 升 `firebase_core` 4.11.0**(會連動拉高原生 SDK,與 `cloud_firestore 6.5.0` 部署目標衝突);要升得整組一起動。
- pod install 在系統 Ruby 2.6 撞 `Encoding::CompatibilityError`,需 `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`。不支援 Android(`firebase_options.dart` 的 Android 條目用不到)。

## macOS 建置
- build release 後**一律**複製 `.app` 到下載資料夾:
  ```bash
  flutter build macos --release
  rm -rf ~/Downloads/syncnest.app
  cp -R build/macos/Build/Products/Release/syncnest.app ~/Downloads/syncnest.app
  ```
- `flutter` 不在 PATH,先 `export PATH="$PATH:$HOME/development/flutter/bin"`。
- 部署目標:iOS **15.0**(Firebase 要求,Runner 與 Share Extension 繼承;`ios/Podfile` 同)、macOS **13.0**(開機自啟用 `SMAppService`)。
- **絕不可平行跑 macOS 與 iOS 建置**:兩者 Xcode build DB(`build/.../XCBuildData/build.db`)同位置同時建會互鎖(`database is locked ... two concurrent builds`)其一 BUILD FAILED;更糟的是 build 失敗後**舊產物仍在**,接著 `cp`/`flutter install` 會誤裝舊版。一律**序列化**做完一個再下一個;撞鎖先 `rm -rf build/macos/Build/Intermediates.noindex/XCBuildData` 再重編。

## iOS 系統分享選單(Share Extension)
- 在他 App 分享選單顯示 SyncNest,收圖片/文字/網址後送上次裝置。套件 `receive_sharing_intent: 1.8.1`、`url_launcher`。
- Share Extension target 為**自包含原生 Swift**,**不可** import receive_sharing_intent 或 Flutter(無 engine,會找不到 `Flutter/Flutter.h`)。`ShareViewController.swift` 自行寫進 App Group,資料契約(`SharedMediaFile` 欄位、`ShareKey`/`ShareMessageKey`、URL scheme `ShareMedia-<bundleId>:share`)須與 1.8.1 完全一致。
- 主 App 與擴充共用 App Group `group.com.philio.syncNest`(雙方 entitlements);主 App `Info.plist` 需 `CFBundleURLTypes` 含 `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`。擴充 `MinimumOSVersion` 13.0。
- Dart 端 `lib/core/share_handler.dart` → `runShareFlow`;`models.dart` 的 `SharedPayload`/`PayloadKind.url`。
- **Runner build phases:Embed Foundation Extensions 必須在 Thin Binary、[CP] Embed Pods Frameworks 之前**,否則 "Cycle inside Runner"。
- Xcode 26.5 專案 objectVersion=70,舊 xcodeproj gem 需手動在 `xcodeproj/constants.rb` 補 `70 => 'Xcode 16.0'`。

## Windows 系統匣(Minimize to Tray)
- `lib/core/desktop_tray_service.dart`,僅 Windows。套件 `tray_manager` + `window_manager`。
- 點 X / 最小化 → 隱藏到匣(不結束);左鍵還原、右鍵選單(顯示/結束)。匣圖示 `assets/icon/tray_icon.ico`。`main.dart` 在 `runApp()` 前 `ensureInitialized()`。還原時觸發 `AppController.refreshDiscovery()` 重掃 mDNS。

## Windows 全域快捷鍵(切換視窗顯示/隱藏)
- `lib/core/hotkey_service.dart`(單例),僅 Windows。套件 `hotkey_manager`(Win32 `RegisterHotKey`,`HotKeyScope.system`,不需前景)。預設 `Ctrl+Alt+C`,存 appSupport `hotkey.json`。
- 觸發呼 `DesktopTrayService.toggleWindow()`(前景則 hide、否則 showWindow,一呼一隱)。`main.dart` Windows 區塊 `start()` 內先 `unregisterAll()` 清 hot reload 殘留。設定對話框用 `HotKeyRecorder` 錄製(需至少一修飾鍵),`HotkeyService.update` 即時生效。

## mDNS 探索(桌面端)
- 桌面端每 15 秒 `_discovery.refresh()` 重掃,解決 iOS 切背景再回來後找不到的問題。定時器在 `AppController.init()` 建、`dispose()` 取消。

## 自訂儲存資料夾(桌面 macOS / Windows)
- `lib/core/storage_location.dart`(單例 ChangeNotifier)統一桌面資料(`memos.json` + 接收圖片)落地;`memo_store._dataDir()` 與 `lan_transport._saveDir()` 都呼叫 `baseDir()`。
- 預設 `Downloads/SyncNest`,可在設定改選(存 appSupport `storage_dir`);`main()` 在 `MemoStore().load()` **之前** `await StorageLocation.instance.load()`。**直接用所選資料夾**(不再多包一層),`setPath` 複製舊檔到新夾(不覆蓋同名),傳 `null` 還原預設。`baseDir()` 自帶 try/catch,路徑失效自動退回預設。
- **macOS 沙盒**:`user-selected.read-write` 僅本次執行有效,故用 **security-scoped bookmark** 持久化——`MainFlutterWindow.swift` 的 `SyncNest/storage_bookmark` channel(save/resolve/clear),存 UserDefaults;`load()` 時 resolve 失敗則退回預設。Windows 無沙盒不需。
- 設定入口 `_SettingsDialog` 「儲存資料夾」ListTile。**`file_picker` 11.0.2 用 `FilePicker.getDirectoryPath(...)` 靜態方法,非 `FilePicker.platform`**。

## 開機自啟動
- 入口:AppBar 齒輪 → 設定「開機自動啟動」(僅 macOS/Windows)。`lib/core/autostart.dart`:macOS 走 `SyncNest/autostart` channel 呼 `SMAppService.mainApp`(需 13+);Windows 寫 `HKCU\...\CurrentVersion\Run`(`win32_registry`)。

## 視窗位置/長寬記憶(桌面 macOS / Windows)
- `lib/core/window_bounds_service.dart`(單例):啟動還原上次關閉前的視窗 frame、執行中去抖(500ms)存檔,存 appSupport `window_bounds.json`。
- 初始化掛在 `DesktopTrayService.ensureInitialized()`(已放寬為 `isDesktop`=macOS+Windows,原本僅 Windows):`waitUntilReadyToShow` callback 內 **show 之前** `applySavedBounds()`、show 之後 `startTracking()`,避免閃預設尺寸。
- 還原時用 `screen_retriever`(原 window_manager 的 transitive 相依,已升為直接相依)`_clampToVisible` 夾限:以視窗中心所在螢幕的**完整螢幕區域**(`d.size`,非 visibleSize——否則底部永遠貼不到螢幕邊緣,被工作列/Dock 卡住)為界,並放寬 `_overflowMargin`(100px)允許略微超出邊界;尺寸下限 360×480,防止換螢幕/解析度後開到畫面外;取不到螢幕資訊只保尺寸下限。最小化/隱藏時的 bounds 不可靠,存檔時跳過。
