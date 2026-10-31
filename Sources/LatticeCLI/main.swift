import Foundation
import Darwin
import LatticeKit

// `lattice` — the command line client for a running Lattice.app.
//
// This process never talks to Accessibility itself. It sends one JSON request per line over the
// app's private Unix socket and prints the reply. That means the CLI inherits the app's
// permission grant and can never be the thing that trips a TCC prompt.

// MARK: - Style

private enum Style {
    static let tty = isatty(STDOUT_FILENO) == 1

    static func dim(_ text: String) -> String { tty ? "\u{001B}[2m\(text)\u{001B}[0m" : text }
    static func bold(_ text: String) -> String { tty ? "\u{001B}[1m\(text)\u{001B}[0m" : text }
    static func green(_ text: String) -> String { tty ? "\u{001B}[32m\(text)\u{001B}[0m" : text }
    static func red(_ text: String) -> String { tty ? "\u{001B}[31m\(text)\u{001B}[0m" : text }
    static func yellow(_ text: String) -> String { tty ? "\u{001B}[33m\(text)\u{001B}[0m" : text }
}

// MARK: - Output helpers

private func writeOut(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

private func writeErr(_ text: String) {
    FileHandle.standardError.write(Data(text.utf8))
}

private func fail(_ message: String) -> Int32 {
    writeErr("lattice: \(message)\n")
    return 1
}

private func pad(_ text: String, to width: Int, right: Bool) -> String {
    let missing = max(0, width - text.count)
    let filler = String(repeating: " ", count: missing)
    return right ? filler + text : text + filler
}

private func truncate(_ text: String, _ limit: Int) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(max(0, limit - 1))) + "…"
}

private func renderTable(headers: [String], rows: [[String]], right: Set<Int> = []) -> String {
    guard !rows.isEmpty else { return "" }
    let widths = headers.indices.map { index in
        rows.reduce(headers[index].count) { max($0, $1[index].count) }
    }
    var lines: [String] = []
    let header = headers.indices.map { pad(headers[$0], to: widths[$0], right: right.contains($0)) }
        .joined(separator: "  ")
    lines.append("  " + Style.dim(header))
    for row in rows {
        let line = row.indices.map { pad(row[$0], to: widths[$0], right: right.contains($0)) }
            .joined(separator: "  ")
        lines.append("  " + line)
    }
    return lines.joined(separator: "\n")
}

private func tilde(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard path.hasPrefix(home) else { return path }
    return "~" + path.dropFirst(home.count)
}

private func formatBytes(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

private func string(_ data: [String: ControlValue]?, _ key: String, _ fallback: String = "") -> String {
    data?[key]?.stringValue ?? fallback
}

private func int(_ data: [String: ControlValue]?, _ key: String, _ fallback: Int = 0) -> Int {
    data?[key]?.intValue ?? fallback
}

private func bool(_ data: [String: ControlValue]?, _ key: String) -> Bool? {
    data?[key]?.boolValue
}

private func rows(_ data: [String: ControlValue]?) -> [[String: ControlValue]] {
    (data?["rows"]?.arrayValue ?? []).compactMap(\.objectValue)
}

// MARK: - Socket client

private enum ClientError: Error {
    case notRunning
    case timeout
    case failed(String)

    var message: String {
        switch self {
        case .notRunning: return "Lattice isn't running — open the app"
        case .timeout: return "Lattice didn't answer — the app may be busy"
        case .failed(let reason): return reason
        }
    }
}

private func socketAddress(_ path: String) -> sockaddr_un? {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: bytes)
    }
    return address
}

