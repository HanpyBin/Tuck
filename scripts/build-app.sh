#!/bin/bash
# 构建 Tuck.app 到 build/ 目录
set -euo pipefail
cd "$(dirname "$0")/.."
# UNIVERSAL=1 时同时构建 Apple 芯片和 Intel 版本（发布用）
if [ "${UNIVERSAL:-0}" = "1" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN=.build/apple/Products/Release/Tuck
else
    swift build -c release
    BIN=.build/release/Tuck
fi
APP=build/Tuck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tuck"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 使用稳定的签名标识，尽量避免每次重新构建后辅助功能授权失效
codesign --force --sign "${SIGN_IDENTITY:--}" --identifier io.github.hanpybin.Tuck "$APP"
echo "Built $APP"
