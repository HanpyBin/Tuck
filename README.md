<p align="center"><img src="docs/icon.png" width="128" alt="Tuck icon"></p>

<h1 align="center">Tuck</h1>

一个 macOS 菜单栏（状态栏）图标管理工具：只把你关心的图标留在菜单栏上，其余的收起来。专门考虑了刘海屏菜单栏空间不够的问题。

## 布局

```
[始终隐藏区] ┊ [隐藏区] │ [常显区] ‹Tuck›  控制中心  时钟
```

- **‹ Tuck 图标**：单击展开/收起；⌥ 单击显示全部（含始终隐藏区）；右键打开菜单
- **│ 隐藏分隔线**：左边的图标平时收起
- **┊ 始终隐藏分隔线**：左边的图标只有 ⌥ 单击时才显示

按住 ⌘ 拖动任意菜单栏图标即可改变它所在的区域。

## 功能

- **在设置里直接选择每个图标放在哪个区域**（常显 / 隐藏 / 始终隐藏），Tuck 会自动帮你移动，不用手动 ⌘ 拖。
  即使图标被刘海挡住或在屏幕外也能移动。需要「辅助功能」权限。
- **调整图标顺序**：在设置里上下拖动、点 ←/→，或右键「移到最右 / 移到最左」。列表从上到下对应菜单栏从右到左。
- 常显区图标太多、超出刘海右侧空间时给出提示
- 展开后自动收起（鼠标在菜单栏上或有菜单打开时不会收起）
- 全局快捷键（默认 ⌃⌥⌘B，可在设置中录制）
- 登录时启动
- URL scheme（可配合 Raycast / 快捷指令）：
  - `tuck://toggle`、`tuck://show`、`tuck://show-all`、`tuck://hide`、`tuck://settings`
  - `tuck://move?id=<图标ID>&to=visible|hidden|always`
  - `tuck://place?id=<图标ID>&left-of=<图标ID>`（或 `right-of=`）：调整顺序
  - `tuck://dump`：把识别到的图标列表写到 `~/Library/Caches/io.github.hanpybin.Tuck/items.txt`（图标 ID 也在里面）
- 分隔线位置不对时拒绝收起，避免把 Tuck 自己藏掉

## 下载安装

到 [Releases](../../releases) 下载最新的 `Tuck-x.y.z.dmg`，双击打开，把 Tuck 拖到「Applications」文件夹。
Tuck 没有经过 Apple 公证，第一次打开时到「系统设置 › 隐私与安全性」底部点「仍要打开」，
或在终端运行 `xattr -dr com.apple.quarantine /Applications/Tuck.app`。

## 构建

需要 macOS 14+ 和 Xcode / Swift 5.9+。

```bash
./scripts/install.sh   # 构建、安装到 /Applications 并启动
```

只想构建不安装：`./scripts/build-app.sh`，产物在 `build/Tuck.app`。

> 请先退出 Hidden Bar 等同类软件，两者同时运行会互相干扰。

## 实现说明

- 收起：把分隔线的长度设为 10000，左边的图标被挤出屏幕（与 Hidden Bar 相同的原理）。
- 识别图标：macOS 26 起所有菜单栏图标窗口都归「控制中心」所有，无法从窗口列表看出属于哪个 App，
  因此用辅助功能 API（`AXExtrasMenuBar`）读取每个 App 的菜单栏图标。
- 移动图标：在收起状态下（此时每个图标都有窗口），向图标窗口直接投递带 ⌘ 的鼠标按下/抬起事件，
  落点在分隔线的最左端或最右端。事件直接发给窗口，所以不需要图标在屏幕上可见。

## 已知限制

- 本地构建使用 ad-hoc 签名，每次重新构建后可能需要在「系统设置 › 隐私与安全性 › 辅助功能」里重新勾选 Tuck。
- 在「系统设置 › 菜单栏」中被关闭的图标不会出现在列表中。

## 图标

图标由 `scripts/make-icon.swift` 用代码绘制。修改后重新生成：

```bash
swift scripts/make-icon.swift /tmp/tuck-icon
iconutil -c icns /tmp/tuck-icon/AppIcon.iconset -o Resources/AppIcon.icns
```

## 发布新版本

1. 修改 `Resources/Info.plist` 里的 `CFBundleShortVersionString`
2. `./scripts/release.sh --publish`（构建通用版、打包 DMG、创建 GitHub Release）
