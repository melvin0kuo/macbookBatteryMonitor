#!/bin/bash
# ./build.sh [full|lite] [install]
# 未指定版本時使用分支的 .battery-variant。
set -euo pipefail
cd "$(dirname "$0")"

VARIANT="$(cat .battery-variant 2>/dev/null || echo full)"
INSTALL=false
for ARG in "$@"; do
    case "$ARG" in
        full|lite) VARIANT="$ARG" ;;
        install) INSTALL=true ;;
        *) echo "使用方式：./build.sh [full|lite] [install]" >&2; exit 2 ;;
    esac
done

APP_NAME="macbookBatteryMonitor"
DISPLAY_NAME="電池監控 Full"
BUNDLE_ID="com.kuan.batterymonitor"
SWIFT_FLAGS=(-c release)
if [[ "$VARIANT" == lite ]]; then
    APP_NAME="macbookBatteryMonitorLite"
    DISPLAY_NAME="電池監控 Lite"
    BUNDLE_ID="com.kuan.batterymonitor.lite"
    SWIFT_FLAGS=(-c release -Xswiftc -DBATTERY_LITE)
fi
APP="build/$APP_NAME.app"
SCRATCH=".build/$VARIANT"
swift build --scratch-path "$SCRATCH" "${SWIFT_FLAGS[@]}"
BIN="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)/macbookBatteryMonitor"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.2.0" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 3" "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
codesign --force --sign - --timestamp=none "$APP"
echo "✅ 已產生 $APP ($VARIANT)"

if [[ "$INSTALL" == true ]]; then
    pkill -x "$APP_NAME" || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "✅ 已安裝到 /Applications/$APP_NAME.app"
fi
