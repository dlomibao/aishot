import CoreGraphics
import ImageIO
import XCTest
@testable import AIShotCore

/// Renders onto a known white canvas so every assertion is "what colour is this pixel".
private struct Probe {
    let width: Int
    let height: Int
    private let pixels: [UInt8]

    init(annotations: [Annotation], width: Int = 200, height: Int = 200) throws {
        let style = Style.scaled(to: CGSize(width: width, height: height))
        try self.init(styled: annotations.map { StyledAnnotation($0, style: style) },
                      width: width, height: height)
    }

    init(styled: [StyledAnnotation], width: Int = 200, height: Int = 200) throws {
        self.width = width
        self.height = height
        let base = try XCTUnwrap(Probe.whiteImage(width: width, height: height))
        let rendered = try XCTUnwrap(Renderer.render(base: base, annotations: styled))
        self.pixels = try XCTUnwrap(Probe.rgbaBytes(of: rendered))
    }

    func color(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let i = ((height - 1 - y) * width + x) * 4
        return (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }

    var isAnyPixelRed: Bool {
        stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] > 180 && pixels[$0 + 1] < 90 }
    }

    func pixelCount(inRect rect: CGRect, where matches: ((UInt8, UInt8, UInt8, UInt8)) -> Bool) -> Int {
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) where matches(color(x: x, y: y)) { count += 1 }
        }
        return count
    }

    func redPixelCount(inRect rect: CGRect) -> Int {
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let c = color(x: x, y: y)
                if c.r > 180 && c.g < 90 { count += 1 }
            }
        }
        return count
    }

    static func whiteImage(width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    static func rgbaBytes(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? buffer : nil
    }
}

final class RendererTests: XCTestCase {
    func testOutputKeepsTheSourcePixelDimensions() throws {
        let base = try XCTUnwrap(Probe.whiteImage(width: 640, height: 480))
        let out = try XCTUnwrap(Renderer.render(base: base, annotations: []))
        XCTAssertEqual(out.width, 640)
        XCTAssertEqual(out.height, 480)
    }

    func testAnEmptyAnnotationListLeavesTheImageUntouched() throws {
        let probe = try Probe(annotations: [])
        XCTAssertFalse(probe.isAnyPixelRed)
        let c = probe.color(x: 100, y: 100)
        XCTAssertEqual(c.r, 255)
    }

    func testBoxDrawsOnItsEdgeAndLeavesTheInteriorAlone() throws {
        let rect = CGRect(x: 50, y: 50, width: 100, height: 100)
        let probe = try Probe(annotations: [.box(rect)])
        XCTAssertGreaterThan(probe.redPixelCount(inRect: CGRect(x: 45, y: 45, width: 110, height: 10)), 0,
                             "expected the bottom edge of the box to be drawn")
        let interior = probe.color(x: 100, y: 100)
        XCTAssertEqual(interior.r, 255)
        XCTAssertEqual(interior.g, 255)
    }

    func testRedactFillsItsRegionWithOpaqueBlack() throws {
        let rect = CGRect(x: 40, y: 40, width: 60, height: 60)
        let probe = try Probe(annotations: [.redact(rect)])
        let inside = probe.color(x: 70, y: 70)
        XCTAssertEqual(inside.r, 0)
        XCTAssertEqual(inside.g, 0)
        XCTAssertEqual(inside.b, 0)
        XCTAssertEqual(inside.a, 255)
    }

    func testRedactLeavesPixelsOutsideItsRegionUntouched() throws {
        let probe = try Probe(annotations: [.redact(CGRect(x: 40, y: 40, width: 60, height: 60))])
        let outside = probe.color(x: 150, y: 150)
        XCTAssertEqual(outside.r, 255)
    }

    func testRedactIsDestructiveRatherThanTranslucent() throws {
        // A grey source proves the region was overwritten, not alpha-blended.
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        let grey = try XCTUnwrap(ctx.makeImage())
        let redaction = StyledAnnotation(.redact(CGRect(x: 10, y: 10, width: 50, height: 50)),
                                         style: .scaled(to: CGSize(width: 100, height: 100)))
        let out = try XCTUnwrap(Renderer.render(base: grey, annotations: [redaction]))
        let bytes = try XCTUnwrap(Probe.rgbaBytes(of: out))
        let i = ((100 - 1 - 30) * 100 + 30) * 4
        XCTAssertEqual(bytes[i], 0)
    }

