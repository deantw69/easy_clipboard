#!/usr/bin/env bash
# 建置「clean 版(無鬧鐘)」。
# 用法:tool/build_clean.sh <flutter build 參數...>
#   例:tool/build_clean.sh macos --release
#       tool/build_clean.sh ios --release --no-codesign
#
# 機制(見 CLAUDE.md「雙建置(full/clean)」):
#   1. 把 pubspec_clean.yaml 覆蓋成 pubspec.yaml(移除 firebase 系依賴 → pod/plugin 不生成)
#   2. active_alarm_feature.dart 改 export stub(Dart 編譯圖不含 alarm/firebase 符號)
#   3. iOS/macOS:清 Pods + Podfile.lock 重裝、移除 Info.plist 的 NSSupportsLiveActivities
#   4. flutter build
#   5. 結束時(含失敗)一律 git checkout 還原被改動的追蹤檔
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "用法:tool/build_clean.sh <target> [flutter build 參數...]"
  echo "  例:tool/build_clean.sh macos --release"
  exit 1
fi

TARGET="$1"
shift || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="$PATH:$HOME/development/flutter/bin"

ACTIVE="lib/alarm_facade/active_alarm_feature.dart"
IOS_PLIST="ios/Runner/Info.plist"

restore() {
  echo "→ 還原被改動的追蹤檔..."
  git checkout -- pubspec.yaml "$ACTIVE" "$IOS_PLIST" 2>/dev/null || true
}
trap restore EXIT

echo "→ 套用 clean 變體(pubspec + facade stub)..."
cp pubspec_clean.yaml pubspec.yaml
printf "%s\n" "export 'alarm_feature_stub.dart';" > "$ACTIVE"

echo "→ flutter clean + pub get..."
flutter clean
flutter pub get

case "$TARGET" in
  ios|macos)
    DIR="$TARGET"
    echo "→ 停用 Live Activity(移除 NSSupportsLiveActivities)..."
    if [ "$TARGET" = "ios" ]; then
      /usr/libexec/PlistBuddy -c "Delete :NSSupportsLiveActivities" "$IOS_PLIST" 2>/dev/null || true
    fi
    echo "→ 清 Pods 並重裝($DIR)..."
    rm -rf "$DIR/Pods" "$DIR/Podfile.lock"
    export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8   # 系統 Ruby 2.6 pod install 需要
    ( cd "$DIR" && pod install )
    ;;
esac

echo "→ flutter build $TARGET $*..."
flutter build "$TARGET" "$@"

echo "✅ clean 版建置完成。"
