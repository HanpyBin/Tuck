#!/bin/bash
# 构建 Tuck.app 到 build/ 目录
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Tuck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Tuck "$APP/Contents/MacOS/Tuck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 使用稳定的签名标识，尽量避免每次重新构建后辅助功能授权失效
codesign --force --sign "${SIGN_IDENTITY:--}" --identifier io.github.hanpybin.Tuck "$APP"
echo "Built $APP"