private func connectToLattice() throws -> Int32 {
    let path = LatticeControl.socketPath
    guard FileManager.default.fileExists(atPath: path) else { throw ClientError.notRunning }
    guard let base = socketAddress(path) else { throw ClientError.failed("Socket path is too long") }

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw ClientError.failed("socket(): \(String(cString: strerror(errno)))") }

    var address = base
    var flags = fcntl(fd, F_GETFL, 0)
    if flags < 0 { flags = 0 }
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    if result != 0 {
        if errno == EINPROGRESS {
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptor, 1, 1500)
            if ready == 0 {
                close(fd)
                throw ClientError.notRunning
            }
            if ready < 0 {
                let reason = String(cString: strerror(errno))
                close(fd)
                throw ClientError.failed("Couldn't connect to Lattice — \(reason)")
            }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length)
            if error != 0 {
                close(fd)
                if error == ECONNREFUSED || error == ENOENT {
                    throw ClientError.notRunning
                }
                throw ClientError.failed("Couldn't connect to Lattice — \(String(cString: strerror(error)))")
            }
        } else {
            let error = errno
            close(fd)
            if error == ECONNREFUSED || error == ENOENT {
                throw ClientError.notRunning
            }
            throw ClientError.failed("Couldn't connect to Lattice — \(String(cString: strerror(error)))")
        }
    }

    _ = fcntl(fd, F_SETFL, flags)
    var timeout = timeval(tv_sec: 4, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    return fd
}

private func sendAll(_ data: Data, to fd: Int32) throws {
    var sent = 0
    let bytes = [UInt8](data)
    while sent < bytes.count {
        let count = bytes.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return 0 }
            return Darwin.write(fd, base.advanced(by: sent), bytes.count - sent)
        }
        if count > 0 {
            sent += count
        } else if count < 0 && errno == EINTR {
            continue
        } else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
            throw ClientError.timeout
        } else {
            throw ClientError.failed("Couldn't send the request — \(String(cString: strerror(errno)))")
        }
    }
}

private func readResponseLine(from fd: Int32) throws -> Data {
    var buffer: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 8192)

    while true {
        let count = chunk.withUnsafeMutableBytes { raw -> Int in
            Darwin.read(fd, raw.baseAddress, raw.count)
        }
        if count > 0 {
            buffer.append(contentsOf: chunk[0..<count])
            if let newline = buffer.firstIndex(of: 0x0A) {
                return Data(buffer[..<newline])
            }
            if buffer.count > ControlWire.maxLineBytes {
                throw ClientError.failed("Lattice sent an oversized reply")
            }
        } else if count == 0 {
            throw ClientError.failed("Lattice closed the connection before replying")
        } else if errno == EINTR {
            continue
        } else if errno == EAGAIN || errno == EWOULDBLOCK {
            throw ClientError.timeout
        } else {
            throw ClientError.failed("Couldn't read the reply — \(String(cString: strerror(errno)))")
        }
    }
}

private func perform(_ request: ControlRequest) throws -> ControlResponse {
    let fd = try connectToLattice()
    defer { close(fd) }
    try sendAll(try ControlWire.encode(request), to: fd)
    let line = try readResponseLine(from: fd)
    do {
        return try ControlWire.decode(ControlResponse.self, from: line)
    } catch {
        throw ClientError.failed("Lattice sent a reply this CLI doesn't understand")
    }
}

// MARK: - Argument parsing

private struct Invocation {
    var command: String
    var positionals: [String]
    var flags: [String: String]
    var json: Bool
}

private let commandNames: Set<String> = [
    "status", "spaces", "windows", "layout", "gap", "outer-gap",
    "focus", "move", "swap", "send", "goto", "float", "tile",
    "pause", "resume", "toggle", "doctor", "version", "help",
]

private let arity: [String: Int] = [
    "status": 0, "spaces": 0, "windows": 0, "layout": 1, "gap": 1, "outer-gap": 1,
    "focus": 1, "move": 1, "swap": 1, "send": 1, "goto": 1,
    "float": 0, "tile": 0, "pause": 0, "resume": 0, "toggle": 0,
    "doctor": 0, "version": 0, "help": 0,
]

