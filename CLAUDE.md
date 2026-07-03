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
- **墓碑過期清理(T18)**:`MemoStore._gcTombstones()` 在 `load()` 與 `mergeJson()`(changed 時)清掉 `deleted=true` 且 `updatedAt` 超過 `_tombstoneTtlDays`(30 天)的墓碑,避免 memos.json 無限長大、同步整包越傳越慢。**取捨**:30 天遠大於裝置最長離線間隔——只要各裝置 30 天內同步過一次,墓碑早已生效,清掉不會復活;若某裝置離線超過 30 天才回來,其舊資料可能復活,屬刻意接受的罕見代價。GC 不呼 `onLocalChange`,load 縮檔後 `_save()`。
- 觸發點(`AppController.syncMemosWithAll`,`_syncing` 去抖):discovery onChanged、桌面 15 秒 timer、回前景、本地編輯(`MemoStore.onLocalChange`)。**`mergeJson` 內不可再呼叫 `onLocalChange`**,否則兩台無限互推。iPhone 同網即合併,天然當 macOS↔Windows 橋樑。
- **排序看 `sortKey`(升冪)不是 updatedAt**(`visibleMemos` 先比 sortKey、相等再 updatedAt 降冪;舊資料 sortKey=0 維持新到舊):`add()` 取最小 sortKey-1 置頂、`reorder(orderedIds)` 重指派並 touch,故 `toggleTodo` 雖 touch updatedAt 不改順序。
- UI(`memos_page.dart`):`ReorderableListView` 整列長按拖曳排序(關預設把手、proxyDecorator 陰影+1.02 縮放);自製 `_SwipeRevealDelete`(仿 Line 左滑露 76px 紅鈕,與長按拖曳、點擊編輯並存);**刪除備忘錄不再二次確認**——點紅鈕即刪+SnackBar 5 秒「復原」(`MemoStore.restore`:取消墓碑+touch,LWW 贏過已同步的墓碑);桌面(`_isDesktopPlatform`)滑鼠 hover 卡片浮現拖曳把手(`ReorderableDragStartListener`+grab 游標)與刪除鈕(`Visibility maintainSize` 防版面跳動);卡片右上收合鈕(僅本機記憶體,**不持久化/不同步**),收合時標題 `maxLines:1` 截斷;待辦網址(`_isUrl`)顯示藍字底線可點 `_openUrl`。編輯器:寬高隨螢幕自適應(寬上限 560、高上限 60% 螢幕);待辦列 Enter(`onEditingComplete`)跳下一列/最後一列連續新增並自動聚焦,刪除鈕 `ExcludeFocus` 讓 Tab 只在欄位間跳;刪待辦即刪+列內「復原」(5 秒),不再二次確認。色票常數 `kMemoColors`。
- iOS 分享**全為網址**時 `runShareFlow`(`home_page.dart`)先問「加入備忘錄／傳到裝置」,選備忘錄則 `_addUrlsToMemo` 跳 picker(選現有或新建)把 URL 加為待辦。
- **同步群組碼**(區網多使用者分辨):空碼=維持現狀(與所有同網裝置互通),要隔離才在自己各裝置填同一組碼。`sync_group` 持久化撐過重裝(與鬧鐘 `alarm_group` 同機制,`identity.dart`):**iOS 存 Keychain**(`flutter_secure_storage`)、**桌面(macOS/Windows)存 `StorageLocation.baseDir()` 檔**(預設 Downloads/SyncNest,靠 entitlement 重裝保留)、其餘存 appSupport;空字串清除回未設定。mDNS TXT 多帶 `group` 欄位、discovery 解析寫進 `DeviceInfo.groupCode`。**過濾放同步層**:`syncMemosWithAll` 只同步 `d.groupCode==本機` 的裝置(裝置清單仍完整,剪貼簿/傳檔手動選不受影響);server 端 `memos/sync` 二次比對 header `x-group-code`,不符回 403。改碼走 `AppController.updateGroupCode`(存檔→`copyWith`→`transport.updateLocal`→重新 `register` 帶新 TXT→重同步)。入口在**備忘錄頁 AppBar 右上三點選單**「同步群組碼」(`memos_page.dart`,與「重設並重新同步」並列,屬備忘錄功能不放齒輪設定)。**僅備忘錄自動同步受群組碼影響,鬧鐘的 `alarm_group` 為另一分支獨立機制。**
- **重設並重新同步**(救援被污染的本機資料):入口在**備忘錄頁 AppBar 右上三點選單**(`memos_page.dart`,全平台一致)「重設備忘錄並重新同步」→ `resetMemosAndResync()`:`clearLocal()` 整包清空(連墓碑)再 `syncMemosWithAll()` 純拉回。空清單在 LWW 不參與(不像刪除會留新時間戳墓碑反向覆蓋),故 100% 以他機為準;`clearLocal()` 刻意不呼叫 `onLocalChange`。前提:來源裝置開著且同網。
## iOS 主畫面 Widget(MemoWidget)
- **可設定式 widget**:每個 widget 實例各自選要顯示哪一則備忘錄(可放多個各顯示不同),**無釘選機制**。所有尺寸顯示該備忘錄的標題+待辦(小 4 列、中 5 列、大 13 列,超過顯示「+N 項」),背景用便利貼色,無標題列。**與鬧鐘 CountdownWidget(Live Activity,在 feat/alarm-tab)無關**,是獨立的 WidgetKit extension,屬共通功能在 **main** 開發。
- **iOS 17+**:設定用 `AppIntentConfiguration`(需 iOS 17;`Info.plist` MinimumOSVersion 與 target `IPHONEOS_DEPLOYMENT_TARGET` 皆 17.0)。`SelectMemoIntent`(`WidgetConfigurationIntent`,參數 `memo: MemoEntity?`)+ `MemoEntity`/`MemoEntityQuery`(讀 App Group 列出/還原/預設選項)在 `SelectMemoIntent.swift`。需 `AppIntents.framework`。
- **資料流(單向 App→Widget)**:`lib/core/widget_bridge.dart`(`WidgetBridge` 單例,僅 iOS)`attach(MemoStore)` 監聽 store 任何 `notifyListeners`(本地編輯或遠端合併都推),經 MethodChannel `syncnest/widget`(method `update`)送**完整備忘錄清單**。原生 `ios/Runner/WidgetBridgeChannel.swift`(在 `AppDelegate.didInitializeImplicitFlutterEngine` 註冊)寫進 **App Group `group.com.philio.syncNest`** 的 `UserDefaults` key `memo_widget_data`(JSON Data),再 `WidgetCenter.reloadAllTimelines()`。
- **資料契約**:`{ "memos": [Summary...] }`,`Summary = { id, title, color(ARGB int?), todos: [{text, done}] }`。widget 各實例經 `SelectMemoIntent.memo.id` 從清單挑一則;找不到(被刪)顯示「備忘錄已不存在」、未設定顯示「長按編輯選擇」。待辦順序原樣送出,**Widget 端 `orderedTodos` 未勾選優先、已勾選排後(顯示刪除線)**,再依尺寸截斷。
- **Widget target**:`ios/MemoWidget/`(`MemoWidgetBundle`/`MemoWidget`/`MemoWidgetViews`/`MemoWidgetData`/`SelectMemoIntent`.swift + Info.plist),target 名 `MemoWidgetExtension`,bundleId `com.philio.syncNest.MemoWidget`,entitlements `ios/MemoWidgetExtension.entitlements`(同 App Group)。`containerBackground(for:.widget)` 是 iOS 17+ API,用 `widgetBackground` view 修飾包 `if #available`。
- **加 target 用 xcodeproj gem**(objectVersion 70):`.appex` 掛既有 **Embed Foundation Extensions** phase(在 Thin Binary/Embed Pods 前避免 Cycle),Runner 加依賴。**Runner 是傳統 PBXGroup 非同步群組**(只有 Share Extension 是 `PBXFileSystemSynchronizedRootGroup`),故 `WidgetBridgeChannel.swift` 要顯式加進 Runner 的 group + Sources phase;widget 用傳統 group 顯式列 swift 檔。gem 存檔與 pod install 都可能把 objectVersion 降 54,commit 前確認改回 70。
- **依賴修正**:main 的 `identity.dart`(同步群組碼 Keychain)一直 import `flutter_secure_storage` 卻漏在 main `pubspec.yaml` 宣告(只加在 feat/alarm-tab),導致 main 單獨 build iOS 失敗;已補 `flutter_secure_storage: ^9.2.4` 到 main pubspec。

