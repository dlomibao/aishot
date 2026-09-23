import CoreGraphics
import ImageIO
import XCTest
@testable import AIShotCore

final class UndoRedoTests: XCTestCase {
    private let style = Style.scaled(to: CGSize(width: 400, height: 400), backingScale: 1)
    private let boxA = Annotation.box(CGRect(x: 10, y: 10, width: 50, height: 50))
    private let boxB = Annotation.box(CGRect(x: 100, y: 100, width: 50, height: 50))

    func testRedoRestoresWhatUndoRemoved() {
        var doc = AnnotationDocument()
        doc.add(boxA, style: style)
        doc.undo()
        XCTAssertTrue(doc.annotations.isEmpty)
        doc.redo()
        XCTAssertEqual(doc.annotations.map(\.shape), [boxA])
    }

    func testANewEditClearsTheRedoHistory() {
        var doc = AnnotationDocument()
        doc.add(boxA, style: style)
        doc.undo()
        doc.add(boxB, style: style)
        XCTAssertFalse(doc.canRedo, "redo would otherwise resurrect a branch you abandoned")
        doc.redo()
        XCTAssertEqual(doc.annotations.map(\.shape), [boxB])
    }

    func testUndoAndRedoOnAnEmptyHistoryAreSafe() {
        var doc = AnnotationDocument()
        XCTAssertFalse(doc.undo())
        XCTAssertFalse(doc.redo())
        XCTAssertFalse(doc.canUndo)
    }

