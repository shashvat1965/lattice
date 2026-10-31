import Foundation
import AppKit
import ApplicationServices

/// `LATTICE_SELFTEST=1` runs the engine without a human clicking anything:
/// enumerate, print the diagnostics snapshot, reconcile, print the frames afterwards, exit.
///
///   LATTICE_SELFTEST=1 ./build/Lattice.app/Contents/MacOS/Lattice
///
/// Everything is also written to ~/Library/Logs/Lattice/lattice.log so the run can be
/// inspected after the terminal is gone.
public enum LatticeSelfTest {

    nonisolated(unsafe) private static var hasRun = false

    public static var isRequested: Bool {
        ProcessInfo.processInfo.environment["LATTICE_SELFTEST"] == "1"
    }

    public static func run(engine: WindowEngine) {
        guard isRequested, !hasRun else { return }
        hasRun = true

        var report: [String] = []
        report.append("SELFTEST start (LATTICE_SELFTEST=1)")

        // Pure layout/geometry/motion checks first: they need no Accessibility grant, so they
        // always run and always verify that preferences reach the frames.
        let pure = TilingSelfTest.run()
        report.append(contentsOf: pure.lines)
        report.append("")
        report.append("tiling self-test: \(pure.passed) passed, \(pure.failed) failed")

        let trusted = AXIsProcessTrusted()
        report.append("accessibilityTrusted: \(trusted)")

        let tiler = TilerHolder.shared ?? Tiler(engine: engine)

        if trusted {
            _ = AXPerf.take()
            let enumerateStart = CFAbsoluteTimeGetCurrent()
            engine.start()
            let enumerateMS = (CFAbsoluteTimeGetCurrent() - enumerateStart) * 1000
            let enumerateCalls = AXPerf.take()
            report.append(String(format: "enumerate: %d windows in %.1f ms (%d ax calls)",
                                 engine.windows.count, enumerateMS, enumerateCalls))

            report.append("")
            report.append("--- snapshot before reconcile ---")
            report.append(LatticeDiagnostics.snapshot())

            if tiler.isSuspended || !tiler.prefs.enabled {
                report.append("NOTE: tiling is paused (suspended=\(tiler.isSuspended), enabled=\(tiler.prefs.enabled)); reconcile will be a no-op")
            }

            _ = AXPerf.take()
            let reconcileStart = CFAbsoluteTimeGetCurrent()
            tiler.reconcile(animated: false)
            let reconcileMS = (CFAbsoluteTimeGetCurrent() - reconcileStart) * 1000
            let reconcileCalls = AXPerf.take()
            report.append(String(format: "reconcile: %.1f ms (%d ax calls) for %d windows",
                                 reconcileMS, reconcileCalls, engine.windows.count))

            // Let deferred verification land, then measure the frames that actually stuck.
            RunLoop.current.run(until: Date().addingTimeInterval(0.55))

            report.append("")
            report.append("--- frames after reconcile ---")
            for window in engine.windows.values.sorted(by: { $0.id.raw < $1.id.raw }) {
                let actual = window.axElement?.frame ?? .zero
                let flags = [
                    engine.isStubborn(window.id) ? "stubborn" : nil,
                    tiler.isFloating(window.id) ? "floating" : nil,
                ].compactMap { $0 }.joined(separator: ",")
                report.append(String(format: "  %@ pid=%d app=%@ space=%llu display=%u frame=(%.0f,%.0f %.0fx%.0f) actual=(%.0f,%.0f %.0fx%.0f) %@",
                                     window.id.description, window.pid, window.appName,
                                     window.space.raw, window.display.raw,
                                     window.frame.origin.x, window.frame.origin.y,
                                     window.frame.width, window.frame.height,
                                     actual.origin.x, actual.origin.y, actual.width, actual.height,
                                     flags))
            }

            report.append("")
            report.append("--- snapshot after reconcile ---")
            report.append(LatticeDiagnostics.snapshot())

            // Which Space-move path does this machine allow?
            report.append("")
            report.append("spaceMove: symbol=\(SkyLight.hasMoveSymbol) " +
                          "setCurrentSpace=\(SkyLight.hasSetCurrentSpaceSymbol) " +
                          "callerTrusted=\(trusted)")
        } else {
            report.append("Skipping enumeration/reconcile: Accessibility permission is not granted.")
            report.append("")
            report.append(LatticeDiagnostics.snapshot())
        }

        report.append("SELFTEST done")
        let text = report.joined(separator: "\n")
        print(text)
        Log.info(text)
        exit(0)
    }
}