private func parse(_ arguments: [String]) throws -> Invocation {
    var command: String?
    var positionals: [String] = []
    var flags: [String: String] = [:]
    var json = false
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--json", "-j":
            json = true
            flags["json"] = "1"
        case "--everywhere", "-e":
            flags["everywhere"] = "1"
        case "--help", "-h":
            command = "help"
        case "--version":
            command = "version"
        case "--space":
            index += 1
            guard index < arguments.count else { throw CLIError("--space needs a number") }
            flags["space"] = arguments[index]
        default:
            if argument.hasPrefix("--space=") {
                flags["space"] = String(argument.dropFirst("--space=".count))
            } else if argument.hasPrefix("-") && argument != "-" && Double(argument) == nil {
                throw CLIError("Unknown option \(argument). Run `lattice help`.")
            } else if command == nil {
                command = argument
            } else {
                positionals.append(argument)
            }
        }
        index += 1
    }

    guard let command else { return Invocation(command: "help", positionals: [], flags: flags, json: json) }
    guard commandNames.contains(command) else {
        throw CLIError("Unknown command “\(command)”. Run `lattice help`.")
    }
    if let expected = arity[command], positionals.count != expected {
        let usage = expected == 0 ? "takes no arguments" : "needs \(expected) argument\(expected == 1 ? "" : "s")"
        throw CLIError("lattice \(command) \(usage)")
    }
    if flags["everywhere"] != nil && command != "layout" {
        throw CLIError("--everywhere only applies to `lattice layout`")
    }
    if flags["space"] != nil && command != "windows" {
        throw CLIError("--space only applies to `lattice windows`")
    }
    return Invocation(command: command, positionals: positionals, flags: flags, json: json)
}

private struct CLIError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

// MARK: - Human renderers

private func printJSON(_ response: ControlResponse) -> Int32 {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(response),
          let text = String(data: data, encoding: .utf8) else {
        return fail("Couldn't encode the reply as JSON")
    }
    writeOut(text + "\n")
    return 0
}

private func printStatus(_ response: ControlResponse) -> Int32 {
    let data = response.data
    let enabled = bool(data, "enabled") ?? false
    let trusted = bool(data, "accessibility") ?? false
    let index = int(data, "space")
    let count = int(data, "spaceCount")
    let layout = string(data, "layoutTitle", string(data, "layout"))
    let display = string(data, "display", "Unknown display")

    let labels = [
        ("Tiling", enabled ? Style.green("On") : Style.yellow("Paused")),
        ("Accessibility", trusted ? Style.green("Granted") : Style.red("Not granted")),
        ("Space", "\(index) of \(count) · \(display)"),
        ("Layout", layout),
        ("Windows", "\(int(data, "windows")) on this Space · \(int(data, "windowsTotal")) total"),
        ("Socket", Style.dim(tilde(string(data, "socket", LatticeControl.socketPath)))),
    ]
    let width = labels.map(\.0.count).max() ?? 0

    writeOut(Style.bold("Lattice \(string(data, "version", LatticeControl.versionSummary))") + "\n")
    for (label, value) in labels {
        writeOut("  " + pad(label, to: width, right: false) + "  " + value + "\n")
    }
    if !trusted {
        writeOut("\n  " + Style.yellow("Lattice needs Accessibility to move windows.") + "\n")
        writeOut("  " + Style.dim("Open Lattice, then enable it in System Settings ▸ Privacy & Security ▸ Accessibility.") + "\n")
    }
    return 0
}

private func printSpaces(_ response: ControlResponse) -> Int32 {
    let entries = rows(response.data)
    guard !entries.isEmpty else {
        writeOut("No Spaces found.\n")
        return 0
    }

    let headers = ["#", "CUR", "LAYOUT", "OWN", "WINDOWS", "DISPLAY", "SPACE ID"]
    let body: [[String]] = entries.map { row in
        let fullscreen = bool(row, "fullscreen") ?? false
        let index = int(row, "index")
        return [
            fullscreen ? "fs" : "\(index)",
            (bool(row, "current") ?? false) ? "●" : "·",
            string(row, "layoutTitle", string(row, "layout")),
            (bool(row, "ownLayout") ?? false) ? "yes" : "no",
            "\(int(row, "windows"))",
            truncate(string(row, "display"), 26),
            string(row, "space"),
        ]
    }

    writeOut(renderTable(headers: headers, rows: body, right: [0, 2, 4]) + "\n")
    return 0
}

