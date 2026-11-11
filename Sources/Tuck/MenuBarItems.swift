import AppKit
import ApplicationServices

enum BarSection: Int, CaseIterable, Identifiable {
    case visible, hidden, alwaysHidden
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .visible: return "常显"
        case .hidden: return "隐藏"
        case .alwaysHidden: return "始终隐藏"
        }
    }
}

/// 一个其他 App 的菜单栏图标
struct MenuBarItem: Identifiable {
    let id: String
    let pid: pid_t
    let bundleID: String
    let appName: String
    let title: String
    /// 全局坐标，原点在主屏左上角（与 CGWindow / CGEvent 一致）
    let frame: CGRect
    let section: BarSection
    /// 时钟、控制中心等系统固定的图标不能移动
    let movable: Bool

    var displayName: String {
        if title.isEmpty || title == appName { return appName }
        return "\(appName) · \(title)"
    }

    var icon: NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }
}

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

/// 通过辅助功能 API 枚举所有 App 的菜单栏图标。
/// （macOS 26 起菜单栏图标的窗口全部归「控制中心」所有，只能靠 AX 找到真正的 App。）
enum MenuBarScanner {
    private static let fixedIdentifiers: Set<String> = [
        "com.apple.menuextra.clock",
        "com.apple.menuextra.controlcenter",
    ]

    static func scan(controller: MenuBarController) -> [MenuBarItem] {
        guard Accessibility.isTrusted else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let hiddenMinX = controller.hiddenSep.button?.window?.frame.minX ?? .infinity
        let alwaysMinX = Settings.shared.alwaysHiddenEnabled
            ? (controller.alwaysSep.button?.window?.frame.minX ?? -.infinity)
            : -.infinity

        let windows = MenuBarWindows.all()
        // 只查询 .app（跳过网页内容等辅助进程，它们不响应 AX 会拖慢扫描），并发查询
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownPID && $0.bundleURL?.pathExtension == "app"
        }
        var perApp = [[MenuBarItem]](repeating: [], count: apps.count)
        perApp.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: apps.count) { i in
                buffer[i] = items(of: apps[i], windows: windows, hiddenMinX: hiddenMinX, alwaysMinX: alwaysMinX)
            }
        }
        let result = perApp.flatMap { $0 }
        // 菜单栏上从右到左的顺序
        return result.sorted { $0.frame.minX > $1.frame.minX }
    }

    private static func items(of app: NSRunningApplication, windows: [MenuBarWindows.Window],
                              hiddenMinX: CGFloat, alwaysMinX: CGFloat) -> [MenuBarItem] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        guard let bar: AXUIElement = attribute(axApp, "AXExtrasMenuBar"),
              let children: [AXUIElement] = attribute(bar, kAXChildrenAttribute) else { return [] }

        var result: [MenuBarItem] = []
        for (index, child) in children.enumerated() {
            // 没有对应窗口的图标实际上没显示（例如在「系统设置 › 菜单栏」里被关闭了）
            guard let frame = frame(of: child), frame.width > 0, frame.width < 1000,
                  MenuBarWindows.window(containingX: frame.midX, in: windows) != nil else { continue }
            let identifier: String = attribute(child, kAXIdentifierAttribute) ?? ""
            let desc: String = attribute(child, kAXDescriptionAttribute) ?? ""
            let title: String = attribute(child, kAXTitleAttribute) ?? ""
            let bundleID = app.bundleIdentifier ?? "pid\(app.processIdentifier)"

            let midX = frame.midX
            let section: BarSection = midX < alwaysMinX ? .alwaysHidden : (midX < hiddenMinX ? .hidden : .visible)

            result.append(MenuBarItem(
                id: identifier.isEmpty ? "\(bundleID)#\(index)" : identifier,
                pid: app.processIdentifier,
                bundleID: bundleID,
                appName: app.localizedName ?? bundleID,
                title: desc.isEmpty ? title : desc,
                frame: frame,
                section: section,
                movable: !fixedIdentifiers.contains(identifier)))
        }
        return result
    }

    // MARK: AX helpers

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &p)
        AXValueGetValue(size as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }
}

/// 菜单栏图标窗口（CG 坐标）。macOS 26 起这些窗口都归「控制中心」所有。
enum MenuBarWindows {
    typealias Window = (id: CGWindowID, frame: CGRect)

    /// includeWide：是否包含收起状态下超宽的分隔线窗口
    static func all(includeWide: Bool = false) -> [Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == statusLevel,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict),
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  // 排除弹出窗口和收起状态下超宽的分隔线
                  b.minY < 5, b.height < 60, includeWide || b.width < 1000 else { return nil }
            return (number, b)
        }
    }

    /// 找到与 Tuck 自己的状态栏窗口（NSWindow 坐标）对应的 CG 窗口 ID，包括收起时超宽的分隔线
    static func windowID(matching frame: NSRect) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        for info in list where (info[kCGWindowLayer as String] as? Int) == statusLevel {
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict),
                  abs(b.minX - frame.minX) < 2, abs(b.width - frame.width) < 2, b.minY < 5 else { continue }
            return info[kCGWindowNumber as String] as? CGWindowID
        }
        return nil
    }

    static func window(containingX x: CGFloat, in windows: [Window]? = nil) -> Window? {
        (windows ?? all()).filter { $0.frame.minX <= x && x < $0.frame.maxX }
            .min { $0.frame.width < $1.frame.width }
    }
}