/// Pure verification of the tiling engine against `Preferences`. Every assertion here is about
/// a preference that used to be stored and ignored; the output is a table the lead can read
/// without granting Accessibility to anything.
public enum TilingSelfTest {

    public struct Outcome {
        public var lines: [String]
        public var passed: Int
        public var failed: Int
        public var timingMilliseconds: Double
    }

    // MARK: - Harness

    private struct Harness {
        var lines: [String] = []
        var passed = 0
        var failed = 0

        mutating func check(_ name: String, _ condition: Bool, detail: @autoclosure () -> String = "") {
            if condition { passed += 1 } else { failed += 1 }
            let extra = detail()
            lines.append("  [\(condition ? "PASS" : "FAIL")] \(name)" + (extra.isEmpty ? "" : " — \(extra)"))
        }

        mutating func table(_ header: String) {
            lines.append(header)
        }
    }

    private struct Profile {
        var name: String
        var masterRatio: Double
        var stackPeek: CGFloat
        var gridColumns: Int
    }

    private static let profiles: [Profile] = [
        Profile(name: "defaults", masterRatio: 0.62, stackPeek: 14, gridColumns: 0),
        Profile(name: "ratio 0.40", masterRatio: 0.40, stackPeek: 14, gridColumns: 0),
        Profile(name: "ratio 0.50", masterRatio: 0.50, stackPeek: 14, gridColumns: 0),
        Profile(name: "ratio 0.80", masterRatio: 0.80, stackPeek: 14, gridColumns: 0),
        Profile(name: "ratio 0.95→0.80", masterRatio: 0.95, stackPeek: 14, gridColumns: 0),
        Profile(name: "peek 0", masterRatio: 0.62, stackPeek: 0, gridColumns: 0),
        Profile(name: "peek 4", masterRatio: 0.62, stackPeek: 4, gridColumns: 0),
        Profile(name: "peek 30", masterRatio: 0.62, stackPeek: 30, gridColumns: 0),
        Profile(name: "cols 1", masterRatio: 0.62, stackPeek: 14, gridColumns: 1),
        Profile(name: "cols 2", masterRatio: 0.62, stackPeek: 14, gridColumns: 2),
        Profile(name: "cols 5", masterRatio: 0.62, stackPeek: 14, gridColumns: 5),
    ]

    // MARK: - Entry point

    public static func run() -> Outcome {
        var harness = Harness()
        let clockStart = CFAbsoluteTimeGetCurrent()
        let display = standardDisplay()
        let prefs = Preferences()

        harness.lines.append("--- tiling engine self-test (preferences honoured) ---")
        harness.lines.append("display: \(Int(display.frame.width))x\(Int(display.frame.height)) " +
                             "visible=\(Int(display.visibleFrame.width))x\(Int(display.visibleFrame.height)) " +
                             "gap=\(Int(prefs.gap)) outerGap=\(Int(prefs.outerGap)) " +
                             "minTile=\(Int(prefs.minTiledWidth))x\(Int(prefs.minTiledHeight))")
        let content = TilingGeometry.contentRect(for: display, prefs: prefs)
        harness.lines.append("content: \(format(content))")
        harness.lines.append("")

        layoutProfiles(into: &harness, display: display, content: content, base: prefs)
        frameTable(into: &harness, display: display, content: content, prefs: prefs)
        insertionPolicies(into: &harness)
        minimumSize(into: &harness)
        perDisplayOverrides(into: &harness)
        paddingAndNotch(into: &harness)
        weightsAndTuning(into: &harness, display: display, base: prefs)
        motion(into: &harness)

        // Timing: the whole solver path for a 12-window Space, all six layouts, averaged.
        let timing = measure(display: display, prefs: prefs)
        harness.lines.append("")
        harness.lines.append(String(format: "timing: solver for 12 windows, %.3f ms/call (all layouts, 200 iterations each)", timing))

        let elapsed = (CFAbsoluteTimeGetCurrent() - clockStart) * 1000
        harness.lines.append(String(format: "self-test total: %.1f ms", elapsed))
        return Outcome(lines: harness.lines, passed: harness.passed, failed: harness.failed,
                       timingMilliseconds: timing)
    }

