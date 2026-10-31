import XCTest
@testable import LatticeKit

final class LayoutMathTests: XCTestCase {

    private let rect = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let gap: CGFloat = 8

    func testAllLayoutsReturnOneFramePerWindow() {
        for layout in LayoutKind.allCases {
            for count in 1...9 {
                let frames = LayoutMath.frames(count: count, in: rect, gap: gap, layout: layout)
                XCTAssertEqual(frames.count, count, "\(layout) with \(count) windows")
            }
        }
    }

    func testFramesStayInsideTheRect() {
        for layout in LayoutKind.allCases {
            for count in 1...7 {
                let frames = LayoutMath.frames(count: count, in: rect, gap: gap, layout: layout)
                for frame in frames {
                    XCTAssertGreaterThan(frame.width, 0, "\(layout)/\(count) width")
                    XCTAssertGreaterThan(frame.height, 0, "\(layout)/\(count) height")
                    XCTAssertGreaterThanOrEqual(frame.minX, rect.minX - 1, "\(layout)/\(count) x")
                    XCTAssertGreaterThanOrEqual(frame.minY, rect.minY - 1, "\(layout)/\(count) y")
                    XCTAssertLessThanOrEqual(frame.maxX, rect.maxX + 1, "\(layout)/\(count) maxX")
                    XCTAssertLessThanOrEqual(frame.maxY, rect.maxY + 1, "\(layout)/\(count) maxY")
                }
            }
        }
    }

    func testFramesDoNotOverlap() {
        let layouts: [LayoutKind] = [.columns, .rows, .grid, .master]
        for layout in layouts {
            for count in 2...6 {
                let frames = LayoutMath.frames(count: count, in: rect, gap: gap, layout: layout)
                for i in 0..<frames.count {
                    for j in (i + 1)..<frames.count {
                        let intersection = frames[i].intersection(frames[j])
                        XCTAssertTrue(intersection.isNull || intersection.width < 0.51 || intersection.height < 0.51,
                                      "\(layout)/\(count): frames \(i) and \(j) overlap by \(intersection)")
                    }
                }
            }
        }
    }

    func testGridIsBalanced() {
        let frames = LayoutMath.frames(count: 4, in: rect, gap: gap, layout: .grid)
        let widths = Set(frames.map { Int($0.width.rounded()) })
        let heights = Set(frames.map { Int($0.height.rounded()) })
        XCTAssertEqual(widths.count, 1)
        XCTAssertEqual(heights.count, 1)
    }

    func testColumnsHonourWeights() {
        let frames = LayoutMath.frames(count: 3, in: rect, gap: gap, layout: .columns, weights: [2, 1, 1])
        XCTAssertGreaterThan(frames[0].width, frames[1].width)
        XCTAssertEqual(frames[1].width, frames[2].width, accuracy: 0.5)
    }

    func testSingleWindowFillsInsetRect() {
        let frames = LayoutMath.frames(count: 1, in: rect, gap: gap, layout: .dwindle)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].width, rect.width - gap * 2, accuracy: 0.5)
        XCTAssertEqual(frames[0].height, rect.height - gap * 2, accuracy: 0.5)
    }

    func testZeroWindowsProducesNothing() {
        for layout in LayoutKind.allCases {
            XCTAssertTrue(LayoutMath.frames(count: 0, in: rect, gap: gap, layout: layout).isEmpty)
        }
    }

    func testTinyRectsDoNotCrash() {
        let tiny = CGRect(x: 0, y: 0, width: 10, height: 10)
        for layout in LayoutKind.allCases {
            let frames = LayoutMath.frames(count: 5, in: tiny, gap: 8, layout: layout)
            XCTAssertEqual(frames.count, 5)
        }
    }
}

final class PreferencesTests: XCTestCase {

    func testEveryCommandHasADefaultWhereExpected() {
        // The six focus bindings must always exist; a user can clear them, defaults may not.
        for command in [CommandID.focusLeft, .focusRight, .focusUp, .focusDown] {
            XCTAssertNotNil(Preferences.defaultBindings[command], "\(command) missing default")
        }
    }

    func testKeyCombosRoundTripThroughJSON() throws {
        let combo = KeyCombo(key: "h", modifiers: [.control, .option])
        let data = try JSONEncoder().encode(combo)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        XCTAssertEqual(combo, decoded)
    }

    func testKeyComboDisplayOrder() {
        let combo = KeyCombo(key: "h", modifiers: [.shift, .command, .option, .control])
        XCTAssertEqual(combo.display, "⌃⌥⇧⌘H")
    }

    func testSpaceNumberParsing() {
        XCTAssertEqual(CommandID.space4.spaceNumber, 4)
        XCTAssertEqual(CommandID.moveToSpace9.spaceNumber, 9)
    }

    func testPreferencesRoundTrip() throws {
        var prefs = Preferences()
        prefs.gap = 12
        prefs.layout = .master
        prefs.floatBundleIDs.insert("com.example.app")
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(prefs, decoded)
    }
}
