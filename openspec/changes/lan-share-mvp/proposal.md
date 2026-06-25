## Why

使用者需要在常用的 macOS / iPhone / Windows 三類裝置間,簡單地互傳圖片、影片與剪貼簿內容。現有方案(AirDrop 僅 Apple 生態、雲端硬碟需上傳下載)無法同時涵蓋三平台且操作繁瑣。第一版鎖定同一區域網路內的直接互傳,免帳號、免雲端、低延遲。

## What Changes

- 新增 Flutter 跨平台 App(macOS / iOS / Windows 單一程式碼)。
- 同區網裝置自動發現與互相廣播(mDNS / Bonjour)。
- 裝置間直傳圖片 / 影片 / 任意檔(接收端 HTTP server + 傳送端串流上傳,大檔不佔記憶體)。
- 剪貼簿文字與圖片互傳,接收端自動寫入系統剪貼簿。
- 傳輸層 / 發現層 / 資料模型以介面抽象,為未來「跨網路雲端中繼 + 跨平台備忘錄」預留擴展(本版不實作)。
- 明示平台能力不對稱:桌面可背景自動;iOS 受限於前景手動、需保持 App 開啟、剪貼簿讀取會跳系統橫幅。

## Capabilities

### New Capabilities
- `device-discovery`: 區網內裝置的自動發現與本機廣播,輸出可連線的裝置清單。
- `file-transfer`: 在已發現的裝置間串流傳送圖片 / 影片 / 任意檔,含進度回報與落地儲存。
- `clipboard-sync`: 讀取本機剪貼簿(文字 / 圖片)傳送到目標裝置,接收端寫入系統剪貼簿。

### Modified Capabilities
<!-- 無既有 spec 需修改 -->

## Impact

- 新增依賴:nsd、shelf、dio、super_clipboard、file_picker、image_picker、path_provider、provider、uuid、path。
- 平台設定:iOS `Info.plist`(本地網路 / Bonjour / 相簿權限)、macOS entitlements(network server/client、檔案存取)、iOS Podfile `platform :ios, '13.0'`。
- 程式碼:`lib/` 下新增 core / discovery / transport / clipboard / features 模組與 `app_controller`。
- super_clipboard 引入 Rust 建置鏈(cargo ≥ 1.85,支援 edition2024)。