    func testRedoingACropReportsTheBoundsChange() {
        var doc = AnnotationDocument()
        doc.crop(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(doc.undo())
        XCTAssertTrue(doc.redo())
        XCTAssertEqual(doc.cropRect, CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    func testAMoveIsOneUndoStep() {
        var doc = AnnotationDocument()
        doc.add(boxA, style: style)
        doc.move(at: 0, by: CGVector(dx: 30, dy: -5))
        XCTAssertEqual(doc.annotations[0].shape, .box(CGRect(x: 40, y: 5, width: 50, height: 50)))
        doc.undo()
        XCTAssertEqual(doc.annotations[0].shape, boxA, "one undo should put it back where it started")
    }

    func testAZeroLengthMoveAddsNoUndoStep() {
        var doc = AnnotationDocument()
        doc.add(boxA, style: style)
        doc.move(at: 0, by: .zero)
        doc.undo()
        XCTAssertTrue(doc.annotations.isEmpty, "the only undo step should be the add")
    }

    func testRemovingAShapeCanBeUndone() {
        var doc = AnnotationDocument()
        doc.add(boxA, style: style)
        doc.add(boxB, style: style)
        doc.remove(at: 0)
        XCTAssertEqual(doc.annotations.map(\.shape), [boxB])
        doc.undo()
        XCTAssertEqual(doc.annotations.map(\.shape), [boxA, boxB], "it returns to its original stacking position")
    }

    func testOutOfRangeEditsAreIgnored() {
        var doc = AnnotationDocument()
        doc.add(boxA, style: style)
        doc.move(at: 5, by: CGVector(dx: 1, dy: 1))
        doc.remove(at: -1)
        XCTAssertEqual(doc.annotations.map(\.shape), [boxA])
        doc.undo()
        XCTAssertFalse(doc.canUndo, "ignored edits must not add undo steps")
    }

    func testDeletingAMiddleBadgeDoesNotReuseANumberStillOnTheCanvas() {
        var doc = AnnotationDocument()
        for _ in 0..<3 { doc.add(.badge(center: .zero, number: doc.nextBadgeNumber), style: style) }
        doc.remove(at: 0)
        XCTAssertEqual(doc.nextBadgeNumber, 4, "badges 2 and 3 remain, so the next one is 4")
    }
}

final class HitTestingTests: XCTestCase {
    private let style = Style.scaled(to: CGSize(width: 400, height: 400), backingScale: 1)

    private func styled(_ shape: Annotation) -> StyledAnnotation { StyledAnnotation(shape, style: style) }

    func testAnArrowIsHitNearItsShaftButNotFarFromIt() {
        let arrow = styled(.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)))
        XCTAssertTrue(arrow.hitTest(CGPoint(x: 50, y: 3), tolerance: 4))
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 50, y: 30), tolerance: 4))
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 160, y: 0), tolerance: 4), "past the tip is not the arrow")
    }

    func testABoxIsHitOnItsEdgeNotInItsMiddle() {
        let box = styled(.box(CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertTrue(box.hitTest(CGPoint(x: 0, y: 50), tolerance: 4))
        XCTAssertFalse(box.hitTest(CGPoint(x: 50, y: 50), tolerance: 4),
                       "a box drawn around something must not swallow clicks inside it")
    }

    func testFilledShapesAreHitAnywhereInside() {
        XCTAssertTrue(styled(.redact(CGRect(x: 0, y: 0, width: 100, height: 100))).hitTest(CGPoint(x: 50, y: 50), tolerance: 0))
        XCTAssertTrue(styled(.highlight(CGRect(x: 0, y: 0, width: 100, height: 20))).hitTest(CGPoint(x: 50, y: 10), tolerance: 0))
        XCTAssertTrue(styled(.badge(center: CGPoint(x: 50, y: 50), number: 1)).hitTest(CGPoint(x: 50, y: 50), tolerance: 0))
    }

    func testTextIsHitAcrossTheLinesItActuallyWrapsTo() {
        let text = styled(.text(box: CGRect(x: 0, y: 380, width: 80, height: 20),
                                string: "long enough to wrap onto several lines"))
        let wrappedBelowTheBox = CGPoint(x: 10, y: text.bounds.minY + 2)
        XCTAssertLessThan(text.bounds.minY, 380, "wrapped text grows below the box it was typed in")
        XCTAssertTrue(text.hitTest(wrappedBelowTheBox, tolerance: 0))
    }

    func testTheTopmostShapeWinsWhenShapesOverlap() {
        let shapes = [styled(.redact(CGRect(x: 0, y: 0, width: 100, height: 100))),
                      styled(.highlight(CGRect(x: 0, y: 0, width: 100, height: 100)))]
        XCTAssertEqual(shapes.indexOfShape(at: CGPoint(x: 50, y: 50), tolerance: 0), 1)
    }

    func testEmptySpaceHitsNothing() {
        let shapes = [styled(.box(CGRect(x: 0, y: 0, width: 50, height: 50)))]
        XCTAssertNil(shapes.indexOfShape(at: CGPoint(x: 300, y: 300), tolerance: 4))
    }

    func testTranslationMovesEveryKindOfShape() {
        let offset = CGVector(dx: 10, dy: -20)
        XCTAssertEqual(Annotation.arrow(from: .zero, to: CGPoint(x: 5, y: 5)).translated(by: offset),
                       .arrow(from: CGPoint(x: 10, y: -20), to: CGPoint(x: 15, y: -15)))
        XCTAssertEqual(Annotation.badge(center: .zero, number: 3).translated(by: offset),
                       .badge(center: CGPoint(x: 10, y: -20), number: 3))
        XCTAssertEqual(Annotation.text(box: .zero, string: "a").translated(by: offset),
                       .text(box: CGRect(x: 10, y: -20, width: 0, height: 0), string: "a"))
    }
}

final class ConstrainTests: XCTestCase {
    func testANearlyHorizontalDragSnapsFlat() {
        let end = Constrain.snapTo45Degrees(from: .zero, to: CGPoint(x: 100, y: 8))
        XCTAssertEqual(end.y, 0, accuracy: 0.0001)
        XCTAssertEqual(end.x, hypot(100, 8), accuracy: 0.0001, "the dragged length is kept")
    }

    func testADiagonalDragSnapsToExactly45Degrees() {
        let end = Constrain.snapTo45Degrees(from: .zero, to: CGPoint(x: 100, y: 90))
        XCTAssertEqual(end.x, end.y, accuracy: 0.0001)
    }

    func testSnappingWorksInEveryDirection() {
        let end = Constrain.snapTo45Degrees(from: .zero, to: CGPoint(x: -5, y: -100))
        XCTAssertEqual(end.x, 0, accuracy: 0.0001)
        XCTAssertLessThan(end.y, 0)
    }

    func testAZeroLengthDragIsLeftAlone() {
        XCTAssertEqual(Constrain.snapTo45Degrees(from: CGPoint(x: 3, y: 3), to: CGPoint(x: 3, y: 3)), CGPoint(x: 3, y: 3))
    }

    func testSquareUsesTheLongerSideAndKeepsTheDragDirection() {
        XCTAssertEqual(Constrain.square(from: .zero, to: CGPoint(x: 80, y: -30)), CGPoint(x: 80, y: -80))
        XCTAssertEqual(Constrain.square(from: .zero, to: CGPoint(x: -20, y: 60)), CGPoint(x: -60, y: 60))
    }
}

final class ExportSizeTests: XCTestCase {
    func testARetinaWindowGrabIsCappedOnItsLongEdge() {
        let fitted = ExportSize.long1568.fittedSize(for: CGSize(width: 2528, height: 1772))
        XCTAssertEqual(fitted.width, 1568)
        XCTAssertEqual(fitted.height, (1772 * 1568 / 2528.0).rounded())
    }

    func testATallImageIsCappedOnItsHeight() {
        let fitted = ExportSize.long1280.fittedSize(for: CGSize(width: 800, height: 3000))
        XCTAssertEqual(fitted.height, 1280)
    }

    func testASmallCropIsNeverEnlarged() {
        let size = CGSize(width: 600, height: 200)
        XCTAssertEqual(ExportSize.long1280.fittedSize(for: size), size)
    }

    func testOriginalLeavesEverySizeAlone() {
        let size = CGSize(width: 6000, height: 4000)
        XCTAssertEqual(ExportSize.original.fittedSize(for: size), size)
    }

    func testTheCopyDefaultIs1568() {
        XCTAssertEqual(ExportSize.defaultForCopy, .long1568)
    }

    func testResizedImageHasTheFittedPixelDimensions() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 3000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())
        let resized = try XCTUnwrap(Renderer.resized(image, to: .long1568))
        XCTAssertEqual(resized.width, 1568)
        XCTAssertEqual(resized.height, 523)
    }

    func testCopiedPNGIsExportedAtTheChosenSize() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let base = try XCTUnwrap(ctx.makeImage())
        let data = try XCTUnwrap(Renderer.pngData(base: base, annotations: [], crop: nil, size: .long1280))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, 1280)
        XCTAssertEqual(decoded.height, 640)
    }
}