private func printWindows(_ response: ControlResponse) -> Int32 {
    let data = response.data
    let entries = rows(data)

    if entries.isEmpty {
        let filter = int(data, "spaceFilter")
        if filter > 0 {
            writeOut("No managed windows on Space \(filter).\n")
        } else {
            writeOut("No managed windows.\n")
        }
        if bool(data, "accessibility") == false {
            writeOut(Style.dim("Accessibility isn't granted, so Lattice can't see windows yet.") + "\n")
        }
        return 0
    }

    let headers = ["ID", "TITLE", "APP", "FRAME", "SPACE", "DISPLAY", "FLAGS"]
    let body: [[String]] = entries.map { row in
        var flags: [String] = []
        if bool(row, "floating") == true { flags.append("float") }
        if bool(row, "focused") == true { flags.append("focused") }
        if bool(row, "fullscreen") == true { flags.append("fullscreen") }
        return [
            "\(int(row, "id"))",
            truncate(string(row, "title"), 46),
            truncate(string(row, "app"), 18),
            string(row, "frame"),
            "\(int(row, "space"))",
            truncate(string(row, "display"), 22),
            flags.joined(separator: ","),
        ]
    }

    writeOut(renderTable(headers: headers, rows: body, right: [0, 3, 4]) + "\n")
    return 0
}

private func printVersion(_ response: ControlResponse) -> Int32 {
    let data = response.data
    let version = string(data, "version", LatticeControl.version)
    let build = string(data, "build", LatticeControl.build)
    writeOut("lattice \(version) (\(build))\n")
    return 0
}

private func printDoctor(_ data: [String: ControlValue]?, running: Bool) -> Int32 {
    let trusted = bool(data, "accessibility")
    let enabled = bool(data, "enabled")
    let socket = string(data, "socket", LatticeControl.socketPath)
    let log = string(data, "log", LatticeControl.logPath)
    let logSize = int(data, "logSize")
    let socketMode = string(data, "socketMode", "missing")
    let socketPresent = bool(data, "socketPresent") ?? false
    let pid = int(data, "pid")
    let version = string(data, "version", LatticeControl.versionSummary)

    var lines: [String] = []
    lines.append(Style.bold("Lattice doctor"))
    let labelsAndValues: [(String, String)] = [
        ("App", running ? Style.green("running") + " (pid \(pid))" : Style.red("not running")),
        ("Accessibility", trusted == true ? Style.green("granted")
            : trusted == false ? Style.red("NOT granted")
            : Style.yellow("unknown — app isn't running")),
        ("Tiling", enabled == nil ? Style.dim("—") : (enabled == true ? Style.green("on") : Style.yellow("paused"))),
        ("Socket", "\(tilde(socket)) " + Style.dim(
            socketPresent ? (running ? "(\(socketMode))" : "(stale, \(socketMode))") : "(missing)")),
        ("Log", "\(tilde(log)) " + Style.dim("(\(formatBytes(logSize)))")),
        ("Version", version),
        ("macOS", LatticeDoctorInfo.macOSVersion),
    ]
    let width = labelsAndValues.map(\.0.count).max() ?? 0
    for (label, value) in labelsAndValues {
        lines.append("  " + pad(label, to: width, right: false) + "  " + value)
    }

    lines.append("")
    lines.append("  " + Style.dim("Requirements"))
    let requirements = data?["requirements"]?.arrayValue?.compactMap(\.stringValue) ?? LatticeDoctorInfo.requirements
    for requirement in requirements {
        let mark = requirement.hasPrefix("Accessibility")
            ? (trusted == true ? Style.green("✓") : trusted == false ? Style.red("✗") : Style.dim("·"))
            : Style.dim("·")
        lines.append("    \(mark) \(requirement)")
    }

    if !running {
        lines.append("")
        lines.append("  " + Style.yellow("Lattice isn't running — open the app."))
        lines.append("  " + Style.dim("Open build/Lattice.app (or Applications/Lattice.app), then run `lattice doctor` again."))
    } else if trusted == false {
        lines.append("")
        lines.append("  " + Style.yellow("Accessibility is not granted, so tiling is inert."))
        lines.append("  " + Style.dim("Open Lattice → System Settings ▸ Privacy & Security ▸ Accessibility → enable Lattice."))
    }

    let logLines = data?["logLines"]?.arrayValue?.compactMap(\.stringValue) ?? []
    if !logLines.isEmpty {
        lines.append("")
        lines.append("  " + Style.dim("Last \(logLines.count) log lines"))
        for line in logLines {
            lines.append("  " + Style.dim(truncate(line, 160)))
        }
    } else {
        lines.append("")
        lines.append("  " + Style.dim("Log is empty."))
    }

    writeOut(lines.joined(separator: "\n") + "\n")
    return (running && trusted == true) ? 0 : 1
}

