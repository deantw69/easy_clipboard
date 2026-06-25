## ADDED Requirements

### Requirement: 傳送剪貼簿內容
使用者選擇目標裝置並觸發剪貼簿傳送時,App SHALL 讀取本機剪貼簿;若含圖片則以 PNG 傳送,否則以純文字傳送。

#### Scenario: 傳送剪貼簿圖片
- **WHEN** 本機剪貼簿含圖片且使用者按「傳送剪貼簿」
- **THEN** App SHALL 將圖片以 PNG 傳送到目標裝置

#### Scenario: 傳送剪貼簿文字
- **WHEN** 本機剪貼簿僅含文字
- **THEN** App SHALL 將文字傳送到目標裝置

#### Scenario: 剪貼簿為空
- **WHEN** 剪貼簿沒有文字也沒有圖片
- **THEN** App SHALL 提示沒有可傳送的內容,且不發出傳送

### Requirement: 接收並寫入系統剪貼簿
接收端收到剪貼簿類型內容時 SHALL 自動寫入本機系統剪貼簿,使用者可直接貼上。

#### Scenario: 接收文字後可貼上
- **WHEN** 裝置收到剪貼簿文字
- **THEN** 該文字 SHALL 被寫入本機系統剪貼簿,並在收件清單顯示一筆紀錄

#### Scenario: 接收圖片後可貼上
- **WHEN** 裝置收到剪貼簿圖片
- **THEN** 該圖片 SHALL 被寫入本機系統剪貼簿(PNG)

### Requirement: iOS 剪貼簿取捨
在 iOS 上,剪貼簿讀取 SHALL 僅由前景的手動操作觸發,App SHALL NOT 在背景輪詢剪貼簿;UI MUST 告知使用者每次讀取會出現系統橫幅且需保持 App 開啟。

#### Scenario: iOS 不背景監聽
- **WHEN** App 切到背景
- **THEN** App SHALL NOT 嘗試讀取剪貼簿

#### Scenario: 桌面可自動監聽(選用)
- **WHEN** 在 macOS / Windows 啟用剪貼簿監聽
- **THEN** App MAY 以低頻輪詢偵測文字變化,並避免把本機剛寫入的內容回送