    // MARK: - Layout × tuning

    private static func layoutProfiles(into harness: inout Harness,
                                       display: DisplayInfo,
                                       content: CGRect,
                                       base: Preferences) {
        harness.lines.append("table: every layout × every tuning value (5 windows, focus 1)")
        harness.lines.append("  " + pad("case", 20) + pad("layout", 10) + pad("n", 3)
                             + pad("minW", 6) + pad("minH", 6) + pad("gaps", 6)
                             + pad("inside", 8) + "result")
        for layout in LayoutKind.allCases {
            for profile in profiles {
                var prefs = base
                prefs.masterRatio = profile.masterRatio
                prefs.stackPeek = profile.stackPeek
                prefs.gridColumns = profile.gridColumns

                var caseCheck = Harness()
                let gap = max(0, prefs.innerGap(for: display.id))
                let focus = 1
                let solution = TilingSolver.solve(count: 5,
                                                  content: content,
                                                  gap: gap,
                                                  layout: layout,
                                                  weights: [],
                                                  focusIndex: focus,
                                                  masterRatio: prefs.masterRatio,
                                                  stackPeek: prefs.stackPeek,
                                                  gridColumns: prefs.gridColumns,
                                                  minimum: TilingGeometry.effectiveMinimum(prefs))
                let frames = solution.frames
                let placed = frames.compactMap { $0 }

                let name = "\(layout.rawValue) \(profile.name)"
                caseCheck.check("\(name): one frame per window", frames.count == 5,
                                detail: "got \(frames.count)")
                caseCheck.check("\(name): every window placed", placed.count == 5,
                                detail: "placed \(placed.count), note \(solution.note ?? "none")")
                caseCheck.check("\(name): frames inside the content rect",
                                placed.allSatisfy { inside($0, content) },
                                detail: placed.map(format).joined(separator: " "))
                caseCheck.check("\(name): no tile under 80x60",
                                placed.allSatisfy { $0.width >= 80 - 0.5 && $0.height >= 60 - 0.5 },
                                detail: "min \(String(format: "%.0fx%.0f", solution.minimumSide, solution.minimumSide))")

                if layout != .stack {
                    caseCheck.check("\(name): no overlapping tiles",
                                    !overlaps(placed),
                                    detail: "overlap detected")
                }

                var gapOK = "n/a"
                switch layout {
                case .columns:
                    let ok = columnGaps(placed, gap: gap)
                    gapOK = ok ? "yes" : "no"
                    caseCheck.check("\(name): inner gap between columns is exactly \(Int(gap))",
                                    ok, detail: "")
                case .rows:
                    let ok = rowGaps(placed, gap: gap)
                    gapOK = ok ? "yes" : "no"
                    caseCheck.check("\(name): inner gap between rows is exactly \(Int(gap))",
                                    ok, detail: "")
                case .grid:
                    let columns = prefs.gridColumns > 0 ? min(prefs.gridColumns, 5)
                                                        : Int(ceil(sqrt(5.0)))
                    let xs = Set(placed.map { Int($0.minX.rounded()) }).count
                    let ok = firstRowGaps(placed, columns: columns, gap: gap)
                    gapOK = ok ? "yes" : "no"
                    caseCheck.check("\(name): grid uses \(columns) column(s)",
                                    xs == columns, detail: "found \(xs) x positions")
                    caseCheck.check("\(name): grid gaps are exactly \(Int(gap))",
                                    ok, detail: "")
                case .master:
                    let ratio = min(0.8, max(0.4, prefs.masterRatio))
                    let expected = (content.width - gap) * CGFloat(ratio)
                    let ok = placed.count > 1 && abs(placed[1].minX - placed[0].maxX - gap) <= 0.6
                    gapOK = ok ? "yes" : "no"
                    caseCheck.check("\(name): master width is \(String(format: "%.0f", ratio * 100))%",
                                    abs(placed[0].width - expected) <= 1,
                                    detail: String(format: "master %.1f, expected %.1f", placed[0].width, expected))
                    caseCheck.check("\(name): master/stack gap is exactly \(Int(gap))",
                                    ok, detail: "")
                case .stack:
                    let peek = prefs.stackPeek
                    let exact = placed.enumerated().allSatisfy { index, frame in
                        let rank = ((index - focus) % 5 + 5) % 5
                        let expectedWidth = content.width - 2 * peek * CGFloat(rank)
                        let expectedHeight = content.height - 1.2 * peek * CGFloat(rank)
                        return abs(frame.width - expectedWidth) <= 0.6
                            && abs(frame.height - expectedHeight) <= 0.6
                    }
                    caseCheck.check("\(name): peek \(Int(peek)) drives the inset",
                                    exact, detail: placed.map { String(format: "%.0fx%.0f", $0.width, $0.height) }.joined(separator: " "))
                case .dwindle:
                    caseCheck.check("\(name): dwindle tiles stay inside",
                                    placed.allSatisfy { inside($0, content) }, detail: "")
                }

                let minWidth = placed.map(\.width).min() ?? 0
                let minHeight = placed.map(\.height).min() ?? 0
                let result = caseCheck.failed == 0 ? "PASS" : "FAIL (\(caseCheck.failed))"
                harness.lines.append("  " + pad(name, 20) + pad(layout.rawValue, 10)
                                     + pad("5", 3)
                                     + pad(String(format: "%.0f", minWidth), 6)
                                     + pad(String(format: "%.0f", minHeight), 6)
                                     + pad(gapOK, 6)
                                     + pad(placed.allSatisfy { inside($0, content) } ? "yes" : "no", 8)
                                     + result)

                if caseCheck.failed > 0 {
                    harness.lines.append(contentsOf: caseCheck.lines.filter { $0.contains("[FAIL]") })
                }
                harness.passed += caseCheck.passed
                harness.failed += caseCheck.failed
            }
        }
        harness.lines.append("")
    }

