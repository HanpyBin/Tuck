import AppKit

/// 通过模拟 ⌘ 拖动来移动菜单栏图标。
///
/// 事件直接投递给图标所在的窗口（设置 windowUnderMousePointer 等字段），
/// 不需要真的移动鼠标，所以即使图标被刘海挡住或在屏幕外也能移动。
enum ItemMover {
    enum MoveError: LocalizedError {
        case notTrusted, notMovable, busy, sourceNotFound, separatorNotFound, anchorNotFound, verifyFailed, notReachable
        var errorDescription: String? {
            switch self {
            case .notTrusted: return "需要先在「系统设置 › 隐私与安全性 › 辅助功能」中允许 Tuck。"
            case .busy: return "上一个移动操作还没完成。"
            case .notMovable: return "这个图标由系统固定，不能移动。"
            case .sourceNotFound: return "找不到这个图标的窗口（它可能已经被系统省略）。"
            case .anchorNotFound: return "找不到要参照的那个图标。"
            case .separatorNotFound: return "找不到 Tuck 的分隔线。"
            case .verifyFailed: return "移动后位置没有变化。请在「通用」页点「复制诊断信息」发给开发者，暂时可手动 ⌘ 拖动。"
            case .notReachable: return "这个图标或目标位置被刘海挡住，在这台电脑上无法自动移动，请先把挡住它的图标挪开或手动 ⌘ 拖动。"
            }
        }
    }

    /// 同一时间只允许一个移动操作
    private(set) static var isMoving = false

    /// 最近几次移动的过程记录，用于诊断
    private(set) static var log: [String] = []
    static func record(_ line: String) {
        log.append(line)
        if log.count > 40 { log.removeFirst(log.count - 40) }
    }

    /// 窗口 ID 字段（未公开，0x33）
    private static let windowIDField = CGEventField(rawValue: 0x33)!

    /// 把图标移到另一个区域
    static func move(_ item: MenuBarItem, to section: BarSection, controller: MenuBarController,
                     completion: @escaping (Result<Void, Error>) -> Void) {
        guard section != item.section else { return completion(.success(())) }
        perform(item, controller: controller, completion: completion,
                dropTarget: { _, _ in
                    let separator = section == .alwaysHidden ? controller.alwaysSep : controller.hiddenSep
                    guard let sepFrame = separator.button?.window?.frame,
                          let targetID = MenuBarWindows.windowID(matching: sepFrame) else {
                        throw MoveError.separatorNotFound
                    }
                    // 落在分隔线最左端 → 放到它左边；最右端 → 放到它右边。
                    // 收起状态下分隔线很宽，左端在屏幕外，但事件是直接发给窗口的，不受影响。
                    return (targetID, section == .visible ? sepFrame.maxX - 3 : sepFrame.minX + 3)
                },
                verify: { moved, _ in moved.section == section })
    }

    enum Side { case left, right }

    /// 把图标放到同一区域内另一个图标的左边或右边（用于调整顺序）
    static func place(_ item: MenuBarItem, _ side: Side, of anchor: MenuBarItem, controller: MenuBarController,
                      completion: @escaping (Result<Void, Error>) -> Void) {
        guard anchor.id != item.id else { return completion(.success(())) }
        perform(item, controller: controller, completion: completion,
                dropTarget: { items, windows in
                    guard let a = items.first(where: { $0.id == anchor.id }),
                          let w = MenuBarWindows.window(containingX: a.frame.midX, in: windows) else {
                        throw MoveError.anchorNotFound
                    }
                    // 实测「落在某个窗口右端 → 放到它右边」很可靠，而「落在左端」对部分图标无效。
                    // 所以「放到 A 左边」改成「放到 A 左边紧挨着的那个窗口的右边」。
                    if side == .left,
                       let leftNeighbor = MenuBarWindows.all(includeWide: true)
                           .first(where: { abs($0.frame.maxX - w.frame.minX) < 2 }) {
                        return (leftNeighbor.id, leftNeighbor.frame.maxX - 3)
                    }
                    return (w.id, side == .left ? w.frame.minX + 3 : w.frame.maxX - 3)
                },
                verify: { moved, items in
                    guard let a = items.first(where: { $0.id == anchor.id }) else { return false }
                    // 两者之间不能隔着别的图标
                    let between = items.filter {
                        $0.id != item.id && $0.id != anchor.id &&
                        min(moved.frame.midX, a.frame.midX) < $0.frame.midX &&
                        $0.frame.midX < max(moved.frame.midX, a.frame.midX)
                    }
                    let onSide = side == .left ? moved.frame.midX < a.frame.midX : moved.frame.midX > a.frame.midX
                    return onSide && between.isEmpty
                })
    }