private let usage = """
lattice — control a running Lattice window manager

USAGE
  lattice <command> [arguments] [--json]

SPACES & WINDOWS
  status                        Tiling, Accessibility, current Space, display, layout, windows
  spaces                        Every real Space: index, display, layout, window count
  windows [--space N]           Managed windows, their frames and Spaces
  focus <left|right|up|down>    Move keyboard focus
  move <left|right|up|down>     Move the focused window in the layout
  swap <left|right|up|down>     Swap the focused window with its neighbour
  send <space-number>           Send the focused window to that Space
  goto <space-number>           Switch to that Space
  float | tile                  Float or re-tile the focused window

TILING
  layout <dwindle|columns|rows|grid|master|stack|next> [--everywhere]
  gap <points>                  Inner gap between tiles
  outer-gap <points>            Padding around the tiled area
  pause | resume | toggle       Turn tiling off, on, or flip it
  resume                        Re-enable tiling

DIAGNOSTICS
  doctor                        Why isn't it working? Health, paths, last log lines
  version                       CLI and app version

FLAGS
  --json                        Machine-readable JSON (also -j)
  --everywhere                  Apply the layout to every Space
  --space N                     Filter `windows` by Space number

The CLI talks to the running app over ~/Library/Application Support/Lattice/control.sock.
It has no Accessibility permission of its own by design.
"""

// MARK: - Doctor offline

private func offlineDoctorData() -> [String: ControlValue] {
    let socket = LatticeControl.socketPath
    return [
        "appRunning": .bool(false),
        "pid": .null,
        "accessibility": .null,
        "enabled": .null,
        "socket": .string(socket),
        "socketPresent": .bool(LatticeDoctorInfo.fileExists(socket)),
        "socketMode": .string(LatticeDoctorInfo.posixMode(socket) ?? "missing"),
        "log": .string(LatticeControl.logPath),
        "logSize": .int(LatticeDoctorInfo.logSize() ?? 0),
        "version": .string(LatticeControl.versionSummary),
        "macOS": .string(LatticeDoctorInfo.macOSVersion),
        "requirements": .strings(LatticeDoctorInfo.requirements),
        "logLines": .strings(LatticeDoctorInfo.lastLogLines(10)),
    ]
}

// MARK: - Main

private func run(_ arguments: [String]) -> Int32 {
    signal(SIGPIPE, SIG_IGN)

    let invocation: Invocation
    do {
        invocation = try parse(arguments)
    } catch let error as CLIError {
        return fail(error.message)
    } catch {
        return fail("\(error)")
    }

    if invocation.command == "help" {
        writeOut(usage)
        return 0
    }

    if invocation.command == "version" {
        let response = ControlResponse.success(nil, data: [
            "name": .string("lattice"),
            "version": .string(LatticeControl.version),
            "build": .string(LatticeControl.build),
            "protocol": .int(LatticeControl.protocolVersion),
        ])
        return invocation.json ? printJSON(response) : printVersion(response)
    }

    if invocation.command == "doctor" {
        do {
            let response = try perform(ControlRequest(command: "doctor"))
            if !response.ok {
                return fail(response.message ?? "doctor failed")
            }
            if invocation.json { return printJSON(response) }
            return printDoctor(response.data, running: true)
        } catch {
            let reason = (error as? ClientError)?.message ?? "\(error)"
            if invocation.json {
                let response = ControlResponse(ok: false, message: reason, data: offlineDoctorData())
                _ = printJSON(response)
            } else {
                _ = printDoctor(offlineDoctorData(), running: false)
                writeErr("lattice: \(reason)\n")
            }
            return 1
        }
    }

    let request = ControlRequest(command: invocation.command,
                                 arguments: invocation.positionals,
                                 flags: invocation.flags)

    let response: ControlResponse
    do {
        response = try perform(request)
    } catch let error as ClientError {
        return fail(error.message)
    } catch {
        return fail("\(error)")
    }

    guard response.ok else {
        return fail(response.message ?? "Lattice rejected the command")
    }

    if invocation.json {
        return printJSON(response)
    }

    switch invocation.command {
    case "status": return printStatus(response)
    case "spaces": return printSpaces(response)
    case "windows": return printWindows(response)
    default:
        writeOut((response.message ?? "Done") + "\n")
        return 0
    }
}

exit(run(Array(CommandLine.arguments.dropFirst())))