    func testArrowPutsInkNearBothEndpoints() throws {
        let probe = try Probe(annotations: [.arrow(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 180, y: 180))])
        XCTAssertGreaterThan(probe.redPixelCount(inRect: CGRect(x: 10, y: 10, width: 25, height: 25)), 0,
                             "expected ink at the arrow tail")
        XCTAssertGreaterThan(probe.redPixelCount(inRect: CGRect(x: 160, y: 160, width: 35, height: 35)), 0,
                             "expected the arrowhead at the tip")
    }

    func testArrowheadIsHeavierThanTheTail() throws {
        let probe = try Probe(annotations: [.arrow(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 180, y: 100))])
        let tail = probe.redPixelCount(inRect: CGRect(x: 20, y: 80, width: 30, height: 40))
        let head = probe.redPixelCount(inRect: CGRect(x: 150, y: 80, width: 30, height: 40))
        XCTAssertGreaterThan(head, tail, "the filled head should cover more pixels than the shaft")
    }

    func testTextRendersInk() throws {
        let probe = try Probe(annotations: [.text(origin: CGPoint(x: 20, y: 100), string: "fix this")])
        XCTAssertTrue(probe.isAnyPixelRed)
    }

    func testEmptyTextRendersNothing() throws {
        let probe = try Probe(annotations: [.text(origin: CGPoint(x: 20, y: 100), string: "")])
        XCTAssertFalse(probe.isAnyPixelRed)
    }

    func testBadgeDrawsAFilledDiscAtItsCentre() throws {
        let probe = try Probe(annotations: [.badge(center: CGPoint(x: 100, y: 100), number: 1)])
        XCTAssertGreaterThan(probe.redPixelCount(inRect: CGRect(x: 85, y: 85, width: 30, height: 30)), 50)
    }

    func testStyleKeepsAMinimumStrokeOnTinyImages() {
        let tiny = Style.scaled(to: CGSize(width: 20, height: 20))
        XCTAssertGreaterThanOrEqual(tiny.lineWidth, 1)
    }

    func testPNGEncodingProducesDecodableDataOfTheSameSize() throws {
        let base = try XCTUnwrap(Probe.whiteImage(width: 120, height: 90))
        let boxed = StyledAnnotation(.box(CGRect(x: 10, y: 10, width: 50, height: 50)),
                                     style: .scaled(to: CGSize(width: 120, height: 90)))
        let data = try XCTUnwrap(Renderer.pngData(base: base, annotations: [boxed]))
        XCTAssertGreaterThan(data.count, 0)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 120)
        XCTAssertEqual(decoded.height, 90)
    }

    func testAnnotationsAreDrawnInInsertionOrder() throws {
        // A redact placed after a box must cover the box's ink.
        let probe = try Probe(annotations: [
            .box(CGRect(x: 50, y: 50, width: 60, height: 60)),
            .redact(CGRect(x: 30, y: 30, width: 120, height: 120)),
        ])
        XCTAssertEqual(probe.redPixelCount(inRect: CGRect(x: 30, y: 30, width: 120, height: 120)), 0)
    }
}


final class PerAnnotationStyleTests: XCTestCase {
    private func style(_ color: MarkupColor, _ size: SizeClass = .medium) -> Style {
        .scaled(to: CGSize(width: 200, height: 200), color: color, size: size)
    }

    func testTwoAnnotationsKeepTheirOwnColours() throws {
        let probe = try Probe(styled: [
            StyledAnnotation(.box(CGRect(x: 20, y: 20, width: 60, height: 60)), style: style(.red)),
            StyledAnnotation(.box(CGRect(x: 110, y: 110, width: 60, height: 60)), style: style(.blue)),
        ])
        let left = CGRect(x: 15, y: 15, width: 70, height: 70)
        let right = CGRect(x: 105, y: 105, width: 70, height: 70)

        let isRed: ((UInt8, UInt8, UInt8, UInt8)) -> Bool = { $0.0 > 180 && $0.2 < 90 }
        let isBlue: ((UInt8, UInt8, UInt8, UInt8)) -> Bool = { $0.2 > 180 && $0.0 < 90 }

        XCTAssertGreaterThan(probe.pixelCount(inRect: left, where: isRed), 0)
        XCTAssertEqual(probe.pixelCount(inRect: left, where: isBlue), 0,
                       "the red box must not pick up the blue box's colour")
        XCTAssertGreaterThan(probe.pixelCount(inRect: right, where: isBlue), 0)
        XCTAssertEqual(probe.pixelCount(inRect: right, where: isRed), 0)
    }

