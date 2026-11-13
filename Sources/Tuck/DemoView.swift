import SwiftUI

/// 设置页里循环播放的操作演示：把图标从「隐藏」拖到「常显」，上方菜单栏同步出现；再拖回去。
struct DragDemoView: View {
    private static let cycle: Double = 8
    private static let width: CGFloat = 440
    private static let height: CGFloat = 150
    private static let cell: CGFloat = 40
    private static let pad: CGFloat = 6
    private static let zoneWidth = pad * 2 + cell * 3
    private static let sepWidth: CGFloat = 20
    private static let hiddenX = (width - (zoneWidth * 2 + sepWidth)) / 2
    private static let visibleX = hiddenX + zoneWidth + sepWidth
    private static let zoneY: CGFloat = 112
    private static let rest = CGPoint(x: width - 30, y: height - 6)

    private static let hiddenIcons = ["cloud.fill", "music.note"]
    private static let visibleIcons = ["bolt.fill", "wifi"]
    private static let moving = "star.fill"

    private static func slot(_ visible: Bool, _ i: Int) -> CGPoint {
        CGPoint(x: (visible ? visibleX : hiddenX) + pad + cell * (CGFloat(i) + 0.5), y: zoneY)
    }

    /// 某一时刻的画面状态
    private struct Frame {
        var cursor: CGPoint
        var starVisible: Bool          // 星星当前属于常显区
        var dragging: CGPoint?         // 拖动中星星的位置
        var pressed = false
        var targetVisible: Bool?       // 正在悬停的目标区域
        var menuStar: Double           // 菜单栏上星星的显示程度 0...1
    }

    private static func ease(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func frame(at time: Double) -> Frame {
        let p = time.truncatingRemainder(dividingBy: cycle)
        let forward = p < cycle / 2          // 前半段：隐藏 → 常显；后半段：常显 → 隐藏
        let q = forward ? p : p - cycle / 2
        let from = slot(!forward, 2), to = slot(forward, 2)
        let before = forward ? 0.0 : 1.0, after = forward ? 1.0 : 0.0

        switch q {
        case ..<0.6:
            return Frame(cursor: lerp(rest, from, ease(q / 0.6)), starVisible: !forward, menuStar: before)
        case ..<0.8:
            return Frame(cursor: from, starVisible: !forward, pressed: true, menuStar: before)
        case ..<2.0:
            let pos = lerp(from, to, ease((q - 0.8) / 1.0))
            return Frame(cursor: pos, starVisible: !forward, dragging: pos,
                         targetVisible: q > 1.3 ? forward : nil, menuStar: before)
        default:
            let k = ease((q - 2.0) / 0.35)
            return Frame(cursor: lerp(to, rest, ease((q - 2.2) / 0.8)), starVisible: forward,
                         menuStar: before + (after - before) * k)
        }
    }

    var body: some View {
        TimelineView(.animation) { context in
            let f = Self.frame(at: context.date.timeIntervalSinceReferenceDate)
            ZStack(alignment: .topLeading) {
                menuBar(f)
                zones(f)
                if let pos = f.dragging {
                    icon(Self.moving).scaleEffect(1.15).shadow(radius: 4).position(pos)
                }
                Image(systemName: "cursorarrow")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 1)
                    .scaleEffect(f.pressed || f.dragging != nil ? 0.9 : 1)
                    .position(x: f.cursor.x + 5, y: f.cursor.y + 9)
            }
            .frame(width: Self.width, height: Self.height)
        }
        .accessibilityLabel("演示：把图标拖到常显区，菜单栏上就会显示它；拖回隐藏区就会收起")
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 15)).frame(width: Self.cell, height: 30)
    }

    /// 顶部的迷你菜单栏（收起状态，只显示常显区）
    private func menuBar(_ f: Frame) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("菜单栏").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Spacer()
                ForEach(Self.visibleIcons, id: \.self) { Image(systemName: $0) }
                Image(systemName: Self.moving)
                    .scaleEffect(0.4 + 0.6 * f.menuStar)
                    .opacity(f.menuStar)
                    .frame(width: 14 * f.menuStar)
                Image(systemName: "chevron.left").fontWeight(.semibold).foregroundStyle(.tint)
                Text("9:41").monospacedDigit()
            }
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(width: Self.width, height: 24)
            .background(Color(white: 0.18), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func zones(_ f: Frame) -> some View {
        let hidden = Self.hiddenIcons + (f.starVisible || f.dragging != nil ? [] : [Self.moving])
        let visible = Self.visibleIcons + (f.starVisible && f.dragging == nil ? [Self.moving] : [])
        return ZStack(alignment: .topLeading) {
            zone(title: "隐藏", tint: .orange, x: Self.hiddenX, icons: hidden,
                 pressed: f.pressed && !f.starVisible, targeted: f.targetVisible == false)
            Text("│").font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
                .position(x: Self.hiddenX + Self.zoneWidth + Self.sepWidth / 2, y: Self.zoneY)
            zone(title: "常显", tint: .green, x: Self.visibleX, icons: visible,
                 pressed: f.pressed && f.starVisible, targeted: f.targetVisible == true)
        }
    }

    private func zone(title: String, tint: Color, x: CGFloat, icons: [String], pressed: Bool, targeted: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            .position(x: x + 24, y: Self.zoneY - 32)
            RoundedRectangle(cornerRadius: 7)
                .fill(tint.opacity(targeted ? 0.2 : 0.08))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(tint.opacity(targeted ? 0.9 : 0.4), lineWidth: targeted ? 2 : 1))
                .frame(width: Self.zoneWidth, height: 38)
                .position(x: x + Self.zoneWidth / 2, y: Self.zoneY)
            ForEach(Array(icons.enumerated()), id: \.element) { i, name in
                icon(name)
                    .scaleEffect(pressed && name == Self.moving ? 1.15 : 1)
                    .position(x: x + Self.pad + Self.cell * (CGFloat(i) + 0.5), y: Self.zoneY)
            }
            if targeted {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor)
                    .frame(width: 3, height: 28)
                    .position(x: x + Self.pad + Self.cell * 2, y: Self.zoneY)
            }
        }
    }
}
