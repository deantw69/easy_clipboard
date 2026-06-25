# easy_clipboard 專案慣例

## macOS 建置
- 編譯 macOS release 版後，**一律**把產出的 `.app` 複製一份到使用者的下載資料夾，方便取用：
  ```bash
  flutter build macos --release
  rm -rf ~/Downloads/easy_clipboard.app
  cp -R build/macos/Build/Products/Release/easy_clipboard.app ~/Downloads/easy_clipboard.app
  ```
- `flutter` 不在預設 PATH，需先 `export PATH="$PATH:$HOME/development/flutter/bin"`。
- macOS / iOS 部署目標已因 `gal` 套件需求提高到 **11.0**（`macos/Podfile` 與 `project.pbxproj` 的 `MACOSX_DEPLOYMENT_TARGET`）。
