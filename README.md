# SyncNest

同一區域網路內，在 **macOS / iOS / Windows** 裝置間互傳**圖片、影片、任意檔案與剪貼簿（文字 / 圖片）**的 Flutter 跨平台 App。免帳號、免雲端、低延遲，直接點對點傳輸。

## 特色

- **自動發現**：同一 Wi-Fi 下，裝置透過 mDNS / Bonjour 互相發現並廣播，自動列出可連線裝置。
- **第一頁同時看裝置與收件**：第一頁上半為附近裝置清單、下半為「收到的內容」（各佔一半，收件全域不分裝置）。手機點裝置跳出選單選「傳送圖片 / 影片」或「傳送剪貼簿」；桌面點裝置進傳送頁（保留拖曳與 ⌘/Ctrl+V）。
- **檔案直傳**：接收端跑 HTTP server，傳送端串流上傳（邊收邊寫），大檔不佔記憶體。
- **剪貼簿互傳**：讀取本機剪貼簿（文字 / 圖片）傳到目標裝置；文字接收端自動寫入系統剪貼簿。
- **圖片由接收方決定**：收到圖片（剪貼簿圖片或圖片檔）時，接收端跳出預覽，由本機自行選擇「複製到剪貼簿」或「儲存」（桌面：在 Finder / 檔案總管顯示；iOS：存進相簿），傳送端不再代為決定。
- **iOS 收影片存相簿**：iPhone 收到的影片直接存進系統相簿，而非僅留在 App 目錄。
- **iOS 系統分享選單**：在其他 App（相簿、Safari、Instagram 等）點「分享」即可選 **SyncNest**，把**圖片 / 文字 / 網址**直接送到上次使用的裝置（離線時跳裝置選單讓你選）。網址在接收端會詢問是否用瀏覽器開啟。透過 iOS Share Extension + App Group 實作。
- **清除收到的內容**：第一頁「收到的內容」可一鍵清除，刪除暫存於本機的檔案釋放容量（含前次啟動殘留的檔），已存進相簿者不受影響。
- **跨裝置備忘錄**：獨立「備忘錄」分頁（底部分頁切換），便利貼風格列出小備忘錄，支援純文字與待辦勾選。可選便利貼底色、拖曳排序（順序跨裝置同步，勾選待辦不會改變排序）、待辦一鍵複製、刪除前確認。內容本機持久化（`memos.json`），同一區網的裝置自動雙向同步（Last-Write-Wins + 刪除墓碑）；不需 server，iPhone 隨身帶著即可作為 macOS ↔ Windows 的同步橋樑。最後選擇的分頁會本機記住（各裝置分開），重開還原。從手機分享網址進來時可選擇「加入備忘錄」（加為某則待辦）或傳到其他裝置。`memos.json` 採原子寫入並保留一份 `.bak` 備份，主檔損毀時自動從備份還原並提示，避免資料無聲消失。
- **桌面快捷操作**（macOS / Windows）：點裝置進傳送頁後按 **⌘/Ctrl + V** 直接傳出目前剪貼簿（圖片優先、否則文字）；或將圖片 / 影片**拖曳到視窗放開**即傳出。
- **開機自動啟動**（macOS / Windows）：首頁右上齒輪 → 設定中可切換「開機自動啟動」，登入系統時自動開啟 App。macOS 透過 `SMAppService`、Windows 透過登錄機碼實作。開啟後可再切子選項「自啟時隱藏視窗」，登入啟動時只縮到系統匣背景執行，用全域快捷鍵／匣圖示呼出。
- **可重選儲存資料夾**（macOS / Windows）：首頁右上齒輪 → 設定中可變更備忘錄與接收檔案的儲存資料夾（預設 `下載/SyncNest`）。變更時會把舊資料夾內容複製過去（不覆蓋同名檔），可「還原預設位置」。macOS 沙盒下以 security-scoped bookmark 持久化所選資料夾，重啟後仍可存取。
- **單一程式碼庫**：macOS / iOS / Windows 共用同一份 Flutter 程式碼。
- **可擴展架構**：傳輸層 / 發現層 / 資料模型以介面抽象，未來可擴展「跨網路雲端中繼」而不動既有結構。

## 平台能力差異

