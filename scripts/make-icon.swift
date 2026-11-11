// 生成 Tuck 的 App 图标：swift scripts/make-icon.swift <输出目录>
// 输出 icon_1024.png 和 AppIcon.iconset/（再用 iconutil 转成 .icns）
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func render(size px: Int) -> Data {
    let s = CGFloat(px) / 1024
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)

    // 底板：macOS 图标网格 824×824，留出阴影空间
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x2B2F8F)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [rgb(0x6C7BFF), rgb(0x3B2FA8)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // 顶部高光
    let shine = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
    ctx.restoreGState()

    // 菜单栏条
    let bar = CGRect(x: 148, y: 422, width: 728, height: 188)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0x150F5C, 0.45))
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 56, cornerHeight: 56, transform: nil))
    ctx.setFillColor(rgb(0xFFFFFF, 0.97)); ctx.fillPath()
    ctx.restoreGState()

    func square(_ cx: CGFloat, _ r: CGFloat, _ color: CGColor) {
        ctx.addPath(CGPath(roundedRect: CGRect(x: cx - r, y: bar.midY - r, width: r * 2, height: r * 2),
                           cornerWidth: r * 0.42, cornerHeight: r * 0.42, transform: nil))
        ctx.setFillColor(color); ctx.fillPath()
    }
    // 左侧：被收起的图标，越往左越淡越小
    square(214, 20, rgb(0x4B45C8, 0.16))
    square(282, 28, rgb(0x4B45C8, 0.30))
    square(366, 36, rgb(0x4B45C8, 0.50))
    // 分隔线
    ctx.setStrokeColor(rgb(0x4B45C8, 0.55)); ctx.setLineWidth(9); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 452, y: bar.midY - 52)); ctx.addLine(to: CGPoint(x: 452, y: bar.midY + 52)); ctx.strokePath()
    // 右侧：常显的图标
    square(540, 44, rgb(0x3B2FA8))
    square(648, 44, rgb(0x3B2FA8))
    // Tuck 的「‹」
    ctx.setStrokeColor(rgb(0xFF8A3D)); ctx.setLineWidth(26); ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 814, y: bar.midY + 54)); ctx.addLine(to: CGPoint(x: 758, y: bar.midY))
    ctx.addLine(to: CGPoint(x: 814, y: bar.midY - 54)); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(size: 1024).write(to: outDir.appendingPathComponent("icon_1024.png"))
print("ok")