    // MARK: - Frame table

    private static func frameTable(into harness: inout Harness,
                                   display: DisplayInfo,
                                   content: CGRect,
                                   prefs: Preferences) {
        harness.lines.append("table: resulting frames (5 windows, focus 1, gap \(Int(prefs.gap)))")
        harness.lines.append("  " + pad("layout", 10) + "frames x,y wxh")
        for layout in LayoutKind.allCases {
            let gap = max(0, prefs.innerGap(for: display.id))
            let solution = TilingSolver.solve(count: 5, content: content, gap: gap, layout: layout,
                                              focusIndex: 1, masterRatio: prefs.masterRatio,
                                              stackPeek: prefs.stackPeek, gridColumns: prefs.gridColumns,
                                              minimum: TilingGeometry.effectiveMinimum(prefs))
            let text = solution.frames.enumerated().map { index, frame in
                guard let frame else { return "\(index):deferred" }
                return "\(index):" + format(frame)
            }.joined(separator: "  ")
            harness.lines.append("  " + pad(layout.rawValue, 10) + text)
        }
        harness.lines.append("")
    }

    // MARK: - Insertion policy

    private static func insertionPolicies(into harness: inout Harness) {
        harness.lines.append("insertion policy (order [101,102,103], focused 102, new 104)")
        let a = WindowID(101), b = WindowID(102), c = WindowID(103), d = WindowID(104)
        let expected: [InsertionPolicy: [WindowID]] = [
            .end: [a, b, c, d],
            .master: [d, a, b, c],
            .afterFocused: [a, b, d, c],
        ]
        for policy in InsertionPolicy.allCases {
            let result = TilerOrdering.inserting([d], into: [a, b, c], policy: policy, focused: b)
            harness.check("insertion \(policy.rawValue) -> \(result.order.map(\.raw))",
                          result.order == expected[policy],
                          detail: "expected \(expected[policy]!.map(\.raw))")
        }
        let multi = TilerOrdering.inserting([d, WindowID(105)], into: [a, b, c],
                                            policy: .afterFocused, focused: b)
        harness.check("insertion afterFocused keeps a run together",
                      multi.order == [a, b, d, WindowID(105), c], detail: "\(multi.order.map(\.raw))")
        let noFocus = TilerOrdering.inserting([d], into: [a, b, c], policy: .afterFocused, focused: nil)
        harness.check("insertion afterFocused falls back to the end without focus",
                      noFocus.order == [a, b, c, d], detail: "\(noFocus.order.map(\.raw))")
        harness.check("afterFocused anchors on the previous tile when the new window took focus",
                      TilerOrdering.anchor(currentFocus: d, in: [a, b, c], last: b) == b)
        harness.check("afterFocused prefers the live focused tile when it is already ordered",
                      TilerOrdering.anchor(currentFocus: c, in: [a, b, c], last: b) == c)
        harness.lines.append("")
    }

