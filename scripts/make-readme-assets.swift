import AIShotCore
import AppKit
import CoreGraphics
import CoreText
import Foundation

// Generates the README's icon and example images. The example is annotated with
// the real renderer, so it cannot drift from what the app actually draws.

let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outDir = repo.appendingPathComponent("docs/images")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func text(_ s: String, _ size: CGFloat, _ color: CGColor, bold: Bool = false) -> CTLine {
    let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
    let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
    return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)!)
}

func draw(_ line: CTLine, at p: CGPoint, in ctx: CGContext) {
    ctx.textMatrix = .identity
    ctx.textPosition = p
    CTLineDraw(line, ctx)
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

/// A mock settings pane, standing in for a real screenshot.
func mockScreenshot(width W: Int, height H: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w = CGFloat(W), h = CGFloat(H)

    ctx.setFillColor(rgb(0.118, 0.129, 0.157))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    ctx.setFillColor(rgb(0.086, 0.094, 0.118))
    ctx.fill(CGRect(x: 0, y: 0, width: w * 0.26, height: h))

    let sidebar = ["Profile", "Appearance", "Notifications", "Advanced"]
    for (i, item) in sidebar.enumerated() {
        let y = h - 90 - CGFloat(i) * 42
        if i == 3 {
            ctx.setFillColor(rgb(0.16, 0.18, 0.22))
            ctx.addPath(CGPath(roundedRect: CGRect(x: 14, y: y - 10, width: w * 0.26 - 28, height: 32),
                               cornerWidth: 6, cornerHeight: 6, transform: nil))
            ctx.fillPath()
        }
        draw(text(item, 15, i == 3 ? rgb(0.95, 0.95, 0.97) : rgb(0.55, 0.58, 0.64)),
             at: CGPoint(x: 28, y: y), in: ctx)
    }

    draw(text("Advanced", 26, rgb(0.95, 0.95, 0.97), bold: true), at: CGPoint(x: w * 0.26 + 40, y: h - 80), in: ctx)

    let rows: [(String, String)] = [
        ("API endpoint", "https://api.internal/v2"),
        ("Contact email", "someone@example.com"),
        ("Retry attempts", "3"),
        ("Timeout", "30s"),
    ]
    for (i, row) in rows.enumerated() {
        let y = h - 150 - CGFloat(i) * 62
        ctx.setFillColor(rgb(0.145, 0.157, 0.192))
        ctx.addPath(CGPath(roundedRect: CGRect(x: w * 0.26 + 30, y: y - 18, width: w - (w * 0.26) - 70, height: 48),
                           cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.fillPath()
        draw(text(row.0, 14, rgb(0.62, 0.65, 0.71)), at: CGPoint(x: w * 0.26 + 48, y: y + 12), in: ctx)
        draw(text(row.1, 15, rgb(0.90, 0.91, 0.94)), at: CGPoint(x: w * 0.26 + 48, y: y - 8), in: ctx)
    }

    ctx.setFillColor(rgb(0.20, 0.45, 0.85))
    ctx.addPath(CGPath(roundedRect: CGRect(x: w - 160, y: 34, width: 110, height: 38),
                       cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.fillPath()
    draw(text("Save", 15, rgb(1, 1, 1), bold: true), at: CGPoint(x: w - 125, y: 46), in: ctx)

    return ctx.makeImage()!
}

func write(_ image: CGImage, to name: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
    print("wrote docs/images/\(name)  \(image.width)x\(image.height)")
}

let base = mockScreenshot(width: 900, height: 560)
try write(base, to: "example-base.png")

// Annotated with the real renderer, so the README cannot show markup the app
// does not actually produce.
let size = CGSize(width: base.width, height: base.height)
func style(_ c: MarkupColor, _ z: SizeClass = .medium) -> Style { .scaled(to: size, color: c, size: z) }

// Row i occupies y = 542 - i*62 through +48; values sit 8pt below that baseline.
let annotated = Renderer.render(base: base, annotations: [
    StyledAnnotation(.redact(CGRect(x: 278, y: 332, width: 196, height: 24)), style: style(.red)),
    StyledAnnotation(.badge(center: CGPoint(x: 248, y: 354), number: 1), style: style(.blue)),
    StyledAnnotation(.box(CGRect(x: 262, y: 264, width: 598, height: 54)), style: style(.red)),
    StyledAnnotation(.badge(center: CGPoint(x: 248, y: 291), number: 2), style: style(.blue)),
    StyledAnnotation(.text(origin: CGPoint(x: 446, y: 142), string: "disable until valid"), style: style(.yellow)),
    StyledAnnotation(.arrow(from: CGPoint(x: 612, y: 126), to: CGPoint(x: 744, y: 66)), style: style(.red)),
])!
try write(annotated, to: "example.png")

// Icon for the README header.
let iconset = repo.appendingPathComponent("build/AIShot.iconset/icon_256x256.png")
if let data = try? Data(contentsOf: iconset) {
    try data.write(to: outDir.appendingPathComponent("icon.png"))
    print("wrote docs/images/icon.png")
}