    func testRedactionIgnoresTheSelectedColour() throws {
        let probe = try Probe(styled: [
            StyledAnnotation(.redact(CGRect(x: 40, y: 40, width: 60, height: 60)), style: style(.blue)),
        ])
        let inside = probe.color(x: 70, y: 70)
        XCTAssertEqual(inside.r, 0)
        XCTAssertEqual(inside.b, 0)
    }

    func testLargerSizeClassDrawsAHeavierStroke() {
        let size = CGSize(width: 800, height: 600)
        let small = Style.scaled(to: size, size: .small)
        let medium = Style.scaled(to: size, size: .medium)
        let large = Style.scaled(to: size, size: .large)
        XCTAssertLessThan(small.lineWidth, medium.lineWidth)
        XCTAssertLessThan(medium.lineWidth, large.lineWidth)
        XCTAssertLessThan(small.fontSize, medium.fontSize)
        XCTAssertLessThan(medium.fontSize, large.fontSize)
    }

    /// Regression: markup used to scale off the image's short edge, so a wide
    /// strip got a 2px stroke and 11px text while a full-window grab got 16px
    /// and 60px — an 8x swing driven by nothing but crop shape.
    func testMarkupIsTheSameSizeWhateverTheCropShape() {
        let strip = Style.scaled(to: CGSize(width: 1688, height: 202), backingScale: 2)
        let square = Style.scaled(to: CGSize(width: 864, height: 646), backingScale: 2)
        let window = Style.scaled(to: CGSize(width: 2528, height: 1772), backingScale: 2)

        XCTAssertEqual(strip.lineWidth, square.lineWidth)
        XCTAssertEqual(square.lineWidth, window.lineWidth)
        XCTAssertEqual(strip.fontSize, square.fontSize)
        XCTAssertEqual(square.fontSize, window.fontSize)
    }

    func testMarkupTracksTheDisplaysBackingScale() {
        // A Retina grab has twice the pixels for the same on-screen size, so
        // the markup needs twice the pixels to look the same.
        let oneX = Style.scaled(to: CGSize(width: 800, height: 600), backingScale: 1)
        let twoX = Style.scaled(to: CGSize(width: 1600, height: 1200), backingScale: 2)
        XCTAssertEqual(twoX.lineWidth, oneX.lineWidth * 2, accuracy: 1)
        XCTAssertEqual(twoX.fontSize, oneX.fontSize * 2, accuracy: 1)
    }

    func testMarkupIsCappedSoItCannotSwampATinyCrop() {
        let tiny = CGSize(width: 400, height: 40)
        let style = Style.scaled(to: tiny, backingScale: 2, size: .large)
        XCTAssertLessThanOrEqual(style.fontSize, tiny.height * 0.35 + 1,
                                 "text must not overflow a thin crop")
        XCTAssertLessThanOrEqual(style.lineWidth, tiny.height * 0.08 + 1)
    }

    func testAZeroBackingScaleDoesNotCollapseTheStyle() {
        let style = Style.scaled(to: CGSize(width: 800, height: 600), backingScale: 0)
        XCTAssertGreaterThanOrEqual(style.lineWidth, 1)
        XCTAssertGreaterThanOrEqual(style.fontSize, 9)
    }

    func testEveryPaletteColourIsDistinctAndNamed() {
        let names = Set(MarkupColor.palette.map(\.name))
        XCTAssertEqual(names.count, MarkupColor.palette.count)
        for color in MarkupColor.palette {
            XCTAssertEqual(MarkupColor.named(color.name), color)
        }
    }

    func testCyclingColoursVisitsEveryPaletteEntryAndWrapsAround() {
        var seen: [MarkupColor] = []
        var current = MarkupColor.red
        for _ in MarkupColor.palette.indices {
            seen.append(current)
            current = current.next
        }
        XCTAssertEqual(seen.count, MarkupColor.palette.count)
        XCTAssertEqual(Set(seen.map(\.name)).count, MarkupColor.palette.count)
        XCTAssertEqual(current, .red, "cycling all the way round should return to the start")
    }

    func testSizeSteppingClampsAtBothEnds() {
        XCTAssertEqual(SizeClass.small.smaller, .small)
        XCTAssertEqual(SizeClass.large.larger, .large)
        XCTAssertEqual(SizeClass.small.larger, .medium)
        XCTAssertEqual(SizeClass.large.smaller, .medium)
    }
}