    // MARK: - Minimum size degradation

    private static func minimumSize(into harness: inout Harness) {
        harness.lines.append("minimum tile size (§5): degrade instead of impossible frames")
        var prefs = Preferences()
        prefs.minTiledWidth = 220
        prefs.minTiledHeight = 140
        prefs.layout = .master

        let small = DisplayInfo(id: DisplayID(21),
                                frame: CGRect(x: 0, y: 0, width: 640, height: 400),
                                visibleFrame: CGRect(x: 0, y: 25, width: 640, height: 375),
                                name: "small")
        let smallContent = TilingGeometry.contentRect(for: small, prefs: prefs)
        let smallSolution = TilingSolver.solve(count: 9, content: smallContent,
                                               gap: prefs.innerGap(for: small.id),
                                               layout: .master,
                                               masterRatio: prefs.masterRatio,
                                               stackPeek: prefs.stackPeek,
                                               gridColumns: prefs.gridColumns,
                                               minimum: TilingGeometry.effectiveMinimum(prefs))
        harness.check("small display (640x400, 9 windows) reports degradation",
                      smallSolution.note != nil,
                      detail: smallSolution.note ?? "nil")
        harness.check("small display tiles every window at >= 80x60",
                      smallSolution.frames.compactMap { $0 }.count == 9
                        && smallSolution.frames.compactMap { $0 }.allSatisfy { $0.width >= 80 && $0.height >= 60 },
                      detail: smallSolution.frames.compactMap { $0 }.map(format).joined(separator: " "))
        harness.check("small display frames stay inside content",
                      smallSolution.frames.compactMap { $0 }.allSatisfy { inside($0, smallContent) })

        let tiny = DisplayInfo(id: DisplayID(22),
                               frame: CGRect(x: 0, y: 0, width: 300, height: 200),
                               visibleFrame: CGRect(x: 0, y: 25, width: 300, height: 175),
                               name: "tiny")
        let tinyContent = TilingGeometry.contentRect(for: tiny, prefs: prefs)
        let tinySolution = TilingSolver.solve(count: 9, content: tinyContent,
                                              gap: prefs.innerGap(for: tiny.id),
                                              layout: .master,
                                              masterRatio: prefs.masterRatio,
                                              stackPeek: prefs.stackPeek,
                                              gridColumns: prefs.gridColumns,
                                              minimum: TilingGeometry.effectiveMinimum(prefs))
        harness.check("tiny display (300x200) defers what cannot fit",
                      tinySolution.skipped == 3,
                      detail: "skipped \(tinySolution.skipped), note \(tinySolution.note ?? "nil")")
        harness.check("tiny display places only >= 80x60 frames",
                      tinySolution.frames.compactMap { $0 }.allSatisfy { $0.width >= 80 && $0.height >= 60 },
                      detail: tinySolution.frames.compactMap { $0 }.map(format).joined(separator: " "))
        harness.lines.append("")
    }

    // MARK: - Per-display overrides

    private static func perDisplayOverrides(into harness: inout Harness) {
        harness.lines.append("per-display overrides (§10): gap, outerGap, layout")
        var prefs = Preferences()
        prefs.gap = 8
        prefs.outerGap = 8
        prefs.layout = .dwindle
        let display = standardDisplay()
        let overridden = DisplayID(77)
        prefs.displayOverrides[String(overridden.raw)] = DisplayOverride(gap: 4, outerGap: 20,
                                                                         layout: .master,
                                                                         respectDock: true)

        let content = TilingGeometry.contentRect(for: display.with(id: overridden), prefs: prefs)
        harness.check("override outerGap 20 reaches the content rect",
                      content.minX == display.visibleFrame.minX + 20
                        && content.minY == display.visibleFrame.minY + 20,
                      detail: format(content))
        harness.check("override gap is 4, global gap stays 8",
                      prefs.innerGap(for: overridden) == 4 && prefs.innerGap(for: display.id) == 8)
        harness.check("override layout wins over the Space layout",
                      TilingGeometry.resolvedLayout(space: SpaceID(9), display: display.with(id: overridden), prefs: prefs) == .master,
                      detail: TilingGeometry.resolvedLayout(space: SpaceID(9), display: display.with(id: overridden), prefs: prefs).rawValue)
        harness.check("display without an override falls back to the global values",
                      prefs.innerGap(for: display.id) == 8
                        && prefs.outerPadding(for: display.id) == 8
                        && TilingGeometry.resolvedLayout(space: SpaceID(9), display: display, prefs: prefs) == .dwindle)

        let gap = prefs.innerGap(for: overridden)
        let solution = TilingSolver.solve(count: 4, content: content, gap: gap,
                                          layout: TilingGeometry.resolvedLayout(space: SpaceID(9), display: display.with(id: overridden), prefs: prefs),
                                          masterRatio: prefs.masterRatio,
                                          stackPeek: prefs.stackPeek,
                                          gridColumns: prefs.gridColumns,
                                          minimum: TilingGeometry.effectiveMinimum(prefs))
        let frames = solution.frames.compactMap { $0 }
        harness.check("override layout produced master frames",
                      frames.count == 4 && solution.layout == .master,
                      detail: "layout \(solution.layout.rawValue)")
        harness.check("override gap is exact between master and stack",
                      frames.count == 4 && frames[1].minX - frames[0].maxX == gap,
                      detail: String(format: "gap %.1f, expected %.1f", frames.count == 4 ? frames[1].minX - frames[0].maxX : -1, gap))
        harness.lines.append("")
    }

