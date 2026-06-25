## ADDED Requirements

### Requirement: 接收端 HTTP 服務
每台裝置 SHALL 啟動一個 HTTP 接收服務,提供 `GET /info`(回傳裝置資訊)、`POST /file`(接收檔案)端點,並 MUST 在預設埠被占用時自動改用其他可用埠。

#### Scenario: 埠衝突自動退避
- **WHEN** 預設埠 53318 已被占用
- **THEN** 接收服務 SHALL 嘗試後續埠直到綁定成功,並以實際埠對外廣播

### Requirement: 串流傳送檔案
傳送端 SHALL 以串流方式上傳檔案本體,接收端 MUST 邊接收邊寫入磁碟,過程中 SHALL NOT 將整個檔案載入記憶體,以支援大型影片。

#### Scenario: 傳送大型影片不耗盡記憶體
- **WHEN** 使用者傳送一個數百 MB 的影片
- **THEN** 傳送與接收 SHALL 以串流完成,記憶體用量 SHALL 維持在低水位

#### Scenario: 傳送進度回報
- **WHEN** 檔案傳送進行中
- **THEN** 傳送端 UI SHALL 顯示 0% 到 100% 的進度

### Requirement: 檔案落地與命名
接收到的檔案 SHALL 儲存到平台適當目錄(桌面用 Downloads、行動裝置用 App 文件目錄)的 `EasyClipboard` 子資料夾,且檔名衝突時 MUST 自動加序號避免覆蓋。

#### Scenario: 同名檔案不覆蓋
- **WHEN** 接收的檔名與既有檔案相同
- **THEN** 新檔 SHALL 以 `名稱 (1).副檔名` 形式儲存,不覆蓋原檔

#### Scenario: 來源裝置選取媒體
- **WHEN** 使用者在 iPhone 選取照片/影片(相簿)或在桌面選取檔案
- **THEN** App SHALL 使用對應平台的選取器(iOS 用相簿選取器、桌面用檔案選取器)取得來源檔

### Requirement: 傳輸層抽象
傳輸功能 SHALL 透過介面(`Transport`)定義,區網實作為其中一種;新增雲端中繼實作時 MUST NOT 需要更動 UI 或上層服務。

#### Scenario: 可替換傳輸實作
- **WHEN** 未來新增雲端中繼傳輸
- **THEN** 僅需新增實作 `Transport` 的類別,UI 與 `AppController` SHALL 不需修改
