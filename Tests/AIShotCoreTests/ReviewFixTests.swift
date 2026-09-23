import CoreGraphics
import Foundation
import XCTest
@testable import AIShotCore

final class DegenerateShapeTests: XCTestCase {
    func testAClickSizedArrowIsDegenerate() {
        XCTAssertTrue(Annotation.arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 12)).isDegenerate(minimum: 6))
    }

    func testARealArrowIsKept() {
        XCTAssertFalse(Annotation.arrow(from: .zero, to: CGPoint(x: 40, y: 0)).isDegenerate(minimum: 6))
    }

    func testAnArrowExactlyAtTheMinimumIsKept() {
        XCTAssertFalse(Annotation.arrow(from: .zero, to: CGPoint(x: 6, y: 0)).isDegenerate(minimum: 6))
    }

    /// A long, thin box is a deliberate underline; only a click-sized one is
    /// a stray click.
    func testALongThinBoxIsKeptAsAnUnderline() {
        XCTAssertFalse(Annotation.box(CGRect(x: 0, y: 0, width: 200, height: 1)).isDegenerate(minimum: 6))
    }

    func testAClickSizedBoxIsDegenerate() {
        XCTAssertTrue(Annotation.box(CGRect(x: 0, y: 0, width: 3, height: 2)).isDegenerate(minimum: 6))
    }

    func testAThinHighlightAcrossALineIsKept() {
        XCTAssertFalse(Annotation.highlight(CGRect(x: 0, y: 0, width: 300, height: 4)).isDegenerate(minimum: 6))
    }

    func testASmallButVisibleBoxIsKept() {
        XCTAssertFalse(Annotation.box(CGRect(x: 0, y: 0, width: 8, height: 8)).isDegenerate(minimum: 6))
    }

    func testATinyRedactionIsDegenerate() {
        XCTAssertTrue(Annotation.redact(CGRect(x: 0, y: 0, width: 2, height: 2)).isDegenerate(minimum: 6))
    }

    func testEmptyTextIsDegenerate() {
        XCTAssertTrue(Annotation.text(box: CGRect(x: 0, y: 0, width: 100, height: 20), string: "").isDegenerate(minimum: 6))
    }

    func testBadgesAreNeverDegenerate() {
        XCTAssertFalse(Annotation.badge(center: .zero, number: 1).isDegenerate(minimum: 6))
    }
}

final class ColourLightnessTests: XCTestCase {
    func testWhiteAndYellowNeedADarkBackdrop() {
        XCTAssertTrue(MarkupColor.white.isLight)
        XCTAssertTrue(MarkupColor.yellow.isLight)
    }

    func testDarkerPaletteColoursReadOnALightBackdrop() {
        for colour in [MarkupColor.red, .blue, .green, .orange] {
            XCTAssertFalse(colour.isLight, "\(colour.name) should use the light backdrop")
        }
    }

    func testLuminanceSpansZeroToOne() {
        XCTAssertEqual(MarkupColor.white.relativeLuminance, 1, accuracy: 0.001)
        XCTAssertEqual(MarkupColor(name: "black", red: 0, green: 0, blue: 0).relativeLuminance, 0, accuracy: 0.001)
    }
}

final class UniqueFileNameTests: XCTestCase {
    private let base = URL(fileURLWithPath: "/tmp/shots/aishot-20260923-101010.png")

    func testAFreeNameIsReturnedUnchanged() {
        XCTAssertEqual(FileNaming.uniqueURL(for: base, exists: { _ in false }), base)
    }

    func testACollisionGetsASuffixBeforeTheExtension() {
        let result = FileNaming.uniqueURL(for: base, exists: { $0 == self.base })
        XCTAssertEqual(result.lastPathComponent, "aishot-20260923-101010-2.png")
        XCTAssertEqual(result.deletingLastPathComponent(), base.deletingLastPathComponent())
    }

    func testSeveralCollisionsFindTheNextFreeSuffix() {
        let taken: Set<String> = ["aishot-20260923-101010.png", "aishot-20260923-101010-2.png", "aishot-20260923-101010-3.png"]
        let result = FileNaming.uniqueURL(for: base, exists: { taken.contains($0.lastPathComponent) })
        XCTAssertEqual(result.lastPathComponent, "aishot-20260923-101010-4.png")
    }

    func testANameWithoutAnExtensionStillGetsASuffix() {
        let bare = URL(fileURLWithPath: "/tmp/shots/notes")
        let result = FileNaming.uniqueURL(for: bare, exists: { $0 == bare })
        XCTAssertEqual(result.lastPathComponent, "notes-2")
    }
}
