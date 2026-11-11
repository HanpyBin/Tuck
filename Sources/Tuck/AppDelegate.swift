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
            default: break
            }
        }
    }

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(menuBar: menuBar)
        }
        settingsWindow?.show()
    }
}