## 鬧鐘分頁(跨裝置倒數計時,整合自 cross_platform_alarm)
- 第三分頁「鬧鐘」是**跨裝置共用的單一倒數計時器**(非多組),程式 `lib/alarm/`,`root_page.dart` NavigationBar index 2。
- **同步走 Firebase Firestore**(與本專案區網 P2P 無關):`TimerRepository`(`timer_repository.dart`)讀寫,`TimerState`(`timer_state.dart`)只存絕對 `deadline`+長度本地算剩餘,LWW 靠 transaction。接 Firebase 專案 `cross-platform-alarm-app`,bundleId `com.philio.easyClipboard`。設定檔 `firebase_options.dart`、`ios|macos/Runner/GoogleService-Info.plist`(皆 git 追蹤)。
- **群組代碼分組 `timers/{code}`**(`AlarmGroup`,`alarm_group.dart`,單例+ChangeNotifier):同代碼共用同一筆倒數,別人各自一組。`TimerRepository.setTimerId(code)`;`AlarmPage` 監聽 `AlarmGroup`,代碼變更即取消舊訂閱、清舊群組通知/響鈴/Live Activity、重訂。入口 AppBar `Icons.group_work_outlined`(檢視/複製/輸入代碼)。`main()` 在 `StorageLocation.load()` 後(桌面要先有 baseDir)、建 `AlarmServices` 前 `await AlarmGroup.instance.load()`。
- **代碼持久化撐過重裝**:桌面存檔案 `alarm_group` 於 `baseDir()`(Downloads);iOS 用 `flutter_secure_storage` 存 Keychain(重裝保留)。首次無碼產生 uuid 前 8 hex。**因此預設不再與獨立版「跨平台鬧鐘」App 共用 `shared`**;要連動手動把代碼設成 `shared`。
- 服務 holder `AlarmServices`(`alarm_services.dart`)於 `Firebase.initializeApp()` 後建,`Provider.value` 注入;`AlarmPage` `initState` `context.read`(不在 dispose 釋放這些 App 生命週期單例)。
- 通知 `notification_service.dart`(`flutter_local_notifications`,channel `timer_done` id 1001):iOS/macOS/Android 支援 `zonedSchedule`,**Windows 不支援排程**(只前景 `showNow`)。前景響鈴 `audioplayers` 播 `assets/sounds/alarm.wav`(`alarm_sound_service.dart`)。
- macOS 選單列倒數 `menu_bar_service.dart`(僅 macOS)。**merge main(T14 macOS tray)後已整合**:macOS statusItem 由共通 `DesktopTrayService` 單一擁有(圖示 `tray_icon_macos.png`、右鍵選單、點擊還原視窗);`MenuBarService` **不再自建圖示/tooltip、也不 destroy**,只 `setTitle` 疊倒數文字(trayManager 單例只有一個 statusItem,兩邊各建會互蓋)。結果:狀態列=SyncNest 圖示+倒數文字+選單並存。冷啟動若倒數 `setTitle` 早於 `DesktopTrayService.init()` 建 statusItem,首秒文字可能漏顯(下一 tick 自癒)。
- **iOS Live Activity(動態島)**:`live_activity_service.dart` 經 MethodChannel `easy_clipboard/live_activity` 接原生(`ios/Runner/LiveActivityChannel.swift`、`LiveActivityManager.swift`,在 `AppDelegate.didInitializeImplicitFlutterEngine` 註冊)。Widget Extension `ios/CountdownWidget/`(target `CountdownWidgetExtension`,bundleId `com.philio.easyClipboard.CountdownWidget`,部署 16.1)。`Info.plist` `NSSupportsLiveActivities=true`。Widget 用 xcodeproj gem 加進 Runner.xcodeproj(objectVersion 54),`.appex` 掛既有 Embed Foundation Extensions phase(在 Thin Binary/Embed Pods 前避免 Cycle)。
- **`CountdownAttributes.swift` 必須同屬 Runner 與 CountdownWidgetExtension 兩 target**(Live Activity 靠檔案 membership 共用 Attributes,非 import):pbxproj 同一 fileRef 要有兩個 PBXBuildFile 各掛一 target 的 Sources phase;只掛 Widget 會讓 Runner 報 `Cannot find 'CountdownAttributes' in scope`。
- **Firebase 版本鎖(別亂升,否則啟動黑/白屏)**:`firebase_core` 釘 `4.10.0`(原生 Pigeon `FirebaseOptions` 14 欄);但 transitive `firebase_core_web` 拉 `firebase_core_platform_interface ^7.1.0`(Dart 解碼 15 欄)→ `initializeApp` 報 `RangeError`、到不了 `runApp`。修法:`pubspec.yaml` `dependency_overrides: firebase_core_platform_interface: 7.0.1`。**別為消 override 升 `firebase_core` 4.11.0**(會連動拉高原生 SDK,與 `cloud_firestore 6.5.0` 部署目標衝突);要升得整組一起動。
- pod install 在系統 Ruby 2.6 撞 `Encoding::CompatibilityError`,需 `export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`。不支援 Android(`firebase_options.dart` 的 Android 條目用不到)。

