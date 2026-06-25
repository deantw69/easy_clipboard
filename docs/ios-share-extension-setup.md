# iOS 分享選單(Share Extension)設定步驟

讓 easy_clipboard 出現在 iOS 系統「分享」彈出選單中(從相簿、Safari、IG 等分享照片 /
文字 / 網址時可選到本 App,並自動傳送到上次的裝置)。

Flutter / Swift 程式碼與設定檔都已寫好,**以下只剩 Xcode GUI 與 Apple 後台的步驟需要你手動完成**。
App Group 沒設好,Extension 與主 App 無法共享分享進來的資料,整個功能不會動。

- **App Group 名稱**:`group.com.philio.easyClipboard`
- **主 App Bundle ID**:`com.philio.easyClipboard`
- **Extension Bundle ID**:`com.philio.easyClipboard.Share`
- **Extension target 名稱**:必須**精確**為 `Share Extension`(Podfile 以此名對應)

---

## 1. 開啟專案

```bash
open ios/Runner.xcworkspace
```

## 2. 新增 Share Extension target

1. Xcode 選單 **File → New → Target…**
2. 選 **iOS → Application Extension → Share Extension**,按 Next。
3. **Product Name** 填 `Share Extension`(含空格,務必一致)。
   - Language:Swift。
   - 確認 **Bundle Identifier** 為 `com.philio.easyClipboard.Share`。
4. 按 Finish。跳出 **"Activate "Share Extension" scheme?"** 時按 **Cancel**(不要啟用此 scheme)。

Xcode 會在 `ios/Share Extension/` 自動產生 `ShareViewController.swift`、`Info.plist`、
`MainInterface.storyboard` 等預設檔。

## 3. 用本專案範本覆蓋自動產生的檔

target 建好後,在終端機執行(把已寫好的範本覆蓋進去):

```bash
cd ios
cp ShareExtensionTemplate/ShareViewController.swift "Share Extension/ShareViewController.swift"
cp ShareExtensionTemplate/Info.plist               "Share Extension/Info.plist"
cp ShareExtensionTemplate/MainInterface.storyboard "Share Extension/Base.lproj/MainInterface.storyboard"
cp "ShareExtensionTemplate/Share Extension.entitlements" "Share Extension/Share Extension.entitlements"
```

> 若 Xcode 產生的 storyboard 不在 `Base.lproj/`,改放到它實際的位置即可。
> 範本內容:啟動規則只開放**圖片 / 文字 / 網址**(不含影片、任意檔)。

回到 Xcode,把 `Share Extension.entitlements` 拖進左側 **Share Extension** group(若尚未在專案樹中)。

## 4. 加入 App Group 能力(主 App 與 Extension 都要)

對 **Runner** target:
1. 選 Runner target → **Signing & Capabilities**。
2. 點 **+ Capability** → 加入 **App Groups**。
3. 勾選 / 新增 `group.com.philio.easyClipboard`。
   - 這會自動套用已存在的 `Runner/Runner.entitlements`(已含此 group)。

對 **Share Extension** target:
1. 選 Share Extension target → **Signing & Capabilities**。
2. **+ Capability → App Groups**,同樣加入 `group.com.philio.easyClipboard`。
3. 確認 Build Settings 的 **Code Signing Entitlements** 指向
   `Share Extension/Share Extension.entitlements`。

> App Group 能力需綁定你的 Apple Developer 帳號;若 Xcode 報錯,到
> [developer.apple.com](https://developer.apple.com) → Identifiers,為兩個 App ID 啟用 App Groups
> 並建立 `group.com.philio.easyClipboard`,再讓 Xcode 重新產生 provisioning profile。

## 5. 設定 Extension 的 Deployment Target

Share Extension target → **General → Minimum Deployments** 設為 **iOS 13.0**(與主 App 一致)。

## 6. 啟用 Podfile 的 Extension target

編輯 `ios/Podfile`,把這三行的註解取消:

```ruby
  target 'Share Extension' do
    inherit! :search_paths
  end
```

然後安裝 pod:

```bash
cd ios && pod install
```

## 7. 建置與測試

```bash
flutter run               # 或在 Xcode 直接 Run Runner
```

測試:相簿選一張照片 → 分享 → 應可看到 **easy_clipboard**。
選取後 App 會切到前景,自動傳送到上次的裝置(找不到則跳裝置選單)。

---

## 已知注意事項

- **暖啟動(App 已在前景/背景)**:本專案使用 `UIScene` 生命週期(`SceneDelegate`)。
  冷啟動走 App Group 讀取,一定正常。若發現「App 已開著時分享沒有反應」,
  需在 `SceneDelegate` 轉送 `scene(_:openURLContexts:)` 給外掛;屆時再補。
- **內容類型**:目前只接圖片 / 文字 / 網址。要加影片或任意檔,於
  `Share Extension/Info.plist` 的 `NSExtensionActivationRule` 加回對應 key,
  並在 `lib/core/share_handler.dart` 處理 `video` / `file` 類型。
- **網址**:送到對端後,接收方會跳「在瀏覽器開啟 / 複製 / 關閉」。
