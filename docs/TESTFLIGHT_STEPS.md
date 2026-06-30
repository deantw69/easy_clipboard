# easy_clipboard 外部 TestFlight 上架手動步驟

目標:把 iOS 版發佈到**外部 TestFlight**(Email／公開連結邀請,最多 10000 人),通過一次輕量 Beta App Review。

> 程式端已處理:`Info.plist` 加 `ITSAppUsesNonExemptEncryption=false`(免出口管制問卷)、新增 `ios/Runner/PrivacyInfo.xcprivacy` 並已掛進 Runner target。以下為你需要手動操作的部分。

關鍵資訊:
- Bundle ID(主 App):`com.philio.easyClipboard`
- Bundle ID(分享擴充):`com.philio.easyClipboard.Share-Extension`
- App Group:`group.com.philio.easyClipboard`
- Team ID:`6P5WSRHW66`
- 版本:`1.0.0 (build 1)`

---

## B1. Apple Developer Portal — 帳號與識別碼
網址:https://developer.apple.com/account

- [ ] 確認 Team `6P5WSRHW66` 已加入**付費** Apple Developer Program(US$99/年;未付費無法上傳)。
- [ ] Certificates, IDs & Profiles → **Identifiers** → 篩選 **App Groups**:確認 `group.com.philio.easyClipboard` 存在,沒有就 ➕ 新建(Description 任填、ID 填這串)。
- [ ] **Identifiers** → App IDs,確認以下兩個都存在且都關聯了上面那組 App Group:
  - `com.philio.easyClipboard`(主 App)→ 編輯 → Capabilities 勾 **App Groups** → Configure → 勾 `group.com.philio.easyClipboard`
  - `com.philio.easyClipboard.Share-Extension`(擴充)→ 同樣勾 App Groups → 同一組
  > 用 Xcode 自動簽章時 App ID 會自動建立,但 **App Group 必須先存在**才能正確關聯,否則 archive 簽章失敗。

## B2. App Store Connect — 建立 App 紀錄
網址:https://appstoreconnect.apple.com

- [ ] My Apps → ➕ → **New App**
  - Platform:iOS
  - Name:`Easy Clipboard`(若已被占用需換名)
  - Primary Language:繁體中文(或你要的)
  - Bundle ID:選 `com.philio.easyClipboard`
  - SKU:任填(例 `easyclipboard001`)
  - User Access:Full
- [ ]「App 隱私(App Privacy)」外部 TestFlight 不強制完整填,建議先標 **Data Not Collected**(本 App 不蒐集資料、只在區網傳輸)。

## B3. Xcode — 簽章設定
- [ ] 用 Xcode 開 **`ios/Runner.xcworkspace`**(不是 `.xcodeproj`)。
- [ ] **Runner** target → Signing & Capabilities:
  - Team = `6P5WSRHW66`
  - ✅ Automatically manage signing
  - 確認 App Groups 內有 `group.com.philio.easyClipboard`
- [ ] **Share Extension** target → 同樣設 Team、自動簽章、App Groups 勾 `group.com.philio.easyClipboard`。
- [ ](選)在 Runner 的 Build Phases → Copy Bundle Resources 確認有 `PrivacyInfo.xcprivacy`(程式已加,正常應已在)。

## B4. 打包與上傳
> `flutter` 不在 PATH 時先:`export PATH="$PATH:$HOME/development/flutter/bin"`

**路線 A:CLI(推薦,快)**
```bash
export PATH="$PATH:$HOME/development/flutter/bin"
cd /Users/philio/Downloads/easy_clipboard
flutter build ipa --release
# 產物:build/ios/ipa/easy_clipboard.ipa
```
- [ ] 用 **Transporter**(Mac App Store 免費下載)拖入 `.ipa` → Deliver 上傳。
  或 `xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios -u <Apple ID> -p <App 專用密碼>`。

**路線 B:Xcode**
- [ ] Xcode → 選 `Any iOS Device` → Product → **Archive** → Distribute App → App Store Connect → Upload。

- [ ] 上傳後在 App Store Connect → TestFlight 等 build 由 "Processing" 變為可用(數分鐘~1 小時)。

> 之後每次重新上傳要把 build number 加一:`flutter build ipa --release --build-number=2`(`pubspec.yaml` 的 `+1` 或此參數)。

## B5. TestFlight 外部測試設定
- [ ] App Store Connect → 你的 App → **TestFlight** 分頁。
- [ ] 出口管制:已加 `ITSAppUsesNonExemptEncryption=false`,**不會再被問**(若仍被問,選「No / 不使用非豁免加密」)。
- [ ] 左側「測試資訊(Test Information)」填:Beta App 描述、Feedback Email、**審核備註**(見 B6,務必填)。
- [ ] 建立 **External Group**(外部群組)→ 加入剛處理好的 build → 新增測試員(Email)或開啟 **Public Link** 公開連結。
- [ ] 首次外部 build 會自動進入 **Beta App Review**(輕量,通常 1 天內)。通過後同群組後續 build 多半免再審。

## B6. 審核備註(複製貼上用,降低被退風險)
> 核心功能需同一 Wi-Fi 下兩台裝置互傳,單機難完整展示,務必說明:

```
本 App 為區域網路內的裝置間傳輸工具:可在同一 Wi-Fi 下,於多台裝置之間互傳剪貼簿文字、圖片/影片檔案,以及同步備忘錄。
裝置探索使用 Bonjour 服務 _easyclip._tcp,傳輸走區網內 HTTP / WebSocket,「不經過任何外部伺服器、不上傳任何資料到雲端」。

測試前提:需要兩台連到同一 Wi-Fi 的裝置(例如兩支 iPhone,或 iPhone 搭配執行本 App 桌面版的 Mac/Windows)才能完整驗證傳輸功能;單一裝置可瀏覽介面但無法觀察跨裝置傳輸。
若不便準備第二台裝置,我可提供操作示範影片。
```
- [ ](建議)錄一段兩台裝置互傳的 demo 影片,連結附在備註,避免審核員「無法驗證功能」。

---

## 完成判斷
- [ ] `flutter build ipa --release` 成功產出 ipa(簽章/App Group/擴充皆過)。
- [ ] 上傳後 build 正常處理,**沒有跳出出口管制問卷**。
- [ ] **沒有收到** Apple 寄來的 Privacy Manifest 警告 email。
- [ ] 外部測試員收到邀請可安裝;兩台同網裝置實測傳輸正常。

## 本次未涵蓋(正式上架才需要)
商店截圖、關鍵字/描述、完整 App 隱私標籤、年齡分級、隱私政策 URL、兩台裝置 demo 影片(上架審核較可能要求)。macOS/Windows 發佈為另案。
