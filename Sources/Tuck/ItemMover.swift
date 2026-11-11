import AppKit

/// 通过模拟 ⌘ 拖动来移动菜单栏图标。
///
/// 事件直接投递给图标所在的窗口（设置 windowUnderMousePointer 等字段），
/// 不需要真的移动鼠标，所以即使图标被刘海挡住或在屏幕外也能移动。
enum ItemMover {
    enum MoveError: LocalizedError {
        case notTrusted, notMovable, busy, sourceNotFound, separatorNotFound, verifyFailed
        var errorDescription: String? {
            switch self {
            case .notTrusted: return "需要先在「系统设置 › 隐私与安全性 › 辅助功能」中允许 Tuck。"
            case .busy: return "上一个移动操作还没完成。"
            case .notMovable: return "这个图标由系统固定，不能移动。"
            case .sourceNotFound: return "找不到这个图标的窗口（它可能已经被系统省略）。"
            case .separatorNotFound: return "找不到 Tuck 的分隔线。"
            case .verifyFailed: return "移动后位置没有变化，请再试一次或手动 ⌘ 拖动。"
            }
        }
    }

    /// 同一时间只允许一个移动操作
    private(set) static var isMoving = false

    /// 窗口 ID 字段（未公开，0x33）
    private static let windowIDField = CGEventField(rawValue: 0x33)!

    static func move(_ item: MenuBarItem, to section: BarSection, controller: MenuBarController,
                     completion: @escaping (Result<Void, Error>) -> Void) {
        guard Accessibility.isTrusted else { return completion(.failure(MoveError.notTrusted)) }
        guard item.movable else { return completion(.failure(MoveError.notMovable)) }
        guard section != item.section else { return completion(.success(())) }
        guard !isMoving else { return completion(.failure(MoveError.busy)) }
        isMoving = true

        // 在「收起」状态下操作：此时每个图标都有窗口（隐藏的在屏幕外），
        // 而全部展开时放不下的图标会被系统直接省略，反而找不到。
        let previousState = controller.state
        controller.suspendAutoCollapse = true
        controller.apply(.collapsed)

        func finish(_ result: Result<Void, Error>) {
            isMoving = false
            controller.apply(previousState)
            controller.suspendAutoCollapse = false
            completion(result)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let windows = MenuBarWindows.all()
            guard let current = MenuBarScanner.scan(controller: controller).first(where: { $0.id == item.id }),
                  let source = MenuBarWindows.window(containingX: current.frame.midX, in: windows) else {
                return finish(.failure(MoveError.sourceNotFound))
            }

            let separator = section == .alwaysHidden ? controller.alwaysSep : controller.hiddenSep
            guard let sepFrame = separator.button?.window?.frame,
                  let targetID = MenuBarWindows.windowID(matching: sepFrame) else {
                return finish(.failure(MoveError.separatorNotFound))
            }

            // 落在分隔线最左端 → 放到它左边；最右端 → 放到它右边。
            // 收起状态下分隔线很宽，左端在屏幕外，但事件是直接发给窗口的，不受影响。
            let dropX = section == .visible ? sepFrame.maxX - 3 : sepFrame.minX + 3
            let y = source.frame.midY

            DispatchQueue.global(qos: .userInitiated).async {
                postCommandDrag(from: CGPoint(x: source.frame.midX, y: y), sourceWindow: source.id,
                                to: CGPoint(x: dropX, y: y), targetWindow: targetID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let moved = MenuBarScanner.scan(controller: controller).first(where: { $0.id == item.id })
                    finish(moved?.section == section ? .success(()) : .failure(MoveError.verifyFailed))
                }
            }
        }
    }

    private static func postCommandDrag(from start: CGPoint, sourceWindow: CGWindowID,
                                        to end: CGPoint, targetWindow: CGWindowID) {
        let source = CGEventSource(stateID: .hidSystemState)
        let savedCursor = CGEvent(source: nil)?.location

        func post(_ type: CGEventType, _ point: CGPoint, _ window: CGWindowID) {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                      mouseCursorPosition: point, mouseButton: .left) else { return }
            event.flags = .maskCommand
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
            event.setIntegerValueField(windowIDField, value: Int64(window))
            event.post(tap: .cgSessionEventTap)
        }

        post(.leftMouseDown, start, sourceWindow)
        usleep(100_000)
        post(.leftMouseUp, end, targetWindow)
        usleep(100_000)
        if let savedCursor { CGWarpMouseCursorPosition(savedCursor) }
    }
}
