import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 复刻菜单栏里的一个插入位置
struct DropSlot: Equatable {
    let section: BarSection
    let index: Int
}

final class ItemsModel: ObservableObject {
    let controller: MenuBarController
    @Published var items: [MenuBarItem] = []
    @Published var trusted = Accessibility.isTrusted
    @Published var movingID: String?
    @Published var message: String?
    @Published var notchOverflow: CGFloat = 0
    @Published var dropSlot: DropSlot?
    var draggingID: String?
    private var trustTimer: Timer?

    init(controller: MenuBarController) {
        self.controller = controller
    }

    func onAppear() {
        refresh()
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Accessibility.isTrusted != self.trusted { self.refresh() }
        }
    }

    func onDisappear() { trustTimer?.invalidate(); trustTimer = nil }

    func refresh() {
        trusted = Accessibility.isTrusted
        items = MenuBarScanner.scan(controller: controller)
        notchOverflow = computeNotchOverflow()
    }

    /// 某个区域里可移动的图标，按菜单栏上从左到右排列
    func zone(_ section: BarSection) -> [MenuBarItem] {
        items.filter { $0.section == section && $0.movable }.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// 系统固定的图标（时钟、控制中心），从左到右
    var fixedItems: [MenuBarItem] {
        items.filter { !$0.movable }.sorted { $0.frame.minX < $1.frame.minX }
    }

    func drop(_ id: String, into section: BarSection, at index: Int) {
        guard movingID == nil, let item = items.first(where: { $0.id == id }) else { return }
        let snapshot = items
        run(item) { ItemMover.drop(item, into: section, at: index, items: snapshot, controller: self.controller, completion: $0) }
    }

    func move(_ item: MenuBarItem, to section: BarSection) {
        guard movingID == nil else { return }
        run(item) { ItemMover.move(item, to: section, controller: self.controller, completion: $0) }
    }

    private func run(_ item: MenuBarItem, _ action: (@escaping (Result<Void, Error>) -> Void) -> Void) {
        movingID = item.id
        message = nil
        action { [weak self] result in
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

// MARK: - 页面

struct ItemsView: View {
    @StateObject private var model: ItemsModel
    @ObservedObject private var settings = Settings.shared

    init(controller: MenuBarController) {
        _model = StateObject(wrappedValue: ItemsModel(controller: controller))
    }

    var body: some View {
        Group {
            if model.trusted { content } else { permissionPrompt }
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
                Button("请求权限") { Accessibility.requestAccess() }.buttonStyle(.borderedProminent)
                Button("打开系统设置") { Accessibility.openSettings() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("拖动图标来调整它在菜单栏上的位置").font(.headline)
                Spacer()
                if model.movingID != nil { ProgressView().controlSize(.small) }
                Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
            }

            if model.notchOverflow > 0 {
                Label("常显区比刘海右侧的空间宽了约 \(Int(model.notchOverflow)) pt，最左边的会被刘海挡住。建议再隐藏几个。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let message = model.message {
                Label(message, systemImage: "xmark.octagon.fill").font(.callout).foregroundStyle(.red)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    replica.padding(.vertical, 6).id("replica")
                }
                .onAppear { proxy.scrollTo("replica", anchor: .trailing) }
            }

            Divider().padding(.vertical, 4)
            HStack(alignment: .top, spacing: 28) {
                DragDemoView()
                    .padding(12)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 8) {
                    Text("怎么用").font(.headline)
                    tip("hand.draw", "把图标拖到「常显」就一直显示，拖到「隐藏」平时收起。右键图标也能直接选区域。")
                    tip("cursorarrow.click", "单击菜单栏上的 ‹ 展开或收起隐藏的图标，快捷键 \(settings.hotKey.displayString)。")
                    if settings.alwaysHiddenEnabled {
                        tip("option", "「始终隐藏」的图标只有 ⌥ 单击 ‹ 时才出现。")
                    }
                    tip("command", "也可以在菜单栏上按住 ⌘ 直接拖动图标。")
                    tip("rectangle.topthird.inset.filled", "常显图标太多会被刘海挡住，超出时这里会提醒。")
                }
                .font(.callout)
                .frame(maxWidth: 360, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 18)
        }
    }

    // MARK: 复刻的菜单栏

    private var replica: some View {
        HStack(alignment: .bottom, spacing: 4) {
            if settings.alwaysHiddenEnabled {
                ZoneStrip(section: .alwaysHidden, tint: .gray, model: model)
                SeparatorMark(dashed: true)
            }
            ZoneStrip(section: .hidden, tint: .orange, model: model)
            SeparatorMark(dashed: false)
            ZoneStrip(section: .visible, tint: .green, model: model)
            // Tuck 自己 + 系统固定的图标
            VStack(alignment: .leading, spacing: 4) {
                Text("系统固定").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.tint).frame(height: 22)
                        Text("Tuck").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(width: ItemCell.width)
                    ForEach(model.fixedItems) { item in
                        ItemCell(item: item, model: model).opacity(0.5)
                    }
                }
                .padding(.horizontal, ZoneStrip.padding)
                .frame(height: ZoneStrip.height)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
            }
        }
    }
}

/// 一个区域：标题 + 一段菜单栏
private struct ZoneStrip: View {
    static let padding: CGFloat = 6
    static let height: CGFloat = 52

    let section: BarSection
    let tint: Color
    @ObservedObject var model: ItemsModel

    var body: some View {
        let items = model.zone(section)
        let slot = model.dropSlot?.section == section ? model.dropSlot?.index : nil
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text("\(section.title)（\(items.count)）").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ItemCell(item: item, model: model)
                        .overlay(alignment: .leading) { if slot == index { InsertionMark() } }
                        .overlay(alignment: .trailing) {
                            if slot == items.count && index == items.count - 1 { InsertionMark() }
                        }
                }
                if items.isEmpty {
                    Text("拖到这里").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 10)
                }
            }
            .padding(.horizontal, Self.padding)
            .frame(minWidth: 90, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
            .background(tint.opacity(slot != nil ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(slot != nil ? 0.9 : 0.4), lineWidth: slot != nil ? 2 : 1)
            )
            .onDrop(of: [.text], delegate: ZoneDropDelegate(section: section, count: items.count, model: model))
        }
    }
}

