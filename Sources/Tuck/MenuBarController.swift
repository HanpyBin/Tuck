import AppKit

/// 管理 Tuck 自己的三个状态栏项目：
///
///   [始终隐藏区] ┊ [隐藏区] │ [常显区] ‹Tuck›
///                ↑ alwaysSep  ↑ hiddenSep        ↑ control
///
/// 收起时把分隔符的长度设为一个很大的值，把它左边的图标全部挤出屏幕。
final class MenuBarController: NSObject {
    enum State { case collapsed, expanded, expandedAll }

    static let hugeLength: CGFloat = 10_000

    let control: NSStatusItem
    let hiddenSep: NSStatusItem
    let alwaysSep: NSStatusItem

    private(set) var state: State = .expanded
    private var collapseTimer: Timer?
    private let settings = Settings.shared
    private var warnedAboutOrder = false
    /// 移动图标等操作期间暂停自动收起
    var suspendAutoCollapse = false { didSet { scheduleAutoCollapse() } }

    var onOpenSettings: (() -> Void)?

    override init() {
        // 首次启动时把 Tuck 图标和「│」放到最右边（数值是距屏幕右边缘的距离）。
        // 否则在图标很多的刘海屏上，新图标会被排到最左边、藏在刘海后面看不见。
        // 「┊」不预设，会出现在最左边，因此一开始没有图标处于「始终隐藏」区。
        Self.seedPosition("tuck.control", 0)
        Self.seedPosition("tuck.hiddenSeparator", 1)

        control = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        control.autosaveName = "tuck.control"
        hiddenSep = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        hiddenSep.autosaveName = "tuck.hiddenSeparator"
        alwaysSep = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        alwaysSep.autosaveName = "tuck.alwaysHiddenSeparator"
        super.init()

        if let button = control.button {
            button.target = self
            button.action = #selector(controlClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Tuck：单击展开/收起，⌥单击显示全部，右键打开菜单"
        }
        hiddenSep.button?.image = Self.dividerImage(dashed: false)
        hiddenSep.button?.toolTip = "Tuck 分隔线：左边的图标会被隐藏（⌘拖动图标来调整）"
        alwaysSep.button?.image = Self.dividerImage(dashed: true)
        alwaysSep.button?.toolTip = "Tuck 分隔线：左边的图标始终隐藏，⌥单击 Tuck 才显示"

        // 等状态栏布局完成后再收起
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.apply(.collapsed)
        }
        refresh()
    }

    private static func seedPosition(_ autosaveName: String, _ value: CGFloat) {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    // MARK: - 状态切换

    func toggle() {
        apply(state == .collapsed ? .expanded : .collapsed)
    }

    func refresh() { apply(state) }

    func apply(_ newState: State) {
        let ahEnabled = settings.alwaysHiddenEnabled
        alwaysSep.isVisible = ahEnabled

        if newState == .collapsed, let problem = orderProblem() {
            // 顺序不对时收起会把 Tuck 自己也藏掉，拒绝收起
            state = .expanded
            setSeparator(hiddenSep, hidden: false)
            if ahEnabled { setSeparator(alwaysSep, hidden: false) }
            updateControlImage()
            warnOrder(problem)
            return
        }

        state = newState
        switch newState {
        case .collapsed:
            setSeparator(hiddenSep, hidden: true)
            if ahEnabled { setSeparator(alwaysSep, hidden: true) }
        case .expanded:
            setSeparator(hiddenSep, hidden: false)
            if ahEnabled { setSeparator(alwaysSep, hidden: true) }
        case .expandedAll:
            setSeparator(hiddenSep, hidden: false)
            if ahEnabled { setSeparator(alwaysSep, hidden: false) }
        }
        updateControlImage()
        scheduleAutoCollapse()
    }

    private func setSeparator(_ item: NSStatusItem, hidden: Bool) {
        if hidden {
            item.length = Self.hugeLength
        } else {
            item.length = NSStatusItem.variableLength
        }
        item.button?.isHidden = hidden
    }

    private func updateControlImage() {
        let name = state == .collapsed ? "chevron.left" : "chevron.right"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Tuck")
        image?.isTemplate = true
        control.button?.image = image
    }

    // MARK: - 位置校验

    /// 状态栏项目的右边缘（不受长度变化影响）
    func rightEdge(of item: NSStatusItem) -> CGFloat? {
        guard let w = item.button?.window, w.frame.width > 0 else { return nil }
        return w.frame.maxX
    }

    private func orderProblem() -> String? {
        guard let c = rightEdge(of: control), let h = rightEdge(of: hiddenSep) else { return nil }
        if h >= c {
            return "隐藏分隔线「│」跑到了 Tuck 图标的右边。请按住 ⌘ 把「│」拖到 Tuck 图标（‹）的左边。"
        }
        if settings.alwaysHiddenEnabled, let a = rightEdge(of: alwaysSep), a >= h {
            return "始终隐藏分隔线「┊」跑到了「│」的右边。请按住 ⌘ 把「┊」拖到「│」的左边。"
        }
        return nil
    }

    private func warnOrder(_ message: String) {
        guard !warnedAboutOrder else { return }
        warnedAboutOrder = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Tuck 分隔线位置不对"
        alert.informativeText = message
        alert.runModal()
        warnedAboutOrder = false
    }

    // MARK: - 自动收起

    func scheduleAutoCollapse() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        guard state != .collapsed, settings.autoCollapse, !suspendAutoCollapse else { return }
        collapseTimer = Timer.scheduledTimer(withTimeInterval: max(1, settings.autoCollapseDelay),
                                             repeats: false) { [weak self] _ in
            self?.autoCollapseFired()
        }
    }

    private func autoCollapseFired() {
        // 鼠标还在菜单栏上，或者有菜单正开着时，稍后再试
        if Self.isMouseInMenuBar() || Self.isMenuOpen() {
            collapseTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                self?.autoCollapseFired()
            }
            return
        }
        apply(.collapsed)
    }

    static func isMouseInMenuBar() -> Bool {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return p.y >= screen.frame.maxY - barHeight
    }

    static func isMenuOpen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return list.contains { ($0[kCGWindowLayer as String] as? Int) == menuLevel }
    }

    // MARK: - 点击

    @objc private func controlClicked() {
        guard let event = NSApp.currentEvent else { toggle(); return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else if event.modifierFlags.contains(.option) {
            apply(state == .expandedAll ? .collapsed : .expandedAll)
        } else {
            toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let toggleTitle = state == .collapsed ? "展开隐藏的图标" : "收起"
        menu.addItem(withTitle: toggleTitle, action: #selector(menuToggle), keyEquivalent: "").target = self
        if settings.alwaysHiddenEnabled {
            menu.addItem(withTitle: "显示全部（含始终隐藏）", action: #selector(menuShowAll), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Tuck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        control.menu = menu
        control.button?.performClick(nil)
        control.menu = nil
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuShowAll() { apply(.expandedAll) }
    @objc private func menuSettings() { onOpenSettings?() }

    // MARK: - 图片

    static func dividerImage(dashed: Bool) -> NSImage {
        let size = NSSize(width: 12, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX, y: 1))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 1))
            path.lineWidth = 1.5
            if dashed { path.setLineDash([2, 2], count: 2, phase: 0) }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