    // MARK: - Edges, menu bar, notch

    private static func paddingAndNotch(into harness: inout Harness) {
        harness.lines.append("padding, menu bar, dock, notch (§1)")
        var prefs = Preferences()
        prefs.outerGap = 8
        prefs.edges = Margin(top: 10, leading: 12, bottom: 6, trailing: 14)
        let display = standardDisplay()
        let content = TilingGeometry.contentRect(for: display, prefs: prefs)
        let expected = CGRect(x: 20,
                              y: display.visibleFrame.minY + 10 + 8,
                              width: display.visibleFrame.width - 12 - 14 - 16,
                              height: display.visibleFrame.height - 10 - 6 - 16)
        harness.check("edge margins are applied per side and outerGap is added",
                      near(content, expected),
                      detail: "got \(format(content)), expected \(format(expected))")

        var ignoreDock = prefs
        ignoreDock.respectDock = false
        let docked = DisplayInfo(id: DisplayID(23),
                                 frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                 visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 800),
                                 name: "docked")
        let withDock = TilingGeometry.contentRect(for: docked, prefs: prefs)
        let withoutDock = TilingGeometry.contentRect(for: docked, prefs: ignoreDock)
        harness.check("respectDock=false lets tiles use the docked strip",
                      withoutDock.height > withDock.height,
                      detail: "\(format(withDock)) vs \(format(withoutDock))")

        var notchPrefs = Preferences()
        notchPrefs.outerGap = 8
        notchPrefs.respectMenuBar = false
        notchPrefs.respectDock = false
        let notched = DisplayInfo(id: DisplayID(31),
                                  frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                  visibleFrame: CGRect(x: 0, y: 38, width: 1512, height: 944),
                                  name: "notched", hasNotch: true)
        let notchContent = TilingGeometry.contentRect(for: notched, prefs: notchPrefs)
        harness.check("notch is never tiled under, even with respectMenuBar off",
                      notchContent.minY >= notched.visibleFrame.minY + 8,
                      detail: format(notchContent))

        var menuPrefs = Preferences()
        menuPrefs.outerGap = 8
        menuPrefs.respectDock = false
        menuPrefs.respectMenuBar = true
        let menuContent = TilingGeometry.contentRect(for: display, prefs: menuPrefs)
        harness.check("respectMenuBar keeps the menu bar clear with respectDock off",
                      menuContent.minY >= display.visibleFrame.minY + 8,
                      detail: format(menuContent))

        var underMenuPrefs = Preferences()
        underMenuPrefs.outerGap = 8
        underMenuPrefs.respectDock = true
        underMenuPrefs.respectMenuBar = false
        let underMenu = TilingGeometry.contentRect(for: display, prefs: underMenuPrefs)
        harness.check("respectMenuBar=false extends under the menu bar while the Dock stays respected",
                      abs(underMenu.minY - (display.frame.minY + 8)) < 0.5,
                      detail: format(underMenu))

