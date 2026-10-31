import Foundation

/// Shared contract between the Lattice app (server) and the `lattice` CLI (client).
///
/// Transport: a Unix domain socket at `~/Library/Application Support/Lattice/control.sock`.
/// Framing: one UTF-8 JSON object per line, in both directions. A request line looks like
/// `{"command":"layout","arguments":["columns"],"flags":{}}`; the reply is a `ControlResponse`.
/// Nothing here touches AppKit, so the CLI can link LatticeKit without pulling in the GUI.
public enum LatticeControl {
    /// Bumped only when the wire format changes incompatibly.
    public static let protocolVersion = 1

    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lattice", isDirectory: true)
    }

    public static var socketURL: URL {
        supportDirectory.appendingPathComponent("control.sock")
    }

    public static var socketPath: String { socketURL.path }

    public static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Lattice", isDirectory: true)
            .appendingPathComponent("lattice.log")
    }

    public static var logPath: String { logURL.path }

    /// The bundle's short version when running from `Lattice.app`, with a sane fallback for
    /// `swift run lattice`.
    public static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    public static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    public static var versionSummary: String { "\(version) (\(build))" }
}

// MARK: - Request

public struct ControlRequest: Codable, Sendable, Equatable {
    public var command: String
    public var arguments: [String]
    public var flags: [String: String]

    public init(command: String, arguments: [String] = [], flags: [String: String] = [:]) {
        self.command = command
        self.arguments = arguments
        self.flags = flags
    }

    private enum CodingKeys: String, CodingKey { case command, arguments, flags }

    /// Tolerant decoding keeps old scripts working when new fields are added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        flags = try container.decodeIfPresent([String: String].self, forKey: .flags) ?? [:]
    }
}

// MARK: - Response

public struct ControlResponse: Codable, Sendable, Equatable {
    public var ok: Bool
    public var message: String?
    public var data: [String: ControlValue]?

    public init(ok: Bool, message: String? = nil, data: [String: ControlValue]? = nil) {
        self.ok = ok
        self.message = message
        self.data = data
    }

    public static func success(_ message: String? = nil, data: [String: ControlValue]? = nil) -> ControlResponse {
        ControlResponse(ok: true, message: message, data: data)
    }

    public static func failure(_ message: String) -> ControlResponse {
        ControlResponse(ok: false, message: message, data: nil)
    }
}

// MARK: - Values

/// A tiny, dependency-free JSON value used for `ControlResponse.data`.
/// Typed enough for the CLI to render tables without re-parsing free-form JSON.
public enum ControlValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([ControlValue])
    case object([String: ControlValue])

    // Convenience constructors keep the server code readable.
    public static func numbers(_ values: [Int]) -> ControlValue { .array(values.map { .int($0) }) }
    public static func strings(_ values: [String]) -> ControlValue { .array(values.map { .string($0) }) }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value) where value.rounded() == value: return Int(value)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [ControlValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: ControlValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> ControlValue? {
        objectValue?[key]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ControlValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ControlValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported control value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Wire helpers

public enum ControlWire {
    /// A request line longer than this is rejected instead of buffered forever.
    public static let maxLineBytes = 1_048_576

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }
}
