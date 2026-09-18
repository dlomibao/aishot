import CoreGraphics
import XCTest
@testable import AIShotCore

final class CanvasTransformTests: XCTestCase {
    func testScaleIsImagePixelsPerViewPoint() {
        let t = CanvasTransform(imageSize: CGSize(width: 800, height: 600),
                                viewSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(t.scale, 2.0, accuracy: 0.0001)
    }

    func testViewPointMapsToImagePixels() {
        let t = CanvasTransform(imageSize: CGSize(width: 800, height: 600),
                                viewSize: CGSize(width: 400, height: 300))
        let p = t.imagePoint(fromView: CGPoint(x: 100, y: 50))
        XCTAssertEqual(p.x, 200, accuracy: 0.0001)
        XCTAssertEqual(p.y, 100, accuracy: 0.0001)
    }

    func testRoundTripThroughBothTransformsIsIdentity() {
        let t = CanvasTransform(imageSize: CGSize(width: 1234, height: 987),
                                viewSize: CGSize(width: 617, height: 493.5))
        let original = CGPoint(x: 321, y: 77)
        let back = t.viewPoint(fromImage: t.imagePoint(fromView: original))
        XCTAssertEqual(back.x, original.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, original.y, accuracy: 0.0001)
    }

    func testFittedViewSizeShrinksToMaxPreservingAspect() {
        let fitted = CanvasTransform.fittedViewSize(imageSize: CGSize(width: 2000, height: 1000),
                                                    maxSize: CGSize(width: 800, height: 800))
        XCTAssertEqual(fitted.width, 800, accuracy: 0.0001)
        XCTAssertEqual(fitted.height, 400, accuracy: 0.0001)
    }

    func testFittedViewSizeNeverEnlargesASmallImage() {
        let fitted = CanvasTransform.fittedViewSize(imageSize: CGSize(width: 100, height: 80),
                                                    maxSize: CGSize(width: 800, height: 800))
        XCTAssertEqual(fitted.width, 100, accuracy: 0.0001)
        XCTAssertEqual(fitted.height, 80, accuracy: 0.0001)
    }

    func testFittedViewSizeIsConstrainedByTheTighterAxis() {
        let fitted = CanvasTransform.fittedViewSize(imageSize: CGSize(width: 1000, height: 2000),
                                                    maxSize: CGSize(width: 900, height: 400))
        XCTAssertEqual(fitted.height, 400, accuracy: 0.0001)
        XCTAssertEqual(fitted.width, 200, accuracy: 0.0001)
    }
}

final class AnnotationDocumentTests: XCTestCase {
    func testBadgeNumbersIncrementInOrderOfPlacement() {
        var doc = AnnotationDocument()
        doc.add(.badge(center: .zero, number: doc.nextBadgeNumber))
        doc.add(.badge(center: .zero, number: doc.nextBadgeNumber))
        XCTAssertEqual(doc.nextBadgeNumber, 3)
    }

    func testUndoRemovesTheMostRecentAnnotation() {
        var doc = AnnotationDocument()
        doc.add(.box(CGRect(x: 0, y: 0, width: 10, height: 10)))
        doc.add(.box(CGRect(x: 5, y: 5, width: 10, height: 10)))
        doc.undo()
        XCTAssertEqual(doc.annotations.count, 1)
    }

    func testUndoingPastTheBeginningIsSafe() {
        var doc = AnnotationDocument()
        doc.undo()
        XCTAssertTrue(doc.annotations.isEmpty)
    }

    func testUndoingABadgeFreesItsNumberForReuse() {
        var doc = AnnotationDocument()
        doc.add(.badge(center: .zero, number: doc.nextBadgeNumber))
        doc.add(.badge(center: .zero, number: doc.nextBadgeNumber))
        doc.undo()
        XCTAssertEqual(doc.nextBadgeNumber, 2)
    }
}
