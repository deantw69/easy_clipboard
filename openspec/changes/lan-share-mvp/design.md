## Context

全新 Flutter 專案,目標在 macOS / iOS / Windows 三平台共用一份程式碼。第一版限定同一區域網路內互傳圖片/影片/剪貼簿,免帳號免雲端。未來要擴展到跨網路同步與跨平台備忘錄,因此架構需預留替換點。平台能力不對稱是核心限制:桌面可背景常駐,iOS 僅前景手動且讀剪貼簿會跳系統橫幅。

## Goals / Non-Goals

**Goals:**
- 三平台單一程式碼,區網自動發現裝置。
- 大型影片以串流互傳,不耗盡記憶體,含進度。
- 剪貼簿文字/圖片互傳並自動寫入系統剪貼簿。
- 傳輸層/發現層/資料模型抽象化,雲端中繼可後加。

**Non-Goals:**
- 跨網路 / 外網傳輸、雲端中繼(僅預留介面)。
- 跨平台備忘錄(僅在資料模型預留 id/updatedAt/deviceId)。
- iOS 背景自動剪貼簿同步(平台不允許)。

## Decisions

- **跨平台框架用 Flutter**:相對於三套原生,開發/維護成本最低;系統整合缺口用既有 Dart 套件補。
- **發現用 `nsd`**:三平台中唯一同時支援「發現 + 註冊」,雙向互傳需兩端皆可被發現;`multicast_dns` 無註冊、`flutter_nsd` 僅發現,故排除。
- **傳輸沿用 LocalSend「接收端開 server」模型**:接收端跑 `shelf` HTTP server,傳送端用 `dio` 串流上傳。第一版簡化為單段 `POST /file`(metadata 放 header),省去 prepare/upload 兩段往返,夠用且可靠。檔案走 HTTP 而非 WebSocket,因 HTTP 天然支援大檔串流與未來續傳。
- **剪貼簿用 `super_clipboard`**:內建 `Clipboard` 只能純文字;此套件跨三平台支援圖片+富文字(代價是引入 Rust 建置鏈,需 cargo ≥ 1.85)。
- **選取器分平台**:iOS 用 `image_picker`(原生相簿),桌面用 `file_picker`(`image_picker` 桌面支援薄弱)。
- **抽象介面**:`Transport` / `DiscoveryService` 為介面,區網為其一實作;`TransferEnvelope` 與資料模型統一帶 `id/timestamp/deviceId`,雲端中繼與未來同步只換實作。

## Risks / Trade-offs

- [iOS 無背景能力] → UI 明示「需保持 App 開啟、剪貼簿手動觸發」,功能對齊平台現實而非假裝對稱。
- [super_clipboard 仍屬 early stage 且依賴 Rust] → 鎖定可用版本,CI/開發機需 cargo ≥ 1.85(edition2024)。
- [單段上傳無斷點續傳] → 第一版可接受;介面已預留,未來可在 `LanTransport` 內加 Range/offset。
- [固定埠 53318 可能被占用] → 啟動時於埠範圍內退避綁定,以實際埠廣播。

## Open Questions

- iOS 收到的圖片/影片是否要進一步存入系統相簿(需額外套件如 gal),第一版先存 App 文件目錄。
- 桌面剪貼簿自動監聽是否預設開啟,或留為使用者選項。