        let gap = max(0, prefs.innerGap(for: display.id))
        let solution = TilingSolver.solve(count: 3, content: content, gap: gap, layout: .columns,
                                          minimum: TilingGeometry.effectiveMinimum(prefs))
        let frames = solution.frames.compactMap { $0 }
        harness.check("tiles sit inside visibleFrame minus outer padding minus edges",
                      frames.allSatisfy { $0.minX >= display.visibleFrame.minX + 12 + 8 - 0.5
                        && $0.maxX <= display.visibleFrame.maxX - 14 - 8 + 0.5
                        && $0.minY >= display.visibleFrame.minY + 10 + 8 - 0.5
                        && $0.maxY <= display.visibleFrame.maxY - 6 - 8 + 0.5 },
                      detail: frames.map(format).joined(separator: " "))
        harness.lines.append("")
    }

    // MARK: - Weights

    private static func weightsAndTuning(into harness: inout Harness,
                                         display: DisplayInfo,
                                         base: Preferences) {
        harness.lines.append("weights and tuning interaction")
        let content = TilingGeometry.contentRect(for: display, prefs: base)
        let gap = max(0, base.innerGap(for: display.id))
        let uniform = TilingSolver.solve(count: 3, content: content, gap: gap, layout: .master,
                                         weights: [1, 1, 1],
                                         masterRatio: 0.62,
                                         minimum: TilingGeometry.effectiveMinimum(base))
        let widened = TilingSolver.solve(count: 3, content: content, gap: gap, layout: .master,
                                         weights: [3, 1, 1],
                                         masterRatio: 0.62,
                                         minimum: TilingGeometry.effectiveMinimum(base))
        harness.check("growing the master weight grows the master tile",
                      (widened.frames.first ?? nil)!.width > (uniform.frames.first ?? nil)!.width,
                      detail: "\(format((uniform.frames.first ?? nil)!)) -> \(format((widened.frames.first ?? nil)!))")
        harness.check("master ratio is clamped to 0.4–0.8",
                      abs(((widened.frames.first ?? nil)!.width / (content.width - gap)) - 0.8) <= 0.01,
                      detail: String(format: "%.3f", (widened.frames.first ?? nil)!.width / (content.width - gap)))

        // autoBalance: a close either returns the Space to equal shares or keeps its splits.
        let a = WindowID(201), b = WindowID(202), c = WindowID(203)
        let balanced = WeightBalancing.afterClose(existing: [3, 1, 2],
                                                  previousTiled: [a, b, c],
                                                  surviving: [a, c],
                                                  autoBalance: true)
        let persisted = WeightBalancing.afterClose(existing: [3, 1, 2],
                                                   previousTiled: [a, b, c],
                                                   surviving: [a, c],
                                                   autoBalance: false)
        harness.check("autoBalance=true rebalances a Space whose window closed",
                      balanced == [1, 1], detail: "\(balanced)")
        harness.check("autoBalance=false keeps the surviving splits",
                      persisted == [3, 2], detail: "\(persisted)")
        harness.lines.append("")
    }

    // MARK: - Motion

    private static func motion(into harness: inout Harness) {
        harness.lines.append("motion (§7): curves and gates")
        for curve in AnimationCurve.allCases {
            harness.check("curve \(curve.rawValue) starts at 0 and ends at 1",
                          MotionCurve.progress(0, curve: curve) == 0
                            && abs(MotionCurve.progress(1, curve: curve) - 1) < 0.0001,
                          detail: String(format: "p(0)=%.4f p(1)=%.4f",
                                         MotionCurve.progress(0, curve: curve),
                                         MotionCurve.progress(1, curve: curve)))
            var monotonic = true
            var previous = -1.0
            for step in 0...60 {
                let value = MotionCurve.progress(Double(step) / 60, curve: curve)
                if value + 0.0001 < previous { monotonic = false }
                previous = value
            }
            harness.check("curve \(curve.rawValue) is monotonic", monotonic)
        }
        harness.check("spring overshoots by less than 10%",
                      MotionCurve.progress(0.55, curve: .spring) < 1.1,
                      detail: String(format: "%.3f", MotionCurve.progress(0.55, curve: .spring)))

        harness.check("animateSnap=false suppresses a snap tween",
                      MotionPolicy.allowsAnimation(animate: true, animateSnap: false,
                                                   animateLayoutSwaps: true, reduceMotion: false,
                                                   reason: .snap) == false)
        harness.check("animateLayoutSwaps=false suppresses a swap tween",
                      MotionPolicy.allowsAnimation(animate: true, animateSnap: true,
                                                   animateLayoutSwaps: false, reduceMotion: false,
                                                   reason: .layoutSwap) == false)
        harness.check("Reduce Motion forces instant in every case",
                      !MotionPolicy.allowsAnimation(animate: true, animateSnap: true,
                                                    animateLayoutSwaps: true, reduceMotion: true,
                                                    reason: .general)
                        && !MotionPolicy.allowsAnimation(animate: true, animateSnap: true,
                                                         animateLayoutSwaps: true, reduceMotion: true,
                                                         reason: .snap)
                        && !MotionPolicy.allowsAnimation(animate: true, animateSnap: true,
                                                         animateLayoutSwaps: true, reduceMotion: true,
                                                         reason: .layoutSwap))
        harness.check("animate=false suppresses everything",
                      !MotionPolicy.allowsAnimation(animate: false, animateSnap: true,
                                                    animateLayoutSwaps: true, reduceMotion: false,
                                                    reason: .general))
        harness.lines.append("")
    }

    // MARK: - Timing

    private static func measure(display: DisplayInfo, prefs: Preferences) -> Double {
        let content = TilingGeometry.contentRect(for: display, prefs: prefs)
        let gap = max(0, prefs.innerGap(for: display.id))
        let minimum = TilingGeometry.effectiveMinimum(prefs)
        let weights = Array(repeating: CGFloat(1), count: 12)
        let iterations = 200
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            for layout in LayoutKind.allCases {
                _ = TilingSolver.solve(count: 12, content: content, gap: gap, layout: layout,
                                       weights: weights, focusIndex: 0,
                                       masterRatio: prefs.masterRatio,
                                       stackPeek: prefs.stackPeek,
                                       gridColumns: prefs.gridColumns,
                                       minimum: minimum)
            }
        }
        let total = CFAbsoluteTimeGetCurrent() - start
        return total / Double(iterations) * 1000
    }

    // MARK: - Geometry assertions

    private static func standardDisplay() -> DisplayInfo {
        DisplayInfo(id: DisplayID(1),
                    frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                    visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875),
                    name: "SelfTest",
                    hasNotch: false,
                    scale: 2)
    }

    private static func inside(_ frame: CGRect, _ rect: CGRect) -> Bool {
        frame.minX >= rect.minX - 0.6 && frame.minY >= rect.minY - 0.6
            && frame.maxX <= rect.maxX + 0.6 && frame.maxY <= rect.maxY + 0.6
            && frame.width > 0 && frame.height > 0
    }

    private static func near(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 0.5 && abs(lhs.minY - rhs.minY) <= 0.5
            && abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
    }

    private static func overlaps(_ frames: [CGRect]) -> Bool {
        for i in frames.indices {
            for j in frames.indices where j > i {
                let intersection = frames[i].intersection(frames[j])
                if !intersection.isNull && intersection.width > 0.6 && intersection.height > 0.6 {
                    return true
                }
            }
        }
        return false
    }

    private static func columnGaps(_ frames: [CGRect], gap: CGFloat) -> Bool {
        guard frames.count > 1 else { return true }
        for index in 1..<frames.count {
            if abs((frames[index].minX - frames[index - 1].maxX) - gap) > 0.6 { return false }
        }
        return true
    }

    private static func rowGaps(_ frames: [CGRect], gap: CGFloat) -> Bool {
        guard frames.count > 1 else { return true }
        for index in 1..<frames.count {
            if abs((frames[index].minY - frames[index - 1].maxY) - gap) > 0.6 { return false }
        }
        return true
    }

    private static func firstRowGaps(_ frames: [CGRect], columns: Int, gap: CGFloat) -> Bool {
        guard columns > 1 else { return true }
        for index in 1..<min(columns, frames.count) {
            if abs((frames[index].minX - frames[index - 1].maxX) - gap) > 0.6 { return false }
        }
        if frames.count > columns {
            if abs((frames[columns].minY - frames[0].maxY) - gap) > 0.6 { return false }
        }
        return true
    }

    // MARK: - Formatting

    private static func format(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f %.0fx%.0f)", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        value.count >= width ? value + " " : value + String(repeating: " ", count: width - value.count)
    }
}

private extension DisplayInfo {
    func with(id: DisplayID) -> DisplayInfo {
        var copy = self
        copy.id = id
        return copy
    }
}
