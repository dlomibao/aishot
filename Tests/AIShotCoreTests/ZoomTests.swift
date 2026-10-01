import CoreGraphics
import XCTest
@testable import AIShotCore

final class ZoomTests: XCTestCase {
    func testFitShrinksALargeDocumentToTheTighterAxis() {
        let m = Zoom.fit(document: CGSize(width: 2000, height: 1000), in: CGSize(width: 1000, height: 800))
        XCTAssertEqual(m, 0.5, accuracy: 0.0001)
    }

    func testFitEnlargesASmallDocumentWhenTheWindowIsBigger() {
        let m = Zoom.fit(document: CGSize(width: 200, height: 100), in: CGSize(width: 800, height: 800))
        XCTAssertEqual(m, 4, accuracy: 0.0001)
    }

    func testFitIsClampedToTheZoomRange() {
        XCTAssertEqual(Zoom.fit(document: CGSize(width: 10, height: 10), in: CGSize(width: 5000, height: 5000)),
                       Zoom.maximum)
        XCTAssertEqual(Zoom.fit(document: CGSize(width: 100_000, height: 100_000), in: CGSize(width: 100, height: 100)),
                       Zoom.minimum)
    }

    func testFitWithAnEmptyViewportOrDocumentFallsBackToActualSize() {
        XCTAssertEqual(Zoom.fit(document: .zero, in: CGSize(width: 800, height: 600)), 1)
        XCTAssertEqual(Zoom.fit(document: CGSize(width: 800, height: 600), in: .zero), 1)
    }

    func testSteppingInFromActualSizeGoesToTheNextStep() {
        XCTAssertEqual(Zoom.stepIn(from: 1), 1.25, accuracy: 0.0001)
        XCTAssertEqual(Zoom.stepOut(from: 1), 0.75, accuracy: 0.0001)
    }

    /// A fit level is rarely a step value; stepping from it should still land
    /// on the neighbouring round number, not skip one or stay put.
    func testSteppingFromBetweenStepsLandsOnTheNeighbours() {
        XCTAssertEqual(Zoom.stepIn(from: 0.6), 0.67, accuracy: 0.0001)
        XCTAssertEqual(Zoom.stepOut(from: 0.6), 0.5, accuracy: 0.0001)
    }

    func testSteppingStopsAtTheEndsOfTheRange() {
        XCTAssertEqual(Zoom.stepIn(from: Zoom.maximum), Zoom.maximum)
        XCTAssertEqual(Zoom.stepOut(from: Zoom.minimum), Zoom.minimum)
    }

    func testPercentLabelRounds() {
        XCTAssertEqual(Zoom.percentLabel(0.666), "67%")
        XCTAssertEqual(Zoom.percentLabel(1), "100%")
    }
}