final class HighlightRenderingTests: XCTestCase {
    private func centrePixel(highlighting background: CGFloat) throws -> (r: UInt8, g: UInt8, b: UInt8) {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: background, green: background, blue: background, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let base = try XCTUnwrap(ctx.makeImage())
        let style = Style.scaled(to: CGSize(width: 40, height: 40), backingScale: 1, color: .yellow)
        let out = try XCTUnwrap(Renderer.render(base: base, annotations: [
            StyledAnnotation(.highlight(CGRect(x: 0, y: 0, width: 40, height: 40)), style: style),
        ]))
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { raw in
            let probe = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            probe.draw(out, in: CGRect(x: -20, y: -20, width: 40, height: 40))
        }
        return (px[0], px[1], px[2])
    }

    func testAHighlightTintsAWhiteBackgroundWithoutCoveringIt() throws {
        let p = try centrePixel(highlighting: 1)
        XCTAssertLessThan(p.b, 235, "the yellow tint should show on white")
        XCTAssertGreaterThan(p.b, 100, "but stay translucent so text underneath reads")
    }

    /// Multiply blending would leave black untouched, making the highlight
    /// invisible on a dark editor theme.
    func testAHighlightIsStillVisibleOnADarkBackground() throws {
        let p = try centrePixel(highlighting: 0.08)
        XCTAssertGreaterThan(Int(p.r), 60, "yellow must visibly lift a dark background")
    }
}
