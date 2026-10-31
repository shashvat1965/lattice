import Foundation

/// Filesystem/version facts shared by the server's `doctor` response and the CLI's offline
/// report, so the two never disagree about where things live.
public enum LatticeDoctorInfo {
    public static let requirements: [String] = [
        "macOS 15 or later",
        "Accessibility permission granted to Lattice.app — the CLI never asks for its own",
        "System Integrity Protection enabled — Lattice only uses native WindowServer APIs",
        "Real macOS Spaces — Lattice never emulates or renames a workspace",
        "Lattice running with tiling enabled (`lattice resume`)",
    ]

    public static func lastLogLines(_ limit: Int = 10) -> [String] {
        guard limit > 0, let data = try? Data(contentsOf: LatticeControl.logURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(limit))
    }

    public static func logSize() -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: LatticeControl.logPath) else {
            return nil
        }
        return (attributes[.size] as? NSNumber)?.intValue
    }

    public static func fileExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// `"0700"`-style permission string for the socket, or nil when it is absent.
    public static func posixMode(_ path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return String(format: "%04o", info.st_mode & 0o777)
    }

    public static var macOSVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}
