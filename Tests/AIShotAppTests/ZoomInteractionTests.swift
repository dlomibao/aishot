import AIShotCore
import AppKit
import XCTest
@testable import aishot

/// Drives the real editor window: fit mode, resizing, manual zoom, and the
/// on-screen sizes that must not change with zoom.
@MainActor
final class ZoomInteractionTests: XCTestCase {
    private var controller: EditorWindowController!

    override func setUp() async throws {
        controller = EditorWindowController(image: try Self.image(width: 1600, height: 1000)) { _ in }
    }

    override func tearDown() async throws {
        controller.discard()
        controller = nil
    }

    private static func image(width: Int, height: Int) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(ctx.makeImage())
    }

    private var window: NSWindow { controller.window! }

    private var scrollView: NSScrollView {
        window.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!
    }

    private var canvas: CanvasView { scrollView.documentView as! CanvasView }

    /// True when the whole canvas is visible and touches the viewport on at
    /// least one axis — what "fit" means.
    private func assertFits(file: StaticString = #filePath, line: UInt = #line) {
        let expected = Zoom.fit(document: canvas.frame.size, in: scrollView.contentSize)
        XCTAssertEqual(scrollView.magnification, expected, accuracy: 0.01, file: file, line: line)
    }

    private func resizeContent(to size: NSSize) {
        window.setContentSize(size)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func testTheWindowCanBeResized() {
        XCTAssertTrue(window.styleMask.contains(.resizable))
    }

    func testItOpensFittedToTheWindow() {
        assertFits()
    }

    func testResizingRefitsTheImage() {
        let before = scrollView.magnification
        resizeContent(to: NSSize(width: window.contentLayoutRect.width * 1.5,
                                 height: window.contentLayoutRect.height * 1.5))
        XCTAssertGreaterThan(scrollView.magnification, before, "a bigger window should show the image bigger")
        assertFits()
    }

    func testZoomingByHandStopsTheWindowFromRefitting() {
        controller.zoomIn()
        let zoomed = scrollView.magnification
        resizeContent(to: NSSize(width: window.contentLayoutRect.width + 200,
                                 height: window.contentLayoutRect.height + 200))
        XCTAssertEqual(scrollView.magnification, zoomed, accuracy: 0.001,
                       "after a manual zoom, resizing must leave the zoom alone")
    }

    func testZoomToFitResumesRefitting() {
        controller.zoomToActualSize()
        XCTAssertEqual(scrollView.magnification, 1, accuracy: 0.001)
        controller.zoomToFit()
        resizeContent(to: NSSize(width: window.contentLayoutRect.width + 300,
                                 height: window.contentLayoutRect.height + 300))
        assertFits()
    }

    func testZoomInAndOutMoveByOneStep() {
        controller.zoomToActualSize()
        controller.zoomIn()
        XCTAssertEqual(scrollView.magnification, Zoom.stepIn(from: 1), accuracy: 0.001)
        controller.zoomOut()
        controller.zoomOut()
        XCTAssertEqual(scrollView.magnification, Zoom.stepOut(from: 1), accuracy: 0.001)
    }

    func testTheWindowCannotShrinkBelowTheToolbar() {
        resizeContent(to: NSSize(width: 50, height: 50))
        XCTAssertGreaterThanOrEqual(window.contentLayoutRect.width, window.contentMinSize.width - 0.5)
        XCTAssertGreaterThan(window.contentMinSize.width, 300, "the minimum must leave room for the toolbar")
    }

    func testCroppingShrinksTheCanvasToTheCropAndRefits() {
        let fullWidth = canvas.frame.width
        canvas.tool = .crop
        let from = canvas.convert(NSPoint(x: canvas.bounds.width * 0.25, y: canvas.bounds.height * 0.25), to: nil)
        let to = canvas.convert(NSPoint(x: canvas.bounds.width * 0.75, y: canvas.bounds.height * 0.75), to: nil)
        canvas.mouseDown(with: Self.mouse(.leftMouseDown, from, window))
        canvas.mouseDragged(with: Self.mouse(.leftMouseDragged, to, window))
        canvas.mouseUp(with: Self.mouse(.leftMouseUp, to, window))
        canvas.confirmCrop()

        XCTAssertEqual(canvas.frame.width, fullWidth / 2, accuracy: 2, "the canvas is laid out at the crop's actual size")
        assertFits()
    }

    func testShortcutsReachTheZoom() throws {
        controller.zoomToActualSize()
        let plus = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                  characters: "=", charactersIgnoringModifiers: "=",
                                                  isARepeat: false, keyCode: 24))
        XCTAssertTrue(controller.handleZoomShortcut(plus), "⌘= is how ⌘+ is usually typed")
        XCTAssertGreaterThan(scrollView.magnification, 1)
    }

    static func mouse(_ type: NSEvent.EventType, _ point: NSPoint, _ window: NSWindow,
                      _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: 1)!
    }
}

/// The same click must select a shape whatever the zoom. Click tolerance is
/// measured on screen, so at 25% it covers four times as many canvas points.
@MainActor
final class ZoomedSelectionTests: XCTestCase {
    func testClickToleranceStaysConstantOnScreenWhenZoomedOut() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Zoom.minimum
        let canvas = CanvasView(image: try XCTUnwrap(ctx.makeImage()), frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = canvas
        window.contentView?.addSubview(scrollView)
        scrollView.magnification = 0.25

        func at(_ x: CGFloat, _ y: CGFloat) -> NSPoint { canvas.convert(NSPoint(x: x, y: y), to: nil) }

        canvas.tool = .box
        canvas.mouseDown(with: ZoomInteractionTests.mouse(.leftMouseDown, at(100, 100), window))
        canvas.mouseDragged(with: ZoomInteractionTests.mouse(.leftMouseDragged, at(300, 200), window))
        canvas.mouseUp(with: ZoomInteractionTests.mouse(.leftMouseUp, at(300, 200), window))

        // 16 canvas points outside the left edge is 4 points on screen at 25%:
        // inside the 6-point tolerance, so it must select.
        canvas.tool = .select
        canvas.mouseDown(with: ZoomInteractionTests.mouse(.leftMouseDown, at(84, 150), window))
        canvas.mouseUp(with: ZoomInteractionTests.mouse(.leftMouseUp, at(84, 150), window))
        XCTAssertTrue(canvas.hasSelection, "a click 4 screen points from the edge should select at any zoom")
    }
}
