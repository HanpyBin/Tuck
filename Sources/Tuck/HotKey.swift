import AppKit
import Carbon.HIToolbox

/// 基于 Carbon 的全局快捷键（无需辅助功能权限）
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func register(_ combo: KeyCombo?) {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        installHandlerIfNeeded()
        guard let combo else { return }
        let id = EventHotKeyID(signature: OSType(0x5455_434B), id: 1) // 'TUCK'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("Tuck: 注册快捷键失败 \(status)") }
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKeyCenter.shared.action?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }
}
