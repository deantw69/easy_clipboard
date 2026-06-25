# easy_clipboard 專案慣例

## macOS 建置
- 編譯 macOS release 版後，**一律**把產出的 `.app` 複製一份到使用者的下載資料夾，方便取用：
  ```bash
  flutter build macos --release
  rm -rf ~/Downloads/easy_clipboard.app
  cp -R build/macos/Build/Products/Release/easy_clipboard.app ~/Downloads/easy_clipboard.app
  ```
- `flutter` 不在預設 PATH，需先 `export PATH="$PATH:$HOME/development/flutter/bin"`。
- iOS 部署目標因 `gal` 套件需求為 **11.0**；macOS 部署目標因開機自啟動用 `SMAppService` 已提高到 **13.0**（`macos/Podfile` 與 `project.pbxproj` 的 `MACOSX_DEPLOYMENT_TARGET`）。

## 開機自啟動
- 設定入口：首頁 AppBar 齒輪圖示 → 設定對話框的「開機自動啟動」開關（僅 macOS / Windows 顯示）。
- 實作在 `lib/core/autostart.dart`：
  - macOS：透過 `easy_clipboard/autostart` method channel 呼叫原生 `SMAppService.mainApp`（`MainFlutterWindow.swift`），需 macOS 13+。
  - Windows：寫入 `HKCU\...\CurrentVersion\Run` 登錄機碼（`win32_registry` 套件）。
