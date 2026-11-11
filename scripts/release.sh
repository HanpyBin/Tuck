#!/bin/bash
# 打包发布版本：构建通用版 Tuck.app 并打包成 dist/Tuck-<版本>.dmg
# 用法：./scripts/release.sh            只打包
#       ./scripts/release.sh --publish  打包并创建 GitHub Release（tag = v<版本>）
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
UNIVERSAL=1 ./scripts/build-app.sh
mkdir -p dist
DMG="dist/Tuck-$VERSION.dmg"
rm -f "$DMG"
# 准备 DMG 内容：Tuck.app + 指向「应用程序」的快捷方式，用户直接拖过去即可安装
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir "$STAGE"
ditto build/Tuck.app "$STAGE/Tuck.app"
ln -s /Applications "$STAGE/Applications"
# 卷图标（挂载后在桌面/访达侧栏显示 Tuck 图标）
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"
if command -v SetFile >/dev/null; then SetFile -c icnC "$STAGE/.VolumeIcon.icns"; fi
hdiutil create -volname "Tuck $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg" >/dev/null
# 打开卷的自定义图标标记
MNT=$(hdiutil attach -nobrowse -noautoopen "$WORK/rw.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}')
if command -v SetFile >/dev/null; then SetFile -a C "$MNT"; fi
hdiutil detach "$MNT" -quiet
hdiutil convert "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
echo "打包完成：$DMG"
lipo -archs build/Tuck.app/Contents/MacOS/Tuck

if [ "${1:-}" = "--publish" ]; then
    gh release create "v$VERSION" "$DMG" --title "Tuck $VERSION" --notes-file - <<NOTES
## 安装

1. 下载下面的 \`Tuck-$VERSION.dmg\`，双击打开，把 **Tuck** 拖到旁边的「Applications」文件夹。
2. 第一次打开：Tuck 没有经过 Apple 公证，macOS 会提示无法验证开发者。
   打开「系统设置 › 隐私与安全性」，在页面底部点「仍要打开」。
   或者在终端运行：\`xattr -dr com.apple.quarantine /Applications/Tuck.app\`
3. 在「系统设置 › 隐私与安全性 › 辅助功能」里允许 Tuck（用于识别和移动菜单栏图标）。

需要 macOS 14 或更高版本，支持 Apple 芯片和 Intel。
NOTES
fi
