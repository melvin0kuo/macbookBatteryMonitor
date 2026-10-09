#!/bin/bash
# 編譯並打包成 BatteryMonitor.app
#   ./build.sh          → build/BatteryMonitor.app
#   ./build.sh install  → 另外安裝到 /Applications 並啟動
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BatteryMonitor"
APP="build/$APP_NAME.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - --timestamp=none "$APP"
echo "✅ 已產生 $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x "$APP_NAME" || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "✅ 已安裝到 /Applications/$APP_NAME.app"
fi
