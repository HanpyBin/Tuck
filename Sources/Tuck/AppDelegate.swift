import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var settingsWindow: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        menuBar.onOpenSettings = { [weak self] in self?.openSettings() }

        let settings = Settings.shared
        HotKeyCenter.shared.action = { [weak self] in self?.menuBar.toggle() }

        settings.$hotKeyEnabled.combineLatest(settings.$hotKey)
            .sink { enabled, combo in HotKeyCenter.shared.register(enabled ? combo : nil) }
            .store(in: &cancellables)

        settings.$alwaysHiddenEnabled.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.menuBar.refresh() } }
            .store(in: &cancellables)
        settings.$autoCollapse.combineLatest(settings.$autoCollapseDelay).dropFirst()
            .sink { [weak self] _, _ in DispatchQueue.main.async { self?.menuBar.scheduleAutoCollapse() } }
            .store(in: &cancellables)

        if !settings.hasLaunchedBefore {
            settings.hasLaunchedBefore = true
            openSettings()
        }
    }

    /// tuck://toggle | show | show-all | hide | settings
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "tuck" {
            switch url.host {
            case "toggle": menuBar.toggle()
            case "show": menuBar.apply(.expanded)
            case "show-all": menuBar.apply(.expandedAll)
            case "hide": menuBar.apply(.collapsed)
            case "settings": openSettings()
            case "dump": dumpItems()
            case "move": moveItem(url)
            case "place": placeItem(url)
            case "drop": dropItem(url)
            case "snapshot": snapshotSettings()
            default: break
            }
        }
    }

    private var lastMoveResult = "-"

    static var dumpURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.hanpybin.Tuck/items.txt")
    }

    /// 把当前识别到的菜单栏图标写到缓存目录，方便排查问题
    private func dumpItems() {
        var lines = ["trusted=\(Accessibility.isTrusted) state=\(menuBar.state) lastMove=\(lastMoveResult)"]
        for item in MenuBarScanner.scan(controller: menuBar) {
            lines.append("\(item.section.title)\t\(item.id)\t\(item.displayName)\tx=\(Int(item.frame.minX)) w=\(Int(item.frame.width))")
        }
        lines.append("==== diagnostics")
        lines.append(Diagnostics.report(controller: menuBar))
        let url = Self.dumpURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// tuck://move?id=<图标 id>&to=visible|hidden|always
    private func moveItem(_ url: URL) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let id = query.first(where: { $0.name == "id" })?.value,
              let to = query.first(where: { $0.name == "to" })?.value,
              let item = MenuBarScanner.scan(controller: menuBar).first(where: { $0.id == id }) else {
            lastMoveResult = "not found: \(url.absoluteString)"
            dumpItems()
            return
        }
        let section: BarSection = to == "visible" ? .visible : (to == "always" ? .alwaysHidden : .hidden)
        ItemMover.move(item, to: section, controller: menuBar) { [weak self] result in
            switch result {
            case .success: self?.lastMoveResult = "ok \(id) -> \(to)"
            case .failure(let error): self?.lastMoveResult = "failed \(id) -> \(to): \(error.localizedDescription)"
            }
            self?.dumpItems()
        }
    }

    /// tuck://place?id=<图标 id>&left-of=<图标 id>  或  &right-of=<图标 id>
    private func placeItem(_ url: URL) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ n: String) -> String? { query.first(where: { $0.name == n })?.value }
        let items = MenuBarScanner.scan(controller: menuBar)
        let side: ItemMover.Side = value("left-of") != nil ? .left : .right
        guard let id = value("id"), let anchorID = value("left-of") ?? value("right-of"),
              let item = items.first(where: { $0.id == id }),
              let anchor = items.first(where: { $0.id == anchorID }) else {
            lastMoveResult = "not found: \(url.absoluteString)"
            dumpItems()
            return
        }
        ItemMover.place(item, side, of: anchor, controller: menuBar) { [weak self] result in
            switch result {
            case .success: self?.lastMoveResult = "ok \(id) \(side) of \(anchorID)"
            case .failure(let error): self?.lastMoveResult = "failed \(id): \(error.localizedDescription)"
            }
            self?.dumpItems()
        }
    }

    /// tuck://drop?id=<图标 id>&zone=visible|hidden|always&index=<从左往右的位置>
    private func dropItem(_ url: URL) {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ n: String) -> String? { query.first(where: { $0.name == n })?.value }
        let items = MenuBarScanner.scan(controller: menuBar)
        guard let id = value("id"), let item = items.first(where: { $0.id == id }),
              let index = value("index").flatMap(Int.init) else {
            lastMoveResult = "not found: \(url.absoluteString)"; dumpItems(); return
        }
        let zone = value("zone")
        let section: BarSection = zone == "visible" ? .visible : (zone == "always" ? .alwaysHidden : .hidden)
        ItemMover.drop(item, into: section, at: index, items: items, controller: menuBar) { [weak self] result in
            switch result {
            case .success: self?.lastMoveResult = "ok drop \(id) \(section) #\(index)"
            case .failure(let error): self?.lastMoveResult = "failed \(id): \(error.localizedDescription)"
            }
            self?.dumpItems()
        }
    }

    /// 调试用：把设置窗口当前内容保存成 PNG（不需要屏幕录制权限）
    private func snapshotSettings() {
        guard let view = settingsWindow?.window?.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = Self.dumpURL.deletingLastPathComponent().appendingPathComponent("settings.png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(menuBar: menuBar)
        }
        settingsWindow?.show()
    }
}