## 深連結導頁(Deep Link → 分頁,iOS)
- **需求**:Widget 點擊回 App→切**備忘錄**分頁(共通,兩分支都要);推播/動態島點擊回 App→切**鬧鐘**分頁(僅 alarm 功能,只 `feat/alarm-tab` 有鬧鐘分頁)。**共通基礎建設在 main 開發**,alarm 專屬的 `syncnest://alarm` 觸發源與分頁 index 對應在 `feat/alarm-tab`。
- **URL scheme `syncnest://`**:`ios/Runner/Info.plist` 的 `CFBundleURLTypes` 第二組(與 Share Extension 的 `ShareMedia-*` 並列)。host 即路由目標:`memo`、`alarm`。Widget 端 `MemoWidget.swift` 加 `.widgetURL(URL(string:"syncnest://memo"))`。
- **必須關掉 Flutter 內建自動深連結(踩過雷)**:`Info.plist` 設 `FlutterDeepLinkingEnabled=false`。否則 Flutter 會把收到的 URL 當導航 route 推進 `MaterialApp`(`home:` 無對應路由)→ **疊一個一模一樣的畫面上來(可往右滑返回)**。關掉後 URL 只由 DeepLinkChannel→TabRouter 切分頁,不 push。(不影響 Share Extension,那是 plugin application delegate 層,與框架導航旗標無關。)
- **接收改用原生 scene 覆寫 + 自寫 channel(踩遍 app_links 後的定案,已驗成功)**:`app_links` 在本 App 的 implicit-engine + `FlutterSceneDelegate` 架構下**抓不到冷啟動**(`getInitialLink()` 回 null)——因為冷啟動 URL 只在 `scene:willConnectToSession:options:` 的 `connectionOptions.URLContexts`,而 app_links 只實作了執行中的 `application:openURL:`(那條靠 Flutter 的 scene→app fallback 轉成 `application:openURL:` 才收得到,故熱啟動成功、冷啟動失敗)。已移除 app_links。作法:
  - **`ios/Runner/SceneDelegate.swift`**(`class SceneDelegate: FlutterSceneDelegate`)覆寫 UIKit 的 `scene(_:willConnectTo:options:)`(冷啟動,取 `connectionOptions.urlContexts`)與 `scene(_:openURLContexts:)`(執行中),**先呼 `super` 保住 Flutter 設定**再取 URL 餵給 `DeepLinkChannel`。覆寫父類「已實作的協定方法」在 Swift 合法(等同覆寫 FlutterAppDelegate 的 `application(...)`);**別去實作 Flutter 私有的 `FlutterSceneLifeCycleDelegate` 協定**——其 `scene:willConnectToSession:options:` 選擇器與 UIKit `UISceneDelegate` 撞名,Swift 會報「renamed / different optionality」編譯錯。
  - **`ios/Runner/DeepLinkChannel.swift`**(純 channel/儲存,`AppDelegate.didInitializeImplicitFlutterEngine` 註冊):MethodChannel `syncnest/deep_link`。冷啟動 URL 存 `initialLink`(此時 engine/channel 可能未就緒),Dart `start()` 以 method `getInitialLink` 取回;執行中經 method `onLink` 推給 Dart。
