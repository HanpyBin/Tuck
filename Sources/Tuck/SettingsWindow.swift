import AppKit
import SwiftUI
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    convenience init(menuBar: MenuBarController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Tuck 设置"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(menuBar: menuBar))
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let menuBar: MenuBarController

    var body: some View {
        TabView {
            ItemsView(controller: menuBar)
                .tabItem { Label("菜单栏图标", systemImage: "menubar.rectangle") }
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
            HelpView()
                .tabItem { Label("使用说明", systemImage: "questionmark.circle") }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 520)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("启动") {
                Toggle("登录时自动启动 Tuck", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section("隐藏") {
                Toggle("展开后自动收起", isOn: $settings.autoCollapse)
                if settings.autoCollapse {
                    HStack {
                        Slider(value: $settings.autoCollapseDelay, in: 3...60, step: 1)
                        Text("\(Int(settings.autoCollapseDelay)) 秒").monospacedDigit().frame(width: 50)
                    }
                }
                Toggle("启用「始终隐藏」区域（⌥ 单击 Tuck 图标才显示）", isOn: $settings.alwaysHiddenEnabled)
            }
            Section("快捷键") {
                Toggle("使用全局快捷键展开/收起", isOn: $settings.hotKeyEnabled)
                if settings.hotKeyEnabled {
                    HStack {
                        Text("快捷键")
                        Spacer()
                        HotKeyRecorder(combo: $settings.hotKey)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "设置失败：\(error.localizedDescription)（需要从 Tuck.app 运行）"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// 点击后按下新的组合键即可录制
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "请按下快捷键…（Esc 取消）" : combo.displayString) {
            recording ? stop() : start()
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyCenter.shared.register(nil) // 录制时先注销，避免触发
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Esc
            let mods = HotKeyCenter.carbonModifiers(from: event.modifierFlags)
            guard mods != 0 else { NSSound.beep(); return nil } // 至少要一个修饰键
            let key = (event.charactersIgnoringModifiers ?? "?").uppercased()
            combo = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods, key: key)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            let s = Settings.shared
            HotKeyCenter.shared.register(s.hotKeyEnabled ? s.hotKey : nil)
        }
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tuck 在菜单栏放了三个东西（从右往左）：").bold()
                Text("‹  Tuck 图标：单击展开/收起；⌥ 单击显示全部；右键打开菜单")
                Text("│  隐藏分隔线：它左边的图标平时被收起")
                Text("┊  始终隐藏分隔线：它左边的图标只有 ⌥ 单击时才显示")
                Divider()
                Text("调整图标所在区域").bold()
                Text("按住 ⌘ 拖动菜单栏图标，把它放到对应分隔线的左边或右边即可。")
                Text("最终布局：[始终隐藏] ┊ [隐藏] │ [常显] ‹")
                    .font(.system(.body, design: .monospaced))
                Divider()
                Text("刘海屏提示").bold()
                Text("刘海会挡住菜单栏中间的一段，展开后图标太多时，左边的图标仍可能被刘海挡住或被系统省略。把不常用的图标放进「始终隐藏」区域可以缓解。")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}
