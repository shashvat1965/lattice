import XCTest
@testable import LatticeKit

/// Regression: with more windows than their minimum sizes allow, the solver used to fall into
/// the 80x60 safety net first and lay nine 800 pt apps out as nine 156 pt columns. That looked
/// broken, and every window refused the write. The app-minimum branch must win.
final class CrowdedSpaceTests: XCTestCase {

    private let content = CGRect(x: 12, y: 45, width: 1472, height: 901)

    func testNineLargeAppsAreNotSqueezedIntoColumns() {
        let big = CGSize(width: 800, height: 600)
        let solution = TilingSolver.solve(count: 9,
                                          content: content,
                                          gap: 12,
                                          layout: .dwindle,
                                          minimum: CGSize(width: 220, height: 140),
                                          minimums: Array(repeating: big, count: 9))

        XCTAssertLessThan(solution.placedCount, 9, "nine 800x600 apps cannot fit one screen")
        XCTAssertGreaterThan(solution.skipped, 0)
        for frame in solution.frames.compactMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(frame.width, big.width - 0.5,
                                        "asked for a width the app will refuse")
            XCTAssertGreaterThanOrEqual(frame.height, big.height - 0.5,
                                        "asked for a height the app will refuse")
            XCTAssertGreaterThan(frame.width, 200, "a wall of 156 pt columns is not a layout")
        }
    }

    func testCrowdedSpaceStillUsesTheDisplay() {
        let solution = TilingSolver.solve(count: 9,
                                          content: content,
                                          gap: 12,
                                          layout: .dwindle,
                                          minimum: CGSize(width: 220, height: 140),
                                          minimums: Array(repeating: CGSize(width: 800, height: 600), count: 9))
        XCTAssertGreaterThanOrEqual(solution.placedCount, 1)
        XCTAssertEqual(solution.layout, .grid)
    }

    func testTileAnywayKeepsTheChosenLayoutAndPlacesEveryWindow() {
        let solution = TilingSolver.solve(count: 9,
                                          content: content,
                                          gap: 12,
                                          layout: .dwindle,
                                          minimum: CGSize(width: 220, height: 140),
                                          minimums: Array(repeating: CGSize(width: 800, height: 600), count: 9),
                                          respectMinimums: false)
        XCTAssertEqual(solution.layout, .dwindle)
        XCTAssertEqual(solution.placedCount, 9, "tile-anyway must not leave windows out")
        XCTAssertEqual(solution.skipped, 0)
        XCTAssertNil(solution.note)
    }
}
