import AppKit
import CoreGraphics
import Foundation

// Draws the app icon at any size from vectors, so every rung of the iconset is
// crisp rather than a downscale of the 1024.

let markupRed = CGColor(red: 0.91, green: 0.15, blue: 0.13, alpha: 1)

func squirclePath(in rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.width * 0.2237,
           cornerHeight: rect.height * 0.2237, transform: nil)
}

func drawArrow(in ctx: CGContext, from: CGPoint, to: CGPoint, width: CGFloat, color: CGColor) {
    let dx = to.x - from.x, dy = to.y - from.y
    let length = (dx * dx + dy * dy).squareRoot()
    guard length > 0 else { return }
    let head = width * 3.2
    let ux = dx / length, uy = dy / length
    let neck = CGPoint(x: to.x - ux * head, y: to.y - uy * head)
    let px = -uy, py = ux

    ctx.setStrokeColor(color)
    ctx.setFillColor(color)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.move(to: from)
    ctx.addLine(to: neck)
    ctx.strokePath()

    ctx.move(to: to)
    ctx.addLine(to: CGPoint(x: neck.x + px * head * 0.42, y: neck.y + py * head * 0.42))
    ctx.addLine(to: CGPoint(x: neck.x - px * head * 0.42, y: neck.y - py * head * 0.42))
    ctx.closePath()
    ctx.fillPath()
}

func renderIcon(size S: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Apple's macOS grid: the squircle occupies ~80% of the canvas.
    let inset = S * 0.10
    let body = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let path = squirclePath(in: body)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 0.20, green: 0.24, blue: 0.31, alpha: 1),
                                       CGColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 1)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])
    ctx.restoreGState()

    // The "screenshot" the markup sits on.
    let cardInset = body.width * 0.175
    let card = body.insetBy(dx: cardInset, dy: cardInset * 1.2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.006), blur: S * 0.02,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
    ctx.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: S * 0.035, cornerHeight: S * 0.035, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()

    // Two grey bars hint at content without turning to mush when small.
    ctx.setFillColor(CGColor(red: 0.78, green: 0.80, blue: 0.83, alpha: 1))
    let barH = card.height * 0.085
    for i in 0..<2 {
        let y = card.maxY - card.height * (0.20 + CGFloat(i) * 0.19)
        let w = card.width * (i == 0 ? 0.52 : 0.34)
        ctx.addPath(CGPath(roundedRect: CGRect(x: card.minX + card.width * 0.13, y: y, width: w, height: barH),
                           cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
        ctx.fillPath()
    }

    // Red box on the thing being pointed at.
    let stroke = max(1, S * 0.026)
    let box = CGRect(x: card.minX + card.width * 0.11, y: card.minY + card.height * 0.17,
                     width: card.width * 0.40, height: card.height * 0.31)
    ctx.setStrokeColor(markupRed)
    ctx.setLineWidth(stroke)
    ctx.setLineJoin(.round)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: stroke, cornerHeight: stroke, transform: nil))
    ctx.strokePath()

    // Arrow into it from the lower right.
    // Kept inside the card: an arrow spilling onto the background reads as a
    // rendering mistake rather than markup.
    drawArrow(in: ctx,
              from: CGPoint(x: card.maxX - card.width * 0.10, y: card.minY + card.height * 0.10),
              to: CGPoint(x: box.maxX + stroke * 1.6, y: box.minY + box.height * 0.55),
              width: stroke * 1.2, color: markupRed)

    return ctx.makeImage()!
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AIShot.iconset")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let rungs: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for rung in rungs {
    let image = renderIcon(size: CGFloat(rung.px))
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: rung.px, height: rung.px)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: outDir.appendingPathComponent("\(rung.name).png"))
}
print("wrote \(rungs.count) sizes to \(outDir.path)")
