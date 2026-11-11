#!/bin/bash
# 打包发布版本：构建通用版 Tuck.app 并压缩成 dist/Tuck-<版本>.zip
# 用法：./scripts/release.sh            只打包
#       ./scripts/release.sh --publish  打包并创建 GitHub Release（tag = v<版本>）
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
UNIVERSAL=1 ./scripts/build-app.sh
mkdir -p dist
ZIP="dist/Tuck-$VERSION.zip"
rm -f "$ZIP"
# 用 ditto 压缩，保留签名和扩展属性
ditto -c -k --sequesterRsrc --keepParent build/Tuck.app "$ZIP"
echo "打包完成：$ZIP"
lipo -archs build/Tuck.app/Contents/MacOS/Tuck

if [ "${1:-}" = "--publish" ]; then
    gh release create "v$VERSION" "$ZIP" --title "Tuck $VERSION" --notes-file - <<NOTES
## 安装

1. 下载下面的 \`Tuck-$VERSION.zip\`，解压后把 **Tuck.app** 拖进「应用程序」。
2. 第一次打开：Tuck 没有经过 Apple 公证，macOS 会提示无法验证开发者。
   打开「系统设置 › 隐私与安全性」，在页面底部点「仍要打开」。
   或者在终端运行：\`xattr -dr com.apple.quarantine /Applications/Tuck.app\`
3. 在「系统设置 › 隐私与安全性 › 辅助功能」里允许 Tuck（用于识别和移动菜单栏图标）。

需要 macOS 14 或更高版本，支持 Apple 芯片和 Intel。
NOTES
fi
