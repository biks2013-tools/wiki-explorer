import Foundation

/// The llm-wiki settings file, `~/.tool-agents/llm-wiki/.env`, edited in place: comments, blank lines, order and
/// untouched lines are kept as they are; only the lines of changed keys are rewritten. Reading follows the CLI's
/// parser (`parseDotenv` in wiki-v2 `src/config/env.ts`): optional `export`, single or double quotes, ` #` comments
/// after unquoted values, last occurrence wins.
public struct DotenvFile: Equatable, Sendable {
    enum Line: Equatable, Sendable {
        case other(String)
        case entry(key: String, value: String, raw: String)
    }

    var lines: [Line]

    public init(text: String) {
        var lines: [Line] = []
        var parts = text.components(separatedBy: "\n")
        if parts.last == "" { parts.removeLast() }
        for raw in parts {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if let (key, value) = Self.parse(line) {
                lines.append(.entry(key: key, value: value, raw: line))
            } else {
                lines.append(.other(line))
            }
        }
        self.lines = lines
    }

    /// The location the CLI uses: `~/.tool-agents/llm-wiki/.env`.
    public static func defaultURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".tool-agents/llm-wiki/.env")
    }

    /// Reads the file; a missing file is an empty one (the CLI treats it the same way).
    public static func load(from url: URL) throws -> DotenvFile {
        guard FileManager.default.fileExists(atPath: url.path) else { return DotenvFile(text: "") }
        return DotenvFile(text: try String(contentsOf: url, encoding: .utf8))
    }

    /// Writes atomically with mode 0600, creating the folder with mode 0700 when missing (as the CLI does).
    public func save(to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let tmp = dir.appendingPathComponent(".env.wiki-explorer-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: tmp.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tmp.path])
        }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }

    public var text: String {
        lines.isEmpty ? "" : lines.map { line -> String in
            switch line {
            case let .other(s): return s
            case let .entry(_, _, raw): return raw
            }
        }.joined(separator: "\n") + "\n"
    }

    /// Effective values (last occurrence of a key wins, as in the CLI).
    public var values: [String: String] {
        var out: [String: String] = [:]
        for case let .entry(key, value, _) in lines { out[key] = value }
        return out
    }

    /// Keys in file order, each once.
    public var keys: [String] {
        var seen = Set<String>()
        return lines.compactMap { line in
            guard case let .entry(key, _, _) = line, seen.insert(key).inserted else { return nil }
            return key
        }
    }

    public subscript(key: String) -> String? { values[key] }

    /// Sets a key: rewrites its last line (earlier duplicates are dropped), or appends it. `nil` or an empty value
    /// removes the key: the CLI has no defaults, so "not set" means absent, never an empty value.
    public mutating func set(_ key: String, _ value: String?) {
        guard let value, !value.isEmpty else {
            lines.removeAll { if case let .entry(k, _, _) = $0 { return k == key } else { return false } }
            return
        }
        if values[key] == value { return }
        let raw = "\(key)=\(Self.quote(value))"
        if let last = lines.lastIndex(where: { if case let .entry(k, _, _) = $0 { return k == key } else { return false } }) {
            let keepExport: Bool = { if case let .entry(_, _, r) = lines[last] { return r.trimmingCharacters(in: .whitespaces).hasPrefix("export ") } else { return false } }()
            lines[last] = .entry(key: key, value: value, raw: keepExport ? "export \(raw)" : raw)
            var i = 0
            lines.removeAll { line in
                defer { i += 1 }
                if case let .entry(k, _, _) = line { return k == key && i != last }
                return false
            }
        } else {
            lines.append(.entry(key: key, value: value, raw: raw))
        }
    }

    /// A value as the CLI's parser reads it back: bare when safe, else double-quoted with `\"` and `\n` escaped.
    static func quote(_ value: String) -> String {
        let safe = value.range(of: #"^[A-Za-z0-9_./:@+,=%~-]*$"#, options: .regularExpression) != nil
        if safe { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    static func parse(_ rawLine: String) -> (String, String)? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { return nil }
        guard let match = line.firstMatch(of: #/^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/#) else { return nil }
        let key = String(match.1)
        var value = String(match.2).trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, (first == "\"" || first == "'"), value.last == first {
            value = String(value.dropFirst().dropLast())
            if first == "\"" { value = value.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"") }
        } else if let hash = value.range(of: " #") {
            value = String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return (key, value)
    }
}
