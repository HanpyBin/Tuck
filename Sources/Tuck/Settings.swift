import Foundation
import Combine
import Carbon.HIToolbox

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon 修饰键掩码
    var key: String         // 用于显示的按键字符

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    /// 默认：⌃⌥⌘B
    static let `default` = KeyCombo(
        keyCode: UInt32(kVK_ANSI_B),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        key: "B")
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var autoCollapse: Bool { didSet { defaults.set(autoCollapse, forKey: "autoCollapse") } }
    @Published var autoCollapseDelay: Double { didSet { defaults.set(autoCollapseDelay, forKey: "autoCollapseDelay") } }
    @Published var alwaysHiddenEnabled: Bool { didSet { defaults.set(alwaysHiddenEnabled, forKey: "alwaysHiddenEnabled") } }
    @Published var hotKeyEnabled: Bool { didSet { defaults.set(hotKeyEnabled, forKey: "hotKeyEnabled") } }
    @Published var hotKey: KeyCombo {
        didSet { defaults.set(try? JSONEncoder().encode(hotKey), forKey: "hotKey") }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }

    private init() {
        defaults.register(defaults: [
            "autoCollapse": true,
            "autoCollapseDelay": 10.0,
            "alwaysHiddenEnabled": true,
            "hotKeyEnabled": true,
        ])
        autoCollapse = defaults.bool(forKey: "autoCollapse")
        autoCollapseDelay = defaults.double(forKey: "autoCollapseDelay")
        alwaysHiddenEnabled = defaults.bool(forKey: "alwaysHiddenEnabled")
        hotKeyEnabled = defaults.bool(forKey: "hotKeyEnabled")
        if let data = defaults.data(forKey: "hotKey"),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            hotKey = combo
        } else {
            hotKey = .default
        }
    }
}
