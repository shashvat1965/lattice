import Foundation
import AppKit
import Darwin
import LatticeKit

/// The app-side half of the control channel.
///
/// The GUI process owns the Accessibility grant, so it is the only process that may inspect or
/// move windows. The CLI connects to this server over a private Unix socket and asks it to do
/// the work. The server is intentionally thin: validate the request, call the same `AppModel` /
/// `Tiler` paths the menu, hotkeys and palette use, and answer on the same line.
///
/// Safety properties:
///  * `start` is idempotent; calling it twice is a no-op.
///  * All socket I/O is non-blocking and driven by dispatch sources on the main queue. Commands
///    are already main-actor work; no command performs blocking I/O.
///  * Multiple clients are handled concurrently and partial lines are buffered per connection.
///  * The socket file is created 0700 (and its directory 0700), and removed on quit/exit.
///  * A stale socket (crash, reboot) is detected by probing it first and replaced.
@MainActor
public final class ControlServer {
    public static let shared = ControlServer()

    private var model: AppModel?
    private var listenerFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [Int32: ControlConnection] = [:]
    private var started = false
    private var cleanupInstalled = false

    private let maxClients = 32

    private init() {}

    // MARK: - Lifecycle

    public func start(model: AppModel) {
        guard !started else { return }
        self.model = model
        installCleanup()

        let path = LatticeControl.socketPath
        let directory = LatticeControl.supportDirectory

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            Log.error("control: could not create \(directory.path): \(error.localizedDescription)")
            return
        }

        if FileManager.default.fileExists(atPath: path) {
            if Self.isListening(at: path) {
                Log.info("control: another Lattice instance already owns \(path); not starting a second server")
                return
            }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            Log.error("control: socket() failed: \(Self.errnoText())")
            return
        }
        Self.setNonBlocking(fd)

        guard let address = Self.address(for: path) else {
            Log.error("control: socket path is too long: \(path)")
            close(fd)
            return
        }

        let bound = withUnsafePointer(to: address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            Log.error("control: bind(\(path)) failed: \(Self.errnoText())")
            close(fd)
            return
        }

        // Only this user may talk to the server. The directory is 0700 too, so the socket is
        // unreachable by anyone else even before the chmod.
        chmod(path, mode_t(0o700))

        guard listen(fd, 16) == 0 else {
            Log.error("control: listen() failed: \(Self.errnoText())")
            close(fd)
            unlink(path)
            return
        }

        listenerFD = fd
        started = true
        ControlSocketCleanup.shared.claim(path)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.acceptPendingConnections()
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        acceptSource = source
        source.resume()

