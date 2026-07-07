#!/usr/bin/env bash
# 建置「full 版(含鬧鐘)」。
# 用法:tool/build_full.sh <target> [flutter build 參數...]
#   例:tool/build_full.sh macos --release
#
# full 是版本庫預設狀態(pubspec.yaml 與 active_alarm_feature.dart 皆為 full),
# 本腳本先確保沒有殘留的 clean 變體(以防上次 clean build 中斷未還原),再正常建置。
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "用法:tool/build_full.sh <target> [flutter build 參數...]"
  echo "  例:tool/build_full.sh macos --release"
  exit 1
fi

TARGET="$1"
shift || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="$PATH:$HOME/development/flutter/bin"

echo "→ 確保為 full 變體(還原可能殘留的 clean 改動)..."
git checkout -- pubspec.yaml \
  lib/alarm_facade/active_alarm_feature.dart \
  ios/Runner/Info.plist 2>/dev/null || true

echo "→ flutter clean + pub get..."
flutter clean
flutter pub get

case "$TARGET" in
  ios|macos)
    echo "→ 清 Pods 並重裝($TARGET)..."
    rm -rf "$TARGET/Pods" "$TARGET/Podfile.lock"
    export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
    ( cd "$TARGET" && pod install )
    ;;
esac

echo "→ flutter build $TARGET $*..."
flutter build "$TARGET" "$@"

echo "✅ full 版建置完成。"
