import XCTest
@testable import LatticeKit

/// The solver must plan around each app's real minimum size. This is the difference between a
/// tidy Space and the ragged, gappy layouts you get when the tiler asks for a tile the app
/// silently refuses.
final class MinimumSizePlanningTests: XCTestCase {

    private let content = CGRect(x: 8, y: 41, width: 1712, height: 1036)
    private let gap: CGFloat = 8

    private func solve(_ count: Int,
                       _ layout: LayoutKind,
                       minimums: [CGSize],
                       content: CGRect? = nil) -> TilingSolver.Solution {
        TilingSolver.solve(count: count,
                           content: content ?? self.content,
                           gap: gap,
                           layout: layout,
                           minimum: CGSize(width: 220, height: 140),
                           minimums: minimums)
    }

    func testNoMinimumsKeepsTheChosenLayout() {
        let solution = solve(4, .dwindle, minimums: [])
        XCTAssertEqual(solution.layout, .dwindle)
        XCTAssertEqual(solution.placedCount, 4)
    }

    func testLargeAppMinimumDegradesToAFittingGrid() {
        // Four windows that each refuse to be smaller than 840x620 cannot sit four-across on
        // this display in a dwindle split; the solver must pick a grid that fits.
        let big = CGSize(width: 840, height: 620)
        let solution = solve(4, .dwindle, minimums: Array(repeating: big, count: 4))

        XCTAssertNotEqual(solution.layout, .dwindle)
        for frame in solution.frames.compactMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(frame.width, big.width - 0.5, "narrower than the app allows")
            XCTAssertGreaterThanOrEqual(frame.height, big.height - 0.5, "shorter than the app allows")
        }
    }

    func testImpossibleMinimumsPlaceOnlyWhatFits() {
        // Five windows that need 900x800 simply do not fit two-up on a 1712x1036 display.
        let huge = CGSize(width: 900, height: 800)
        let solution = solve(5, .dwindle, minimums: Array(repeating: huge, count: 5))

        let placed = solution.frames.compactMap { $0 }
        XCTAssertLessThan(placed.count, 5, "must leave windows alone rather than ask for the impossible")
        XCTAssertGreaterThan(placed.count, 0)
        XCTAssertGreaterThan(solution.skipped, 0)
        for frame in placed {
            XCTAssertGreaterThanOrEqual(frame.width, 80, "never below the WindowServer floor")
            XCTAssertGreaterThanOrEqual(frame.height, 60)
        }
    }

    func testMixedMinimumsRespectTheLargestKnownConstraint() {
        let minimums = [CGSize(width: 900, height: 700),
                        CGSize(width: 300, height: 200),
                        CGSize(width: 300, height: 200)]
        let solution = solve(3, .columns, minimums: minimums)
        // Whatever layout wins, every frame must satisfy its own window's minimum.
        for (index, frame) in solution.frames.enumerated() {
            guard let frame, index < minimums.count else { continue }
            XCTAssertGreaterThanOrEqual(frame.width, minimums[index].width - 0.5)
            XCTAssertGreaterThanOrEqual(frame.height, minimums[index].height - 0.5)
        }
    }

    func testPlanningStaysInsideTheContentRect() {
        let solution = solve(6, .dwindle,
                             minimums: Array(repeating: CGSize(width: 380, height: 380), count: 6))
        for frame in solution.frames.compactMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(frame.minX, content.minX - 1)
            XCTAssertGreaterThanOrEqual(frame.minY, content.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxX, content.maxX + 1)
            XCTAssertLessThanOrEqual(frame.maxY, content.maxY + 1)
        }
    }
}
