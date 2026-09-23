import AIShotCore
import AppKit
import ImageIO
import XCTest
@testable import aishot

/// Drives the real CanvasView with synthetic mouse events, so selection,
/// moving, Shift and the highlighter are tested through the same code the
/// app runs, not through a copy of its logic.
@MainActor
final class CanvasInteractionTests: XCTestCase {
    private var window: NSWindow!
    private var canvas: CanvasView!

    override func setUp() async throws {
        let size = 400, height = 300
        let ctx = try XCTUnwrap(CGContext(data: nil, width: size, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: height))
        let base = try XCTUnwrap(ctx.makeImage())

        // Point size equals pixel size, so view and image coordinates match.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size, height: height),
                          styleMask: [.titled], backing: .buffered, defer: false)
        canvas = CanvasView(image: base, frame: NSRect(x: 0, y: 0, width: size, height: height))
        window.contentView?.addSubview(canvas)
        canvas.color = .red
        canvas.sizeClass = .medium
    }

    // MARK: - Helpers

    private func event(_ type: NSEvent.EventType, _ point: CGPoint, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }

    private func drag(_ from: CGPoint, _ to: CGPoint, _ flags: NSEvent.ModifierFlags = []) {
        canvas.mouseDown(with: event(.leftMouseDown, from, flags))
        for step in 1...5 {
            let t = CGFloat(step) / 5
            let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            canvas.mouseDragged(with: event(.leftMouseDragged, point, flags))
        }
        canvas.mouseUp(with: event(.leftMouseUp, to, flags))
    }

    private func click(_ point: CGPoint, _ flags: NSEvent.ModifierFlags = []) {
        canvas.mouseDown(with: event(.leftMouseDown, point, flags))
        canvas.mouseUp(with: event(.leftMouseUp, point, flags))
    }

    private func exported(_ size: ExportSize = .original) throws -> CGImage {
        let data = try XCTUnwrap(canvas.exportPNG(size: size))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return buffer
    }

    /// Red pixels in a rect with a bottom-left origin, matching the view.
    private func redCount(in rect: CGRect) throws -> Int {
        let image = try exported()
        let px = pixels(of: image)
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = ((image.height - 1 - y) * image.width + x) * 4
                if px[i] > 180 && px[i + 1] < 110 && px[i + 2] < 110 { count += 1 }
            }
        }
        return count
    }

    private func isYellowTinted(at point: CGPoint) throws -> Bool {
        let image = try exported()
        let px = pixels(of: image)
        let i = ((image.height - 1 - Int(point.y)) * image.width + Int(point.x)) * 4
        return px[i] > 230 && px[i + 2] < 230
    }

    private let oldLeftEdge = CGRect(x: 96, y: 120, width: 8, height: 60)
    private let newLeftEdge = CGRect(x: 156, y: 120, width: 8, height: 60)

    private func drawBoxAndMoveItRight() {
        canvas.tool = .box
        drag(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200))
        canvas.tool = .select
        drag(CGPoint(x: 101, y: 150), CGPoint(x: 161, y: 150))
    }

    // MARK: - Selection and moving

    func testClickingInsideAnOutlinedBoxDoesNotSelectIt() {
        canvas.tool = .box
        drag(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200))
        canvas.tool = .select
        click(CGPoint(x: 150, y: 150))
        XCTAssertFalse(canvas.hasSelection)
    }

    func testDraggingASelectedShapeMovesIt() throws {
        drawBoxAndMoveItRight()
        XCTAssertTrue(canvas.hasSelection)
        XCTAssertGreaterThan(try redCount(in: newLeftEdge), 0)
        XCTAssertEqual(try redCount(in: oldLeftEdge), 0)
    }

    func testOneUndoReversesAWholeDrag() throws {
        drawBoxAndMoveItRight()
        canvas.undo()
        XCTAssertGreaterThan(try redCount(in: oldLeftEdge), 0)
        XCTAssertEqual(try redCount(in: newLeftEdge), 0)
        XCTAssertFalse(canvas.hasSelection, "a stale selection index could point at the wrong shape")
        canvas.redo()
        XCTAssertGreaterThan(try redCount(in: newLeftEdge), 0)
    }

    func testDeletingTheSelectionIsUndoable() throws {
        drawBoxAndMoveItRight()
        canvas.deleteSelection()
        XCTAssertEqual(try redCount(in: CGRect(x: 0, y: 0, width: 400, height: 300)), 0)
        canvas.undo()
        XCTAssertGreaterThan(try redCount(in: newLeftEdge), 0)
    }

    func testCommandClickSelectsWithoutLeavingTheDrawingTool() {
        drawBoxAndMoveItRight()
        canvas.tool = .arrow
        click(CGPoint(x: 161, y: 150), [.command])
        XCTAssertTrue(canvas.hasSelection)
        XCTAssertEqual(canvas.tool, .arrow)
    }

    func testEscapeStyleClearingReportsWhetherThereWasASelection() {
        drawBoxAndMoveItRight()
        XCTAssertTrue(canvas.clearSelection())
        XCTAssertFalse(canvas.clearSelection(), "a second esc should fall through to the next thing")
    }

    // MARK: - Drawing

    func testShiftKeepsAnArrowOnItsRow() throws {
        canvas.tool = .arrow
        drag(CGPoint(x: 20, y: 40), CGPoint(x: 120, y: 60), [.shift])
        XCTAssertGreaterThan(try redCount(in: CGRect(x: 60, y: 30, width: 20, height: 20)), 0)
        XCTAssertEqual(try redCount(in: CGRect(x: 100, y: 55, width: 20, height: 20)), 0)
    }

    func testAClickWithTheArrowToolAddsNothing() throws {
        canvas.tool = .arrow
        drag(CGPoint(x: 20, y: 40), CGPoint(x: 120, y: 40))
        click(CGPoint(x: 300, y: 250))
        canvas.undo()
        XCTAssertEqual(try redCount(in: CGRect(x: 60, y: 30, width: 20, height: 20)), 0,
                       "undo should remove the real arrow, so the click added nothing on top")
    }

    func testTheHighlighterTintsWithoutHidingTheBackground() throws {
        canvas.tool = .highlight
        canvas.color = .yellow
        drag(CGPoint(x: 250, y: 20), CGPoint(x: 380, y: 60))
        let image = try exported()
        let px = pixels(of: image)
        let i = ((image.height - 1 - 40) * image.width + 300) * 4
        XCTAssertLessThan(px[i + 2], 230, "yellow tint shows")
        XCTAssertGreaterThan(px[i + 2], 100, "and stays translucent")
    }

    func testShiftMakesTheHighlightSquare() throws {
        canvas.tool = .highlight
        canvas.color = .yellow
        drag(CGPoint(x: 250, y: 20), CGPoint(x: 300, y: 40), [.shift])
        XCTAssertTrue(try isYellowTinted(at: CGPoint(x: 275, y: 60)), "a 50×20 drag becomes 50×50")
        XCTAssertFalse(try isYellowTinted(at: CGPoint(x: 275, y: 80)))
    }

    // MARK: - Cropping

    /// Regression: after a small crop the window stays wide enough for the
    /// toolbar, and the canvas drew the whole screenshot shifted by the crop.
    /// With views no longer clipping by default, the uncropped image showed on
    /// both sides of the cropped one.
    func testACroppedCanvasNeverPaintsBeyondItsEdges() throws {
        let red = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        red.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        red.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        let small = CanvasView(image: try XCTUnwrap(red.makeImage()), frame: NSRect(x: 250, y: 100, width: 100, height: 100))
        window.contentView?.addSubview(small)

        small.tool = .crop
        small.mouseDown(with: event(.leftMouseDown, CGPoint(x: 275, y: 125), []))
        small.mouseDragged(with: event(.leftMouseDragged, CGPoint(x: 325, y: 175), []))
        small.mouseUp(with: event(.leftMouseUp, CGPoint(x: 325, y: 175), []))
        small.confirmCrop()

        // Draw into a bitmap wider than the canvas, with a dirty rect to match,
        // the way AppKit may call draw() when a view does not clip.
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 600, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
        bitmap.translateBy(x: 250, y: 100)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
        small.draw(NSRect(x: -250, y: -100, width: 600, height: 300))
        NSGraphicsContext.restoreGraphicsState()

        let px = pixels(of: try XCTUnwrap(bitmap.makeImage()))
        func isRed(_ x: Int, _ y: Int) -> Bool {
            let i = ((299 - y) * 600 + x) * 4
            return px[i] > 200 && px[i + 1] < 80
        }
        XCTAssertTrue(isRed(300, 150), "the cropped region itself is drawn")
        XCTAssertFalse(isRed(230, 150), "nothing may be drawn left of the canvas")
        XCTAssertFalse(isRed(370, 150), "nothing may be drawn right of the canvas")
    }

    // MARK: - Export

    func testASmallImageIsNotEnlargedByTheCopyCap() throws {
        let image = try exported(.long1280)
        XCTAssertEqual(image.width, 400)
        XCTAssertEqual(image.height, 300)
    }
}