- **Dart 端**:`lib/core/deep_link.dart`(`DeepLinkService` 單例,僅 iOS,`main.dart` 首幀後 `start()`)用 MethodChannel `syncnest/deep_link`:`setMethodCallHandler` 收 `onLink`、開頭 `invokeMethod('getInitialLink')` 收冷啟動;`Uri.host`(`memo`/`alarm`)→`AppTab`(`lib/core/tab_router.dart` enum `{clipboard, memo, alarm}`)交給 `TabRouter.instance.go`。`TabRouter` 用 `ValueNotifier<AppTab?> requested`,`RootPage` 監聽→`_indexForTab` 映射成本分支分頁 index→`setState` 切換→`consume` 清空。
- **分支差異**:`RootPage._indexForTab`(`root_page.dart`)映射 `AppTab`→分頁 index。**main**:clipboard=0、memo=1,`alarm` 回 `null`(無鬧鐘分頁,收到即忽略);**feat/alarm-tab**:再加 `alarm`=2。深連結指定分頁時 `_routedByLink=true`,`_loadLastTab` 不再用 `last_tab` 還原覆蓋(避免搶回)。
- **alarm 專屬觸發源(feat/alarm-tab)**:
  - **推播通知點擊**:通知在 App 內處理,不繞 URL scheme。`NotificationService.onTapAlarm`(`notification_service.dart`)由 `main.dart` 設為 `() => TabRouter.instance.go(AppTab.alarm)`;`initialize` 掛 `onDidReceiveNotificationResponse`(前景/背景喚醒點擊),冷啟動另用 `handleLaunchTap()`(`getNotificationAppLaunchDetails`,冷啟動不觸發上面 callback)。設 callback 後才呼叫 `handleLaunchTap`。**冷啟動關鍵**:`AppDelegate.didFinishLaunchingWithOptions` 一開頭就 `UNUserNotificationCenter.current().delegate = self`——implicit-engine 架構下 plugin(flutter_local_notifications)註冊太晚,不早設 delegate 則冷啟動當下投遞的通知回應會遺失(`didNotificationLaunchApp=false`)。**別再宣告 `UNUserNotificationCenterDelegate` 協定**(FlutterAppDelegate 已宣告,會報 redundant conformance)。
  - **Live Activity / 動態島點擊**:`CountdownLiveActivity.swift`——**鎖定畫面 view** 與 **compact/minimal** 用 `.widgetURL(URL(string:"syncnest://alarm"))`;**動態島 compact/minimal 的 `.widgetURL` 必須套在 `DynamicIsland{...}` 實例那一層(與 `.keylineTint` 並列),不是套在 compactLeading/compactTrailing/minimal 各自子 view 內(套錯層完全無效)**;**展開區(expanded)系統忽略 `.widgetURL`,三區各自包 `Link(destination:)`**。URL 由 SceneDelegate `scene:openURLContexts:` 收→`DeepLinkChannel.onLink`→`TabRouter`。