        Log.info("control: listening on \(path) (mode 0700)")
    }

    /// Removes the socket file. Safe to call more than once.
    public func stop() {
        guard started || listenerFD >= 0 else { return }
        acceptSource?.cancel()
        acceptSource = nil
        let live = Array(connections.values)
        connections.removeAll()
        for connection in live {
            connection.close()
        }
        listenerFD = -1
        started = false
        ControlSocketCleanup.shared.release()
        Log.info("control: stopped")
    }

    private func installCleanup() {
        guard !cleanupInstalled else { return }
        cleanupInstalled = true

        // Normal exits. Ownership is claimed only after a successful listen, so a second
        // instance that declined to start can never unlink the live instance's socket.
        atexit {
            ControlSocketCleanup.shared.release()
        }
        // NSApp.terminate() and menu Quit both post this.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { _ in
            ControlSocketCleanup.shared.release()
        }
    }

    // MARK: - Accepting

    private func acceptPendingConnections() {
        while true {
            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientFD = withUnsafeMutablePointer(to: &storage) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    accept(listenerFD, sockaddrPointer, &length)
                }
            }
            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                Log.error("control: accept failed: \(Self.errnoText())")
                return
            }

            if connections.count >= maxClients {
                close(clientFD)
                continue
            }

            Self.setNonBlocking(clientFD)
            var noSigPipe: Int32 = 1
            setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                       socklen_t(MemoryLayout<Int32>.size))

            let connection = ControlConnection(fd: clientFD) { [weak self] request in
                self?.respond(to: request) ?? .failure("Lattice is shutting down")
            } onClose: { [weak self] fd in
                self?.connections[fd] = nil
            }
            connections[clientFD] = connection
            connection.start()
        }
    }

    // MARK: - Commands

    private func respond(to request: ControlRequest) -> ControlResponse {
        guard let model else { return .failure("Lattice is still starting") }

        switch request.command {
        case "status":     return status(model)
        case "spaces":     return spaces(model)
        case "windows":    return windows(model, request: request)
        case "layout":     return layout(model, request: request)
        case "gap":        return gap(model, request: request, outer: false)
        case "outer-gap":  return gap(model, request: request, outer: true)
        case "focus":      return directionCommand(model, request: request, kind: .focus)
        case "move":       return directionCommand(model, request: request, kind: .move)
        case "swap":       return directionCommand(model, request: request, kind: .swap)
        case "send":       return send(model, request: request)
        case "goto":       return goTo(model, request: request)
        case "float":      return float(model, shouldFloat: true)
        case "tile":       return float(model, shouldFloat: false)
        case "pause":      return setEnabled(model, false)
        case "resume":     return setEnabled(model, true)
        case "toggle":     return setEnabled(model, !model.isEnabled)
        case "doctor":     return doctor(model)
        case "version":
            return .success(nil, data: [
                "name": .string("lattice"),
                "version": .string(LatticeControl.version),
                "build": .string(LatticeControl.build),
                "protocol": .int(LatticeControl.protocolVersion),
            ])
        default:
            return .failure("Unknown command “\(request.command)”. Run `lattice help`.")
        }
    }

    // MARK: status

    private func status(_ model: AppModel) -> ControlResponse {
        model.refreshSpaces()
        let focused = model.focusedSpace
        let entry = SpaceManager.shared.spaceFor(displayID: model.tiler.focusedDisplay())
        let index = Self.userIndex(of: focused, in: entry)
        let windowsOnSpace = model.windowsBySpace[focused]?.count ?? 0
        let totalWindows = model.windowsBySpace.values.reduce(0) { $0 + $1.count }

        return .success(nil, data: [
            "enabled": .bool(model.isEnabled),
            "accessibility": .bool(model.engine.isTrusted),
            "space": .int(index),
            "spaceID": .string(String(focused.raw)),
            "spaceCount": .int(entry.userSpaceIDs.count),
            "display": .string(displayName(entry.display, model: model)),
            "displayID": .string(String(entry.display.raw)),
            "layout": .string(model.prefs.prefs.layout(for: focused).rawValue),
            "layoutTitle": .string(model.prefs.prefs.layout(for: focused).title),
            "layoutNote": .string(model.layoutNotes[focused] ?? ""),
            "windows": .int(windowsOnSpace),
            "windowsTotal": .int(totalWindows),
            "focusedWindow": model.engine.focused.map { .int(Int($0.raw)) } ?? .null,
            "focusedApp": model.engine.focused
                .flatMap { model.engine.window($0)?.appName }
                .map(ControlValue.string) ?? .null,
            "spacesTotal": .int(model.spaces.reduce(0) { $0 + $1.userSpaceIDs.count }),
            "version": .string(LatticeControl.versionSummary),
            "protocol": .int(LatticeControl.protocolVersion),
        ])
    }

    // MARK: spaces

    private func spaces(_ model: AppModel) -> ControlResponse {
        model.refreshSpaces()
        let focused = model.focusedSpace
        var rows: [ControlValue] = []

        for entry in model.spaces {
            let types = entry.spaceTypes
            var userNumber = 0
            for (offset, space) in entry.spaceIDs.enumerated() {
                let type = types.indices.contains(offset) ? types[offset] : 0
                let isUser = type == 0
                if isUser { userNumber += 1 }
                let kind = model.prefs.prefs.layout(for: space)
                rows.append(.object([
                    "space": .string(String(space.raw)),
                    "index": .int(isUser ? userNumber : 0),
                    "fullscreen": .bool(!isUser),
                    "current": .bool(space == focused),
                    "layout": .string(kind.rawValue),
                    "layoutTitle": .string(kind.title),
                    "ownLayout": .bool(model.prefs.prefs.hasOwnLayout(space)),
                    "windows": .int(model.windowsBySpace[space]?.count ?? 0),
                    "display": .string(displayName(entry.display, model: model)),
                    "displayID": .string(String(entry.display.raw)),
                    "isMainDisplay": .bool(entry.isMain),
                ]))
            }
        }

        return .success(nil, data: [
            "current": .string(String(focused.raw)),
            "rows": .array(rows),
            "count": .int(rows.count),
        ])
    }

    // MARK: windows

    private func windows(_ model: AppModel, request: ControlRequest) -> ControlResponse {
        model.refreshSpaces()

        var spaceFilter: Int?
        if let raw = request.flags["space"] {
            guard let value = Int(raw), value > 0 else {
                return .failure("--space needs a positive Space number")
            }
            spaceFilter = value
        }

        let focusedWindow = model.engine.focused
        var rows: [ControlValue] = []

        for window in model.engine.windows.values.sorted(by: { lhs, rhs in
            if lhs.space != rhs.space {
                return Self.spaceOrder(lhs.space, in: model) < Self.spaceOrder(rhs.space, in: model)
            }
            return lhs.id.raw < rhs.id.raw
        }) where !window.isMinimized {
            let index = Self.userIndex(of: window.space, in: model)
            if let spaceFilter, index != spaceFilter { continue }
            rows.append(.object([
                "id": .int(Int(window.id.raw)),
                "title": .string(window.title.isEmpty ? "(untitled)" : window.title),
                "app": .string(window.appName),
                "bundleID": window.bundleID.map(ControlValue.string) ?? .null,
                "x": .double(Double(window.frame.origin.x)),
                "y": .double(Double(window.frame.origin.y)),
                "width": .double(Double(window.frame.width)),
                "height": .double(Double(window.frame.height)),
                "frame": .string(Self.frameString(window.frame)),
                "space": .int(index),
                "spaceID": .string(String(window.space.raw)),
                "display": .string(displayName(window.display, model: model)),
                "displayID": .string(String(window.display.raw)),
                "floating": .bool(model.tiler.isFloating(window.id)),
                "focused": .bool(window.id == focusedWindow),
                "fullscreen": .bool(window.isFullscreen),
            ]))
        }

        return .success(nil, data: [
            "rows": .array(rows),
            "count": .int(rows.count),
            "spaceFilter": spaceFilter.map(ControlValue.int) ?? .null,
            "accessibility": .bool(model.engine.isTrusted),
        ])
    }

    // MARK: layout / gaps

    private enum DirectionKind { case focus, move, swap }

    private func layout(_ model: AppModel, request: ControlRequest) -> ControlResponse {
        guard let raw = request.arguments.first?.lowercased(), !raw.isEmpty else {
            return .failure("layout needs one of: dwindle, columns, rows, grid, master, stack, next")
        }

        let everywhere = request.flags["everywhere"] == "1"
        let space = model.tiler.focusedSpace()
        let before = model.prefs.prefs.layout(for: space)
        let target: LayoutKind

        if raw == "next" {
            let all = LayoutKind.allCases
            let index = all.firstIndex(of: before) ?? 0
            target = all[(index + 1) % all.count]
        } else if let parsed = LayoutKind(rawValue: raw) {
            target = parsed
        } else {
            return .failure("Unknown layout “\(raw)”. Use dwindle, columns, rows, grid, master, stack or next.")
        }

        if everywhere {
            model.setLayoutEverywhere(target)
            return .success("Layout set to \(target.title) on every Space", data: [
                "layout": .string(target.rawValue),
                "layoutTitle": .string(target.title),
                "everywhere": .bool(true),
            ])
        }

        model.setLayout(target, for: space)
        let index = Self.userIndex(of: space, in: model)
        let where_ = index > 0 ? "Space \(index)" : "the current Space"
        return .success("Layout set to \(target.title) on \(where_)", data: [
            "layout": .string(target.rawValue),
            "layoutTitle": .string(target.title),
            "space": .int(index),
            "spaceID": .string(String(space.raw)),
            "everywhere": .bool(false),
        ])
    }

    private func gap(_ model: AppModel, request: ControlRequest, outer: Bool) -> ControlResponse {
        guard let raw = request.arguments.first, let value = Double(raw),
              value.isFinite, value >= 0, value <= 400 else {
            return .failure("\(outer ? "outer-gap" : "gap") needs a number of points between 0 and 400")
        }

        let points = CGFloat(value)
        model.prefs.update { prefs in
            if outer { prefs.outerGap = points } else { prefs.gap = points }
        }
        model.tiler.reconcile()

        let label = Self.pointsString(value)
        var data: [String: ControlValue] = [
            "gap": .double(Double(model.prefs.prefs.gap)),
            "outerGap": .double(Double(model.prefs.prefs.outerGap)),
        ]
        data[outer ? "outerGap" : "gap"] = .double(value)
        return .success("\(outer ? "Outer gap" : "Inner gap") set to \(label) pt", data: data)
    }

    // MARK: focus / move / swap

    private func directionCommand(_ model: AppModel,
                                  request: ControlRequest,
                                  kind: DirectionKind) -> ControlResponse {
        guard let raw = request.arguments.first?.lowercased() else {
            return .failure("\(request.command) needs left, right, up or down")
        }

        let direction: Direction
        switch raw {
        case "left": direction = .left
        case "right": direction = .right
        case "up": direction = .up
        case "down": direction = .down
        default:
            return .failure("Unknown direction “\(raw)”. Use left, right, up or down.")
        }

        if let failure = requireAccessibility(model) { return failure }

        switch kind {
        case .focus: model.dispatch(Self.focusCommand(direction))
        case .move: model.dispatch(Self.moveCommand(direction))
        case .swap: model.dispatch(Self.swapCommand(direction))
        }

        let space = model.tiler.focusedSpace()
        return .success("\(kind == .focus ? "Focused" : kind == .move ? "Moved" : "Swapped") \(raw)",
                        data: [
                            "action": .string(kind == .focus ? "focus" : kind == .move ? "move" : "swap"),
                            "direction": .string(raw),
                            "space": .int(Self.userIndex(of: space, in: model)),
                        ])
    }

    // MARK: send / goto

    private func send(_ model: AppModel, request: ControlRequest) -> ControlResponse {
        guard let raw = request.arguments.first, let number = Int(raw), number > 0 else {
            return .failure("send needs a Space number, e.g. `lattice send 2`")
        }
        if let failure = requireAccessibility(model) { return failure }

        model.refreshSpaces()
        guard let focused = model.engine.focused, let window = model.engine.window(focused) else {
            return .failure("No focused window to send")
        }

        let display = SpaceManager.shared.displayID(for: focused) ?? window.display
        let entry = SpaceManager.shared.spaceFor(displayID: display)
        guard entry.userSpaceIDs.indices.contains(number - 1) else {
            return .failure("Space \(number) doesn't exist on this display (it has \(entry.userSpaceIDs.count))")
        }

        model.tiler.moveWindowToSpace(number: number)
        let title = window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)"
        // The native-drag fallback finishes asynchronously (and can be refused by the other
        // app), so this is a request, not a receipt. The log has the verified outcome.
        return .success("Moving \(title) to Space \(number) — check `lattice spaces` in a moment", data: [
            "window": .int(Int(focused.raw)),
            "app": .string(window.appName),
            "title": .string(window.title),
            "space": .int(number),
            "spaceID": .string(String(entry.userSpaceIDs[number - 1].raw)),
            "confirmed": .bool(false),
        ])
    }

    private func goTo(_ model: AppModel, request: ControlRequest) -> ControlResponse {
        guard let raw = request.arguments.first, let number = Int(raw), number > 0 else {
            return .failure("goto needs a Space number, e.g. `lattice goto 2`")
        }

        model.refreshSpaces()
        let display = model.tiler.focusedDisplay()
        let entry = SpaceManager.shared.spaceFor(displayID: display)
        guard entry.userSpaceIDs.indices.contains(number - 1) else {
            return .failure("Space \(number) doesn't exist on this display (it has \(entry.userSpaceIDs.count))")
        }

        model.tiler.goToSpace(number: number)
        return .success("Switched to Space \(number)", data: [
            "space": .int(number),
            "spaceID": .string(String(entry.userSpaceIDs[number - 1].raw)),
            "display": .string(displayName(display, model: model)),
        ])
    }

    // MARK: float / tile

    private func float(_ model: AppModel, shouldFloat: Bool) -> ControlResponse {
        if let failure = requireAccessibility(model) { return failure }
        guard let focused = model.engine.focused, let window = model.engine.window(focused) else {
            return .failure("No focused window")
        }

        let manuallyFloating = model.tiler.floating.contains(focused)
        let floating = model.tiler.isFloating(focused)
        let name = window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)"

        if shouldFloat {
            if manuallyFloating || floating {
                return .success("\(name) is already floating", data: [
                    "window": .int(Int(focused.raw)),
                    "floating": .bool(true),
                ])
            }
            model.tiler.toggleFloat()
            return .success("\(name) is floating", data: [
                "window": .int(Int(focused.raw)),
                "floating": .bool(true),
            ])
        }

        if manuallyFloating {
            model.tiler.toggleFloat()
            if model.tiler.isFloating(focused) {
                return .failure("\(name) still floats because of an app rule — remove it in Settings ▸ Apps")
            }
            return .success("\(name) is tiled", data: [
                "window": .int(Int(focused.raw)),
                "floating": .bool(false),
            ])
        }

        if floating {
            return .failure("\(name) floats because of an app rule — remove it in Settings ▸ Apps")
        }
        return .success("\(name) is already tiled", data: [
            "window": .int(Int(focused.raw)),
            "floating": .bool(false),
        ])
    }

    // MARK: enable

    private func setEnabled(_ model: AppModel, _ enabled: Bool) -> ControlResponse {
        model.setEnabled(enabled)
        return .success(enabled ? "Resumed — Lattice is tiling" : "Paused — Lattice is leaving windows alone",
                        data: ["enabled": .bool(enabled)])
    }

    // MARK: doctor

    private func doctor(_ model: AppModel) -> ControlResponse {
        model.refreshPermissions()
        let socket = LatticeControl.socketPath
        let mode = LatticeDoctorInfo.posixMode(socket)
        let lines = LatticeDoctorInfo.lastLogLines(10)
        let size = LatticeDoctorInfo.logSize()

        return .success(nil, data: [
            "appRunning": .bool(true),
            "pid": .int(Int(getpid())),
            "accessibility": .bool(model.engine.isTrusted),
            "enabled": .bool(model.isEnabled),
            "socket": .string(socket),
            "socketPresent": .bool(LatticeDoctorInfo.fileExists(socket)),
            "socketMode": .string(mode ?? "unknown"),
            "log": .string(LatticeControl.logPath),
            "logSize": .int(size ?? 0),
            "version": .string(LatticeControl.versionSummary),
            "macOS": .string(LatticeDoctorInfo.macOSVersion),
            "requirements": .strings(LatticeDoctorInfo.requirements),
            "logLines": .strings(lines),
        ])
    }

    // MARK: - Helpers

    private func requireAccessibility(_ model: AppModel) -> ControlResponse? {
        model.refreshPermissions()
        guard model.engine.isTrusted else {
            return .failure("Accessibility permission isn't granted — open Lattice and enable it in System Settings ▸ Privacy & Security ▸ Accessibility")
        }
        return nil
    }

    private func displayName(_ id: DisplayID, model: AppModel) -> String {
        if let info = model.displays.first(where: { $0.id == id }) { return info.name }
        if let screen = SpaceManager.screen(for: id) { return screen.localizedName }
        return "Display \(id.raw)"
    }

    private static func userIndex(of space: SpaceID, in entry: SpaceManager.DisplaySpaces) -> Int {
        entry.userSpaceIDs.firstIndex(of: space).map { $0 + 1 } ?? 0
    }

    private static func userIndex(of space: SpaceID, in model: AppModel) -> Int {
        for entry in model.spaces {
            if let index = entry.userSpaceIDs.firstIndex(of: space) {
                return index + 1
            }
        }
        return 0
    }

    /// Mirrors Mission Control order across displays so window rows sort sensibly.
    private static func spaceOrder(_ space: SpaceID, in model: AppModel) -> Int {
        var offset = 0
        for entry in model.spaces {
            if let index = entry.spaceIDs.firstIndex(of: space) {
                return offset + index
            }
            offset += entry.spaceIDs.count
        }
        return Int.max
    }

    private static func frameString(_ rect: CGRect) -> String {
        "\(Int(rect.origin.x.rounded())),\(Int(rect.origin.y.rounded())) \(Int(rect.width.rounded()))×\(Int(rect.height.rounded()))"
    }

    private static func pointsString(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func focusCommand(_ direction: Direction) -> CommandID {
        switch direction {
        case .left: .focusLeft
        case .right: .focusRight
        case .up: .focusUp
        case .down: .focusDown
        }
    }

    private static func moveCommand(_ direction: Direction) -> CommandID {
        switch direction {
        case .left: .moveLeft
        case .right: .moveRight
        case .up: .moveUp
        case .down: .moveDown
        }
    }

    private static func swapCommand(_ direction: Direction) -> CommandID {
        switch direction {
        case .left: .swapLeft
        case .right: .swapRight
        case .up: .swapUp
        case .down: .swapDown
        }
    }

    // MARK: - POSIX helpers

    private static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }
        return address
    }

    private static func isListening(at path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard var address = address(for: path) else { return false }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    private static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    private static func errnoText() -> String {
        String(cString: strerror(errno))
    }
}