    /// 通用流程：收起 → 找到源窗口和落点 → 模拟 ⌘ 拖动 → 校验
    private static func perform(_ item: MenuBarItem, controller: MenuBarController,
                                completion: @escaping (Result<Void, Error>) -> Void,
                                dropTarget: @escaping ([MenuBarItem], [MenuBarWindows.Window]) throws -> (CGWindowID, CGFloat),
                                verify: @escaping (MenuBarItem, [MenuBarItem]) -> Bool) {
        guard Accessibility.isTrusted else { return completion(.failure(MoveError.notTrusted)) }
        guard item.movable else { return completion(.failure(MoveError.notMovable)) }
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
            let items = MenuBarScanner.scan(controller: controller)
            guard let current = items.first(where: { $0.id == item.id }),
                  let source = MenuBarWindows.window(containingX: current.frame.midX, in: windows) else {
                return finish(.failure(MoveError.sourceNotFound))
            }
            let target: (CGWindowID, CGFloat)
            do { target = try dropTarget(items, windows) } catch { return finish(.failure(error)) }
            let y = source.frame.midY
            record("[1] \(item.id) src win=\(source.id) x=\(Int(source.frame.midX)) -> win=\(target.0) x=\(Int(target.1))")

            DispatchQueue.global(qos: .userInitiated).async {
                // 测试用：TUCK_FORCE_FALLBACK=1 时跳过方案 1
                if ProcessInfo.processInfo.environment["TUCK_FORCE_FALLBACK"] != "1" {
                    postCommandDrag(from: CGPoint(x: source.frame.midX, y: y), sourceWindow: source.id,
                                    to: CGPoint(x: target.1, y: y), targetWindow: target.0)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if check() { return finish(.success(())) }
                    record("[1] 未生效，改用真实光标拖动")
                    fallbackCursorDrag()
                }
            }
        }

        func check() -> Bool {
            let after = MenuBarScanner.scan(controller: controller)
            guard let moved = after.first(where: { $0.id == item.id }) else { return false }
            return verify(moved, after)
        }

        /// 方案 2：展开菜单栏，真的移动光标做一次 ⌘ 拖动（和用户手动操作一样）。
        /// 某些 macOS 版本 / 显示器配置下，方案 1 直接投递给窗口的事件会被忽略。
        /// 限制：起点和落点都必须在屏幕上看得见（不能被刘海挡住）。
        func fallbackCursorDrag() {
            controller.apply(.expandedAll)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let windows = MenuBarWindows.all()
                let items = MenuBarScanner.scan(controller: controller)
                guard let current = items.first(where: { $0.id == item.id }),
                      let source = MenuBarWindows.window(containingX: current.frame.midX, in: windows),
                      let target = try? dropTarget(items, windows) else {
                    record("[2] 展开后找不到图标或落点")
                    return finish(.failure(MoveError.verifyFailed))
                }
                let start = CGPoint(x: source.frame.midX, y: source.frame.midY)
                let end = CGPoint(x: target.1, y: source.frame.midY)
                record("[2] cursor \(Int(start.x)) -> \(Int(end.x)) reachable=\(isReachable(start.x)),\(isReachable(end.x))")
                guard isReachable(start.x), isReachable(end.x) else {
                    return finish(.failure(MoveError.notReachable))
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    postCursorDrag(from: start, to: end)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        let ok = check()
                        record("[2] \(ok ? "成功" : "仍未生效")")
                        finish(ok ? .success(()) : .failure(MoveError.verifyFailed))
                    }
                }
            }
        }
    }

    /// 某个 x 坐标在菜单栏上是否可见可点（在屏幕内且不在刘海里）
    private static func isReachable(_ x: CGFloat) -> Bool {
        guard let screen = NSScreen.screens.first, x > screen.frame.minX + 2, x < screen.frame.maxX - 2 else { return false }
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea, x > l.maxX, x < r.minX {
            return false
        }
        return true
    }

    /// 真实光标的 ⌘ 拖动（经由 HID 事件流，和物理鼠标完全一样）
    private static func postCursorDrag(from start: CGPoint, to end: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        let savedCursor = CGEvent(source: nil)?.location
        func mouse(_ type: CGEventType, _ p: CGPoint) {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p,
                                  mouseButton: .left) else { return }
            e.flags = .maskCommand
            e.post(tap: .cghidEventTap)
        }
        func command(_ down: Bool) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: down) else { return }
            e.flags = down ? .maskCommand : []
            e.post(tap: .cghidEventTap)
        }
        command(true)
        mouse(.mouseMoved, start); usleep(50_000)
        mouse(.leftMouseDown, start); usleep(150_000)
        for i in 1...20 {
            let t = CGFloat(i) / 20
            mouse(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y))
            usleep(15_000)
        }
        usleep(150_000)
        mouse(.leftMouseUp, end); usleep(50_000)
        command(false)
        usleep(200_000)
        if let savedCursor { CGWarpMouseCursorPosition(savedCursor) }
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

extension ItemMover {
    /// 把图标放到某个区域里从左往右数第 index 个位置（index 按包含被拖图标在内的当前顺序计算，
    /// 和设置页里的复刻菜单栏一致）。会换算成「放到某个图标左/右边」或「移到某区域」。
    static func drop(_ item: MenuBarItem, into section: BarSection, at index: Int, items: [MenuBarItem],
                     controller: MenuBarController, completion: @escaping (Result<Void, Error>) -> Void) {
        let zone = items.filter { $0.section == section && $0.movable }.sorted { $0.frame.minX < $1.frame.minX }
        var target = max(0, min(index, zone.count))
        if let old = zone.firstIndex(where: { $0.id == item.id }) {
            // 同一区域内：原位置左右两侧都等于没动
            if target == old || target == old + 1 { return completion(.success(())) }
            if target > old { target -= 1 }
        }
        let others = zone.filter { $0.id != item.id }
        if others.isEmpty {
            move(item, to: section, controller: controller, completion: completion)
        } else if target < others.count {
            place(item, .left, of: others[target], controller: controller, completion: completion)
        } else {
            place(item, .right, of: others[others.count - 1], controller: controller, completion: completion)
        }
    }
}