- **✅ 已完成(2026-07,release 實機驗證)**:widget 冷/熱、動態島(compact 單擊 + expanded)冷/熱、鎖定畫面、冷啟動通知——全數切分頁成功。踩過的雷都記在上面(FlutterDeepLinkingEnabled 必關、app_links 抓不到冷啟動、FlutterSceneLifeCycleDelegate 選擇器撞名、動態島 widgetURL 層級、UN delegate 要早設、Live Activity 改碼要重開新活動才生效)。診斷用的 `lib/core/debug_toast.dart` 已整包移除。

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
- **`Runner.xcodeproj/project.pbxproj` 反覆出現 diff 的真相**:`pod install`(由 `flutter build ios`/`flutter run`/手動觸發)整合 Pods 時用 `xcodeproj` gem 重新序列化 Runner.xcodeproj,把 Xcode 26 緊湊格式改成 gem 的多行格式(synchronized group 展開多行、`PBXFileSystemSynchronizedBuildFileExceptionSet` 註解換成人類可讀字串、刪掉空的 `inputPaths`/`outputPaths`)。**這是純排版 churn,`pod install` 不會降 objectVersion**(實測仍保 70)。**曾見的 `objectVersion 70→54` 只來自當初用 xcodeproj gem 加 Widget 的腳本,不是 pod install**。解法:把 gem 格式(objectVersion 70)commit 進去當基準,之後 pod install 讀自家格式原樣寫回=零 diff;唯有偶爾在 Xcode GUI 存檔才會又被改回緊湊格式。

