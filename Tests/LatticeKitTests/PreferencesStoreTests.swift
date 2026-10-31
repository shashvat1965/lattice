import XCTest
@testable import LatticeKit

final class PreferencesStoreTests: XCTestCase {

    func testEveryObserverReceivesChanges() {
        let store = PreferencesStore.shared
        let original = store.prefs

        var first = 0
        var second = 0
        var third = 0
        let a = store.observe { _ in first += 1 }
        let b = store.observe { _ in second += 1 }
        let c = store.observe { _ in third += 1 }
        defer {
            store.unobserve(a); store.unobserve(b); store.unobserve(c)
            store.replace(original)
        }

        store.update { $0.gap = 12 }
        // notify() is synchronous on the main thread.
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
        XCTAssertEqual(third, 1)

        store.unobserve(b)
        store.update { $0.gap = 13 }
        XCTAssertEqual(first, 2)
        XCTAssertEqual(second, 1, "removed observer must not fire")
        XCTAssertEqual(third, 2)
    }

    func testUnknownKeysDoNotWipePreferences() throws {
        // A file written by an older build: only two keys.
        let json = #"{"gap": 14, "layout": "grid"}"#
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.gap, 14)
        XCTAssertEqual(decoded.layout, .grid)
        XCTAssertEqual(decoded.outerGap, Preferences().outerGap)
        XCTAssertFalse(decoded.bindings.isEmpty, "defaults must survive a partial file")
    }

    func testPerSpaceLayoutsFallBackToDefault() {
        var prefs = Preferences()
        prefs.layout = .grid
        let space = SpaceID(42)
        XCTAssertEqual(prefs.layout(for: space), .grid)
        XCTAssertFalse(prefs.hasOwnLayout(space))

        prefs.setLayout(.master, for: space)
        XCTAssertEqual(prefs.layout(for: space), .master)
        XCTAssertTrue(prefs.hasOwnLayout(space))
        XCTAssertEqual(prefs.layout(for: SpaceID(43)), .grid, "other Spaces keep the default")

        prefs.clearLayoutOverrides()
        XCTAssertEqual(prefs.layout(for: space), .grid)
    }

    func testAppRulesAndHelpers() {
        var prefs = Preferences()
        prefs.unmanagedBundleIDs = ["com.example.terminal"]
        XCTAssertTrue(prefs.isUnmanaged("com.example.terminal"))
        XCTAssertFalse(prefs.isUnmanaged("com.example.other"))

        var rule = AppRule(bundleID: "com.example.chat", name: "Chat")
        rule.float = true
        rule.layout = .columns
        prefs.rules = [rule]
        XCTAssertTrue(prefs.shouldFloat("com.example.chat"))
        XCTAssertEqual(prefs.rule(for: "com.example.chat")?.layout, .columns)
        XCTAssertEqual(prefs.rule(for: "com.example.chat")?.summary, "float · columns")
    }

    func testDisplayOverridesFallBack() {
        var prefs = Preferences()
        prefs.gap = 8
        prefs.outerGap = 8
        let display = DisplayID(7)
        XCTAssertEqual(prefs.innerGap(for: display), 8)

        prefs.displayOverrides[String(display.raw)] = DisplayOverride(gap: 20, outerGap: 30)
        XCTAssertEqual(prefs.innerGap(for: display), 20)
        XCTAssertEqual(prefs.outerPadding(for: display), 30)
        XCTAssertEqual(prefs.innerGap(for: DisplayID(9)), 8)
    }
}

final class TilingGeometryTests: XCTestCase {

    private func display(width: CGFloat = 1440, height: CGFloat = 900, visibleTop: CGFloat = 25) -> DisplayInfo {
        DisplayInfo(id: DisplayID(1),
                    frame: CGRect(x: 0, y: 0, width: width, height: height),
                    visibleFrame: CGRect(x: 0, y: visibleTop, width: width, height: height - visibleTop),
                    name: "Test",
                    hasNotch: false,
                    scale: 2)
    }

    func testContentRectHonoursOuterGapAndEdges() {
        var prefs = Preferences()
        prefs.gap = 8
        prefs.outerGap = 12
        prefs.edges = Margin(top: 4, leading: 6, bottom: 2, trailing: 10)
        let rect = TilingGeometry.contentRect(for: display(), prefs: prefs)

        XCTAssertEqual(rect.minX, 6 + 12, accuracy: 0.6)
        XCTAssertEqual(rect.minY, 25 + 4 + 12, accuracy: 0.6)
        XCTAssertEqual(rect.maxX, 1440 - 10 - 12, accuracy: 0.6)
        XCTAssertEqual(rect.maxY, 900 - 2 - 12, accuracy: 0.6)
    }

    func testContentRectNeverCollapses() {
        var prefs = Preferences()
        prefs.outerGap = 2000
        prefs.edges = Margin(2000)
        let rect = TilingGeometry.contentRect(for: display(), prefs: prefs)
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
    }

    func testHardMinimumIsRespected() {
        XCTAssertGreaterThanOrEqual(TilingGeometry.hardMinimumSize.width, 80)
        XCTAssertGreaterThanOrEqual(TilingGeometry.hardMinimumSize.height, 60)
    }
}
