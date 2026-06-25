## 1. 專案與依賴

- [x] 1.1 以 `flutter create` 建立 macos/ios/windows 三平台專案
- [x] 1.2 加入依賴:nsd、shelf、dio、web_socket_channel、super_clipboard、file_picker、image_picker、path_provider、provider、uuid、path
- [x] 1.3 平台設定:iOS Info.plist(本地網路/Bonjour/相簿)、macOS entitlements、iOS Podfile platform 13.0

## 2. 核心資料模型

- [x] 2.1 定義 DeviceInfo / TransferEnvelope / ReceivedItem(`lib/core/models.dart`)
- [x] 2.2 持久化裝置身分 deviceId/name(`lib/core/identity.dart`)

## 3. 裝置發現

- [x] 3.1 定義 `DiscoveryService` 介面(`lib/discovery/discovery.dart`)
- [x] 3.2 以 nsd 實作註冊+瀏覽,排除本機(`lib/discovery/nsd_discovery.dart`)

## 4. 傳輸層

- [x] 4.1 定義 `Transport` 介面(`lib/transport/transport.dart`)
- [x] 4.2 接收端 shelf server:`/info`、`/file`、`/clipboard` 邊收邊寫(`lib/transport/lan_transport.dart`)
- [x] 4.3 傳送端 dio 串流上傳 + 進度回報
- [x] 4.4 接收檔案落地到 EasyClipboard 目錄、同名加序號、埠退避

## 5. 剪貼簿

- [x] 5.1 super_clipboard 讀寫文字/圖片(`lib/clipboard/clipboard_service.dart`)
- [x] 5.2 桌面輪詢監聽 ClipboardWatcher(避免回送本機剛寫入內容)

## 6. 串接與 UI

- [x] 6.1 AppController 串接身分/發現/傳輸/剪貼簿(`lib/app_controller.dart`)
- [x] 6.2 首頁:裝置清單、收件清單、傳送圖片影片/剪貼簿、進度對話框、iOS 提示(`lib/features/home_page.dart`)
- [x] 6.3 main 以 provider 注入 AppController

## 7. 驗證

- [x] 7.1 flutter analyze 無問題、單元測試通過
- [x] 7.2 macOS 編譯成功 + 本機冒煙(server 起、nsd 廣播可被發現、不崩潰)
- [x] 7.3 iOS 模擬器免簽章編譯成功
- [ ] 7.4 兩台裝置同區網實測互傳(iPhone↔Mac↔Windows):圖片、影片、剪貼簿
- [ ] 7.5 大型影片串流不 OOM、進度與中斷重試
- [ ] 7.6 iOS 真機驗證本地網路權限對話框與剪貼簿橫幅行為

## 8. 後續(非本版必須)

- [ ] 8.1 iOS 收到的照片/影片可選存入系統相簿(gal)
- [ ] 8.2 桌面 system tray / menu bar 常駐
- [ ] 8.3 Windows 機器實機編譯與測試
