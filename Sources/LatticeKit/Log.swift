import Foundation
import AppKit
import ApplicationServices

public enum Log {
    nonisolated(unsafe) public static var verbose = ProcessInfo.processInfo.environment["LATTICE_DEBUG"] == "1"
    private static let queue = DispatchQueue(label: "app.lattice.log")
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Lattice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lattice.log")
    }()

    public static func info(_ message: @autoclosure () -> String) {
        write("INFO", message())
    }

    public static func error(_ message: @autoclosure () -> String) {
        write("ERROR", message())
    }

    public static func debug(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        write("DEBUG", message())
    }

    private static func write(_ level: String, _ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(level) \(message)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