## 桌面系統匣(Minimize to Tray,macOS / Windows)
- `lib/core/desktop_tray_service.dart`。套件 `tray_manager` + `window_manager`。左鍵還原、右鍵選單(顯示/結束);還原時觸發 `AppController.refreshDiscovery()` 重掃 mDNS。`main.dart` 在 `runApp()` 前 `ensureInitialized()`。
- **Windows**:點 X / 最小化 → 隱藏到匣(不結束)。匣圖示 `assets/icon/tray_icon.ico`。
- **macOS**:點紅點關窗 → 隱藏到狀態列;**最小化維持系統慣例進 Dock(不攔截)**。圖示 `assets/icon/tray_icon_macos.png`(**template image**:黑+alpha silhouette,系統依深淺色自動反白,`setIcon(..., isTemplate: true)`;.ico 不能給 macOS 用)。視窗隱藏後點 Dock 圖示叫回視窗靠 `AppDelegate.applicationShouldHandleReopen`(此路徑不經 Dart,不觸發 refreshDiscovery,靠桌面 15 秒重掃補)。
- **macOS 踩雷:`applicationShouldTerminateAfterLastWindowClosed` 必須回 `false`**——即使 preventClose 攔下了 close、只是 orderOut 隱藏,AppKit 仍會對「最後一般視窗離開螢幕」觸發此檢查(有無 NSStatusItem 都一樣),回 true(Flutter 模板預設)= 點紅點直接殺 App。連帶:改 false 後 `windowManager.close()` 在 macOS 只關視窗不退出,tray「結束」`_exitApp` 在 macOS 要改用 `windowManager.destroy()`(=`NSApp.terminate`);Cmd+Q 走 `applicationShouldTerminate` 鏈不受影響。
- **與 `feat/alarm-tab` 的 `menu_bar_service.dart`(macOS 狀態列倒數顯示)合併時必須整合成同一個 tray 圖示**——trayManager 單例只有一個 statusItem,兩邊各自 setIcon/setContextMenu 會互相覆蓋,需做成倒數文字+選單並存,不能各建一個。

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
