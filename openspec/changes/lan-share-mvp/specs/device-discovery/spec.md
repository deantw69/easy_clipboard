## ADDED Requirements

### Requirement: 本機裝置廣播
App 啟動後 SHALL 在區域網路上以 mDNS 服務類型 `_easyclip._tcp` 廣播本機裝置,TXT 紀錄 MUST 包含穩定的 `id`、顯示用 `name` 與 `platform`。

#### Scenario: 啟動後可被其他裝置發現
- **WHEN** App 在某裝置啟動且取得本地網路權限
- **THEN** 同區網的其他裝置 SHALL 能透過 `_easyclip._tcp` 解析到該裝置的 host、port 與 TXT 中的 id/name/platform

#### Scenario: 裝置識別碼跨啟動穩定
- **WHEN** App 重新啟動
- **THEN** 廣播的 `id` SHALL 與前次相同(持久化於本機),以利未來同步與去重

### Requirement: 區網裝置發現
App SHALL 持續瀏覽 `_easyclip._tcp` 服務,維護一份目前可連線的裝置清單,並 MUST 從清單中排除本機。

#### Scenario: 顯示附近裝置
- **WHEN** 同區網有其他裝置在廣播
- **THEN** UI 的裝置清單 SHALL 顯示這些裝置的名稱、平台與位址,且不含本機自身

#### Scenario: 裝置離線後移除
- **WHEN** 某裝置停止廣播或離開網路
- **THEN** 該裝置 SHALL 自清單中移除

### Requirement: 本地網路權限引導(iOS)
在 iOS 上,App SHALL 透過 `Info.plist` 宣告 `NSLocalNetworkUsageDescription` 與 `NSBonjourServices`,並在權限被拒時讓使用者得知無法發現裝置。

#### Scenario: 權限被拒
- **WHEN** 使用者拒絕本地網路權限
- **THEN** App SHALL 不致崩潰,且 UI SHALL 提示需開啟本地網路才能使用
