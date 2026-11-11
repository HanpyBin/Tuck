import AppKit
import SwiftUI

final class ItemsModel: ObservableObject {
    let controller: MenuBarController
    @Published var items: [MenuBarItem] = []
    @Published var trusted = Accessibility.isTrusted
    @Published var movingID: String?
    @Published var message: String?
    @Published var notchOverflow: CGFloat = 0
    private var trustTimer: Timer?

    init(controller: MenuBarController) {
        self.controller = controller
    }

    func onAppear() {
        refresh()
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Accessibility.isTrusted
            if now != self.trusted { self.trusted = now; self.refresh() }
        }
    }

    func onDisappear() { trustTimer?.invalidate(); trustTimer = nil }

    func refresh() {
        trusted = Accessibility.isTrusted
        items = MenuBarScanner.scan(controller: controller)
        notchOverflow = computeNotchOverflow()
    }

    /// 同一区域内可移动的图标，按菜单栏从右到左排列
    func movableItems(in section: BarSection) -> [MenuBarItem] {
        items.filter { $0.section == section && $0.movable }
    }

    /// 把图标挪到所在区域内的第 newIndex 位（0 = 最右）
    func reorder(_ item: MenuBarItem, to newIndex: Int) {
        guard movingID == nil else { return }
        var list = movableItems(in: item.section)
        guard let old = list.firstIndex(where: { $0.id == item.id }), list.count > 1 else { return }
        let index = max(0, min(newIndex, list.count - 1))
        guard index != old else { return }
        list.remove(at: old)
        list.insert(item, at: index)
        // 有右边邻居就放到它左边，否则（成为最右）放到原来最右那个的右边
        let (side, anchor): (ItemMover.Side, MenuBarItem) = index > 0 ? (.left, list[index - 1]) : (.right, list[1])
        movingID = item.id
        message = nil
        ItemMover.place(item, side, of: anchor, controller: controller) { [weak self] result in
            guard let self else { return }
            self.movingID = nil
            if case .failure(let error) = result { self.message = error.localizedDescription }
            self.refresh()
        }
    }

    func move(_ item: MenuBarItem, to section: BarSection) {
        guard movingID == nil else { return }
        movingID = item.id
        message = nil
        ItemMover.move(item, to: section, controller: controller) { [weak self] result in
            guard let self else { return }
            self.movingID = nil
            if case .failure(let error) = result { self.message = error.localizedDescription }
            self.refresh()
        }
    }

    /// 常显区图标的总宽度超出刘海右侧可用空间多少（pt），0 表示放得下
    private func computeNotchOverflow() -> CGFloat {
        guard let screen = NSScreen.screens.first,
              let notchRight = screen.auxiliaryTopRightArea?.minX,
              let controlMinX = controller.control.button?.window?.frame.minX else { return 0 }
        let available = controlMinX - notchRight
        let used = items.filter { $0.section == .visible && $0.frame.maxX <= controlMinX + 1 }
            .reduce(CGFloat(0)) { sum, item in
                sum + (MenuBarWindows.window(containingX: item.frame.midX)?.frame.width ?? item.frame.width + 14)
            }
        return max(0, used - available)
    }
}

struct ItemsView: View {
    @StateObject private var model: ItemsModel

    init(controller: MenuBarController) {
        _model = StateObject(wrappedValue: ItemsModel(controller: controller))
    }

    var body: some View {
        Group {
            if model.trusted {
                list
            } else {
                permissionPrompt
            }
        }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    private var permissionPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "hand.raised.circle").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("需要辅助功能权限").font(.title3).bold()
            Text("Tuck 需要辅助功能权限才能识别菜单栏上每个图标属于哪个 App，并帮你把它移动到指定区域。\n\n不授权也可以用：按住 ⌘ 拖动图标到分隔线左右两侧即可。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            HStack {
                Button("请求权限") { Accessibility.requestAccess() }
                    .buttonStyle(.borderedProminent)
                Button("打开系统设置") { Accessibility.openSettings() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("选择每个图标所在的区域").font(.headline)
                Spacer()
                if model.movingID != nil { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
            }
            if model.notchOverflow > 0 {
                Label("常显区图标比刘海右侧的空间宽了约 \(Int(model.notchOverflow)) pt，最左边的会被刘海挡住。建议再隐藏几个。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let message = model.message {
                Label(message, systemImage: "xmark.octagon.fill").font(.callout).foregroundStyle(.red)
            }
            List {
                ForEach(BarSection.allCases) { section in
                    let items = model.items.filter { $0.section == section }
                    if section != .alwaysHidden || Settings.shared.alwaysHiddenEnabled {
                        let movable = items.filter(\.movable)
                        Section("\(section.title)（\(items.count)）") {
                            if items.isEmpty {
                                Text("无").foregroundStyle(.tertiary)
                            }
                            ForEach(items.filter { !$0.movable }) { item in
                                ItemRow(item: item, index: nil, count: 0, busy: false, disabled: true,
                                        onMove: { _ in }, onReorder: { _ in })
                            }
                            ForEach(Array(movable.enumerated()), id: \.element.id) { index, item in
                                ItemRow(item: item, index: index, count: movable.count,
                                        busy: model.movingID == item.id, disabled: model.movingID != nil,
                                        onMove: { model.move(item, to: $0) },
                                        onReorder: { model.reorder(item, to: $0) })
                            }
                            .onMove { from, to in
                                guard let source = from.first else { return }
                                model.reorder(movable[source], to: to > source ? to - 1 : to)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            Text("列表从上到下 = 菜单栏从右到左。上下拖动行、点 ←/→ 或右键可以调整顺序。改变区域或顺序时 Tuck 会模拟 ⌘ 拖动。列表里没有的图标，可能在「系统设置 › 菜单栏」中被关闭了。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ItemRow: View {
    let item: MenuBarItem
    /// 在所在区域可移动图标中的位置（0 = 最右）；nil 表示系统固定
    let index: Int?
    let count: Int
    let busy: Bool
    let disabled: Bool
    let onMove: (BarSection) -> Void
    let onReorder: (Int) -> Void

    var body: some View {
        HStack {
            if let icon = item.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20)
            }
            Text(item.displayName).lineLimit(1).truncationMode(.tail)
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            if let index, count > 1 {
                ControlGroup {
                    Button { onReorder(index + 1) } label: { Image(systemName: "arrow.left") }
                        .help("在菜单栏上往左挪一位")
                        .disabled(disabled || index >= count - 1)
                    Button { onReorder(index - 1) } label: { Image(systemName: "arrow.right") }
                        .help("在菜单栏上往右挪一位")
                        .disabled(disabled || index == 0)
                }
                .frame(width: 60)
            }
            if item.movable {
                Picker("", selection: Binding(get: { item.section }, set: { onMove($0) })) {
                    ForEach(availableSections) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: Settings.shared.alwaysHiddenEnabled ? 200 : 130)
                .disabled(disabled)
            } else {
                Text("系统固定").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if let index, count > 1 {
                Button("移到最右") { onReorder(0) }.disabled(disabled || index == 0)
                Button("移到最左") { onReorder(count - 1) }.disabled(disabled || index == count - 1)
            }
        }
        .moveDisabled(index == nil || disabled)
    }

    private var availableSections: [BarSection] {
        Settings.shared.alwaysHiddenEnabled ? BarSection.allCases : [.visible, .hidden]
    }
}