// MARK: - Connection

/// One accepted client. Buffers partial request lines in, complete response lines out.
@MainActor
private final class ControlConnection {
    private let fd: Int32
    private let onRequest: (ControlRequest) -> ControlResponse
    private let onClose: (Int32) -> Void

    private var readSource: DispatchSourceRead?
    private var writeSource: DispatchSourceWrite?
    private var input: [UInt8] = []
    private var output = Data()
    private var closed = false
    private var closeAfterFlush = false

    init(fd: Int32,
         onRequest: @escaping (ControlRequest) -> ControlResponse,
         onClose: @escaping (Int32) -> Void) {
        self.fd = fd
        self.onRequest = onRequest
        self.onClose = onClose
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readAvailable() }
        }
        source.setCancelHandler { [fd] in
            Darwin.close(fd)
        }
        readSource = source
        source.resume()
    }

    func close() {
        guard !closed else { return }
        closed = true
        readSource?.cancel()
        readSource = nil
        writeSource?.cancel()
        writeSource = nil
        onClose(fd)
    }

    // MARK: Reading

    private func readAvailable() {
        guard !closed else { return }
        var buffer = [UInt8](repeating: 0, count: 16_384)

        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                read(fd, raw.baseAddress, raw.count)
            }
            if count > 0 {
                input.append(contentsOf: buffer[0..<count])
                if input.count > ControlWire.maxLineBytes {
                    append(.failure("Request is too large"))
                    closeAfterFlush = true
                    flush()
                    return
                }
            } else if count == 0 {
                // Peer finished sending. Answer anything complete, then close.
                closeAfterFlush = true
                break
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                break
            } else if errno == EINTR {
                continue
            } else {
                close()
                return
            }
        }

        processLines()
        // Always flush: a client that sent a request and immediately half-closed still gets
        // its reply. `flush` closes the connection afterwards when `closeAfterFlush` is set.
        flush()
    }

    private func processLines() {
        while let newline = input.firstIndex(of: 0x0A) {
            let line = Array(input[..<newline])
            input.removeFirst(newline + 1)
            guard !line.isEmpty else { continue }

            let request: ControlRequest
            do {
                request = try ControlWire.decode(ControlRequest.self, from: Data(line))
            } catch {
                append(.failure("Malformed request: expected one JSON object per line"))
                continue
            }
            append(onRequest(request))
        }
    }

    private func append(_ response: ControlResponse) {
        do {
            output.append(try ControlWire.encode(response))
        } catch {
            output.append(Data(#"{"ok":false,"message":"Could not encode response"}"#.utf8))
            output.append(0x0A)
        }
    }

    // MARK: Writing

    private func flush() {
        guard !closed else { return }

        while !output.isEmpty {
            let written = output.withUnsafeBytes { raw in
                write(fd, raw.baseAddress, raw.count)
            }
            if written > 0 {
                output.removeFirst(written)
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                enableWrites()
                return
            } else if errno == EINTR {
                continue
            } else {
                close()
                return
            }
        }

        disablesWrites()
        if closeAfterFlush {
            close()
        }
    }

    private func enableWrites() {
        guard writeSource == nil else { return }
        let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
        writeSource = source
        source.resume()
    }

    private func disablesWrites() {
        guard let source = writeSource else { return }
        writeSource = nil
        source.setEventHandler {}
        source.cancel()
    }
}

// MARK: - Socket ownership

/// Remembers which process successfully bound the control socket, so only that process removes
/// it. A second Lattice instance that finds the socket already live must not delete it on exit.
private final class ControlSocketCleanup: @unchecked Sendable {
    static let shared = ControlSocketCleanup()

    private let lock = NSLock()
    private var ownedPath: String?

    func claim(_ path: String) {
        lock.lock()
        ownedPath = path
        lock.unlock()
    }

    func release() {
        lock.lock()
        let path = ownedPath
        ownedPath = nil
        lock.unlock()
        if let path { unlink(path) }
    }
}