| 能力 | 桌面（macOS / Windows） | iOS |
| --- | --- | --- |
| 背景接收 | 可（App 在前景 / 背景皆可運作） | 受限：需保持 App 開啟於前景 |
| 剪貼簿讀取 | 直接讀取 | 讀取時系統會跳出橫幅提示 |
| ⌘/Ctrl+V 傳出、拖曳傳出 | 支援 | 不適用 |
| 收到圖片 | 跳預覽，選複製到剪貼簿或在 Finder 顯示（檔已落地下載資料夾） | 跳預覽，選複製到剪貼簿或存進相簿 |
| 收到影片 | 存到下載資料夾 | 存進系統相簿 |

## 架構

```
lib/
├── main.dart                       入口，注入 AppController（provider）
├── app_controller.dart             中央狀態：串起身分 / 發現 / 傳輸 / 剪貼簿
├── core/
│   ├── identity.dart               裝置穩定識別碼與名稱（持久化）
│   ├── autostart.dart              開機自啟動（macOS SMAppService / Windows 登錄機碼）
│   ├── share_handler.dart          iOS：接收系統分享選單傳入的內容並送出（receive_sharing_intent）
│   └── models.dart                 DeviceInfo / TransferEnvelope / ReceivedItem
├── discovery/
│   ├── discovery.dart              發現服務介面
│   └── nsd_discovery.dart          mDNS / Bonjour 實作（nsd）
├── transport/
│   ├── transport.dart              傳輸介面
│   └── lan_transport.dart          區網直傳（shelf server + dio 串流）
├── clipboard/
│   └── clipboard_service.dart      系統剪貼簿讀寫（super_clipboard）
├── memos/
│   └── memo_store.dart             備忘錄資料層：Memo / MemoTodo 模型、memos.json 持久化、LWW 合併
└── features/
    ├── root_page.dart              底部分頁殼（剪貼簿 / 備忘錄）
    ├── memos_page.dart             備忘錄分頁（便利貼列表、色票、拖曳排序、待辦勾選 / 複製、新增 / 編輯 / 刪除確認）
    └── home_page.dart              HomePage（裝置清單＋收到的內容；手機點裝置跳傳送選單）＋ DevicePage（僅桌面：傳送 / 桌面快捷與拖曳）
```

### 區網傳輸協定

接收端開 HTTP server（埠 `53318`，被占用時往上嘗試至 `53337`）：

- `GET /info` → 回傳本機裝置 JSON（連線前確認）
- `POST /file` → header `x-envelope` 帶 metadata，body 為檔案串流
- `POST /clipboard` → header `x-envelope` 帶 metadata，body 為文字 / PNG 位元組
- `POST /memos/sync` → body 為發起方完整備忘錄清單 JSON；接收端合併（LWW）後回傳自己合併後的完整清單，一次往返雙方收斂

## 開始使用

需求：Flutter SDK（Dart `^3.12.1`）。`super_clipboard` 會引入 Rust 建置鏈（cargo ≥ 1.85，支援 edition2024）。

```bash
flutter pub get
flutter run            # 桌面或已連接的裝置
```

執行後將兩台裝置接上**同一個 Wi-Fi**，App 會自動列出彼此；點選裝置即可傳送檔案或剪貼簿內容。

### 平台設定

- **iOS** `Info.plist`：本地網路 / Bonjour 服務、相簿讀取（`NSPhotoLibraryUsageDescription`）與相簿寫入（`NSPhotoLibraryAddUsageDescription`）權限；Podfile `platform :ios, '13.0'`。
- **iOS 分享選單**：另有 `Share Extension` target（自包含原生 Swift，不依賴 Flutter），與主 App 共用 App Group `group.com.philio.syncNest`；擴充把內容寫進 App Group 後以 URL scheme `ShareMedia-com.philio.syncNest` 喚醒主 App，主 App 端以 `receive_sharing_intent` 讀取。設定步驟見 [docs/ios-share-extension-setup.md](docs/ios-share-extension-setup.md)。
- **macOS** entitlements：network server / client、檔案存取（拖曳進來的檔案以 user-selected 權限讀取）；部署目標 `macOS 13.0`（開機自啟動 `SMAppService` 需求），`MainFlutterWindow.swift` 以 `SyncNest/autostart` method channel 處理自啟動。開機自啟動需 App 經過簽署才會生效。
- **Windows** 開機自啟動：`win32_registry` 寫入 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`。

## 開發

本專案採 [OpenSpec](https://github.com/Fission-AI/OpenSpec) 進行 spec-driven 開發，規格與變更紀錄位於 `openspec/`。第一版範圍見 `openspec/changes/lan-share-mvp/`。

```bash
flutter analyze
flutter test
```