private struct InsertionMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 3, height: 40).offset(x: -1.5)
    }
}

private struct SeparatorMark: View {
    let dashed: Bool

    var body: some View {
        Text(dashed ? "┊" : "│")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.secondary)
            .frame(width: 14, height: ZoneStrip.height)
            .help(dashed ? "始终隐藏分隔线" : "隐藏分隔线")
    }
}

/// 复刻菜单栏中的一个图标：App 图标 + 名字
private struct ItemCell: View {
    static let width: CGFloat = 50

    let item: MenuBarItem
    @ObservedObject var model: ItemsModel

    /// 系统图标用对应的 SF Symbol，比「控制中心」的 App 图标好认
    private var symbol: String? {
        switch item.id {
        case "com.apple.menuextra.wifi": return "wifi"
        case "com.apple.menuextra.battery": return "battery.75percent"
        case "com.apple.menuextra.clock": return "clock"
        case "com.apple.menuextra.controlcenter": return "switch.2"
        case "com.apple.menuextra.bluetooth": return "bluetooth"
        case "com.apple.menuextra.sound", "com.apple.menuextra.volume": return "speaker.wave.2"
        case "com.apple.menuextra.focusmode": return "moon"
        case "com.apple.menuextra.airdrop": return "airplayaudio"
        case "com.apple.menuextra.display": return "sun.max"
        default: break
        }
        switch item.bundleID {
        case "com.apple.Spotlight": return "magnifyingglass"
        case "com.apple.TextInputMenuAgent": return "keyboard"
        default: return nil
        }
    }

    /// 图标下方的短名字
    private var shortName: String {
        if item.id.hasPrefix("com.apple.menuextra."), !item.title.isEmpty {
            return String(item.title.split(separator: "，").first ?? Substring(item.title))
        }
        return item.appName
    }

    var body: some View {
        let busy = model.movingID == item.id
        VStack(spacing: 2) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 15)).frame(width: 22, height: 22)
                } else if let icon = item.icon {
                    Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                } else {
                    Image(systemName: "app.dashed").frame(width: 22, height: 22)
                }
            }
            Text(shortName).font(.system(size: 9)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.width, height: 44)
        .contentShape(Rectangle())
        .opacity(busy ? 0.35 : (model.movingID != nil ? 0.7 : 1))
        .overlay { if busy { ProgressView().controlSize(.small) } }
        .help(item.displayName)
        .modifier(DraggableIfMovable(item: item, model: model))
    }
}

private struct DraggableIfMovable: ViewModifier {
    let item: MenuBarItem
    @ObservedObject var model: ItemsModel
    @ObservedObject private var settings = Settings.shared

    func body(content: Content) -> some View {
        if item.movable {
            content
                .onDrag {
                    model.draggingID = item.id
                    return NSItemProvider(object: item.id as NSString)
                }
                .contextMenu {
                    Text(item.displayName)
                    Divider()
                    ForEach(settings.alwaysHiddenEnabled ? BarSection.allCases : [.visible, .hidden]) { section in
                        Button("移到「\(section.title)」") { model.move(item, to: section) }
                            .disabled(section == item.section || model.movingID != nil)
                    }
                }
        } else {
            content.help("\(item.displayName)（系统固定，不能移动）")
        }
    }
}

private struct ZoneDropDelegate: DropDelegate {
    let section: BarSection
    let count: Int
    let model: ItemsModel

    /// 根据落点 x 计算插入位置（每个图标宽度相同）
    private func index(_ info: DropInfo) -> Int {
        let x = info.location.x - ZoneStrip.padding
        return max(0, min(count, Int((x / ItemCell.width).rounded())))
    }

    func validateDrop(info: DropInfo) -> Bool { model.draggingID != nil && model.movingID == nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let slot = DropSlot(section: section, index: index(info))
        if model.dropSlot != slot { model.dropSlot = slot }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if model.dropSlot?.section == section { model.dropSlot = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let i = index(info)
        model.dropSlot = nil
        guard let id = model.draggingID else { return false }
        model.draggingID = nil
        model.drop(id, into: section, at: i)
        return true
    }
}
