# easy_clipboard

同一區域網路內，在 **macOS / iOS / Windows** 裝置間互傳**圖片、影片、任意檔案與剪貼簿（文字 / 圖片）**的 Flutter 跨平台 App。免帳號、免雲端、低延遲，直接點對點傳輸。

## 特色

- **自動發現**：同一 Wi-Fi 下，裝置透過 mDNS / Bonjour 互相發現並廣播，自動列出可連線裝置。
- **兩段式操作**：第一頁是附近裝置清單，點選裝置即「連上」並進入該裝置的傳輸頁；傳輸頁上半部為傳送操作、下半部為收到的內容。
- **檔案直傳**：接收端跑 HTTP server，傳送端串流上傳（邊收邊寫），大檔不佔記憶體。
- **剪貼簿互傳**：讀取本機剪貼簿（文字 / 圖片）傳到目標裝置，接收端自動寫入系統剪貼簿。
- **iOS 收檔存相簿**：iPhone 收到的圖片 / 影片直接存進系統相簿，而非僅留在 App 目錄。
- **桌面快捷操作**（macOS / Windows）：在傳輸頁按 **⌘/Ctrl + V** 直接傳出目前剪貼簿（圖片優先、否則文字）；或將圖片 / 影片**拖曳到視窗放開**即傳出。
- **單一程式碼庫**：macOS / iOS / Windows 共用同一份 Flutter 程式碼。
- **可擴展架構**：傳輸層 / 發現層 / 資料模型以介面抽象，未來可擴展「跨網路雲端中繼」而不動既有結構。

## 平台能力差異

| 能力 | 桌面（macOS / Windows） | iOS |
| --- | --- | --- |
| 背景接收 | 可（App 在前景 / 背景皆可運作） | 受限：需保持 App 開啟於前景 |
| 剪貼簿讀取 | 直接讀取 | 讀取時系統會跳出橫幅提示 |
| ⌘/Ctrl+V 傳出、拖曳傳出 | 支援 | 不適用 |
| 收到圖片 / 影片 | 存到下載資料夾 | 存進系統相簿 |

## 架構

```
lib/
├── main.dart                       入口，注入 AppController（provider）
├── app_controller.dart             中央狀態：串起身分 / 發現 / 傳輸 / 剪貼簿
├── core/
│   ├── identity.dart               裝置穩定識別碼與名稱（持久化）
│   └── models.dart                 DeviceInfo / TransferEnvelope / ReceivedItem
├── discovery/
│   ├── discovery.dart              發現服務介面
│   └── nsd_discovery.dart          mDNS / Bonjour 實作（nsd）
├── transport/
│   ├── transport.dart              傳輸介面
│   └── lan_transport.dart          區網直傳（shelf server + dio 串流）
├── clipboard/
│   └── clipboard_service.dart      系統剪貼簿讀寫（super_clipboard）
└── features/
    └── home_page.dart              HomePage（裝置清單）＋ DevicePage（傳送 / 接收 / 桌面快捷與拖曳）
```

### 區網傳輸協定

接收端開 HTTP server（埠 `53318`，被占用時往上嘗試至 `53337`）：

- `GET /info` → 回傳本機裝置 JSON（連線前確認）
- `POST /file` → header `x-envelope` 帶 metadata，body 為檔案串流
- `POST /clipboard` → header `x-envelope` 帶 metadata，body 為文字 / PNG 位元組

## 開始使用

需求：Flutter SDK（Dart `^3.12.1`）。`super_clipboard` 會引入 Rust 建置鏈（cargo ≥ 1.85，支援 edition2024）。

```bash
flutter pub get
flutter run            # 桌面或已連接的裝置
```

執行後將兩台裝置接上**同一個 Wi-Fi**，App 會自動列出彼此；點選裝置即可傳送檔案或剪貼簿內容。

### 平台設定

- **iOS** `Info.plist`：本地網路 / Bonjour 服務、相簿讀取（`NSPhotoLibraryUsageDescription`）與相簿寫入（`NSPhotoLibraryAddUsageDescription`）權限；Podfile `platform :ios, '13.0'`。
- **macOS** entitlements：network server / client、檔案存取（拖曳進來的檔案以 user-selected 權限讀取）。

## 開發

本專案採 [OpenSpec](https://github.com/Fission-AI/OpenSpec) 進行 spec-driven 開發，規格與變更紀錄位於 `openspec/`。第一版範圍見 `openspec/changes/lan-share-mvp/`。

```bash
flutter analyze
flutter test
```
