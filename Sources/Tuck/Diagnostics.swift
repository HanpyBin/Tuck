import AppKit

/// 汇总诊断信息，方便用户在别的电脑上出问题时直接复制发过来
enum Diagnostics {
    static func report(controller: MenuBarController) -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        var arch = utsname(); uname(&arch)
        let machine = withUnsafeBytes(of: &arch.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        var lines = [
            "Tuck \(version)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString) \(machine)",
            "trusted=\(Accessibility.isTrusted) postEvent=\(CGPreflightPostEventAccess()) state=\(controller.state)",
        ]
        for (i, screen) in NSScreen.screens.enumerated() {
            let notch = screen.auxiliaryTopLeftArea.map { "notch \(Int($0.maxX))..\(Int(screen.auxiliaryTopRightArea?.minX ?? 0))" } ?? "no notch"
            lines.append("screen\(i) \(screen.frame) visible=\(screen.visibleFrame) \(notch)")
        }
        func f(_ item: NSStatusItem) -> String { item.button?.window.map { "\($0.frame)" } ?? "nil" }
        lines.append("control=\(f(controller.control)) hiddenSep=\(f(controller.hiddenSep)) alwaysSep=\(f(controller.alwaysSep))")
        lines.append("windows: " + MenuBarWindows.all(includeWide: true)
            .sorted { $0.frame.minX < $1.frame.minX }
            .map { "\($0.id)@\(Int($0.frame.minX)),\(Int($0.frame.minY)) w\(Int($0.frame.width))" }.joined(separator: " "))
        lines.append("-- items")
        for item in MenuBarScanner.scan(controller: controller) {
            lines.append("\(item.section.title)\t\(item.id)\t\(item.displayName)\tx=\(Int(item.frame.minX)) y=\(Int(item.frame.minY)) w=\(Int(item.frame.width))")
        }
        lines.append("-- move log")
        lines.append(contentsOf: ItemMover.log)
        return lines.joined(separator: "\n")
    }
}
