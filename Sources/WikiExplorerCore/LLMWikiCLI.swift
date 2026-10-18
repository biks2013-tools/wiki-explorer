import Foundation

/// A failed `llm-wiki` run. Exit codes follow the CLI: 1 operational, 2 configuration, 3 LLM provider.
public struct CLIError: Error, LocalizedError, Sendable {
    public let exitCode: Int32
    /// The CLI's `error: ...` message, or the last stderr lines when there is none.
    public let message: String
    public let arguments: [String]

    public init(exitCode: Int32, message: String, arguments: [String]) {
        self.exitCode = exitCode
        self.message = message
        self.arguments = arguments
    }

    public var errorDescription: String? { message }

    public var kind: String {
        switch exitCode {
        case 2: return "Configuration error"
        case 3: return "LLM provider error"
        default: return "llm-wiki error"
        }
    }

    /// Extracts the `error: ...` line the CLI prints, falling back to the last non-empty stderr lines.
    public static func message(fromStderr stderr: String) -> String {
        let lines = stderr.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if let err = lines.last(where: { $0.hasPrefix("error: ") }) { return String(err.dropFirst("error: ".count)) }
        return lines.suffix(3).joined(separator: "\n")
    }
}

/// Runs the `llm-wiki` CLI with a given environment and decodes its `--json` output.
public final class LLMWikiCLI: Sendable {
    public let executable: URL
    public let environment: [String: String]

    public init(executable: URL, environment: [String: String]) {
        self.executable = executable
        self.environment = environment
    }

    /// Runs `llm-wiki <args>`; returns stdout. `onStderrLine` receives progress lines as they arrive.
    public func run(_ args: [String], onStderrLine: (@Sendable (String) -> Void)? = nil) async throws -> Data {
        let executable = self.executable
        let environment = self.environment
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = args
                process.environment = environment
                process.standardInput = FileHandle.nullDevice
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    cont.resume(throwing: CLIError(exitCode: -1, message: "Could not start \(executable.path): \(error.localizedDescription)", arguments: args))
                    return
                }
                var stdout = Data()
                var stderr = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    stdout = out.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    var pending = Data()
                    while true {
                        let chunk = err.fileHandleForReading.availableData
                        if chunk.isEmpty { break }
                        stderr.append(chunk)
                        pending.append(chunk)
                        while let nl = pending.firstIndex(of: 0x0A) {
                            let line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
                            pending.removeSubrange(pending.startIndex...nl)
                            onStderrLine?(line)
                        }
                    }
                    if !pending.isEmpty { onStderrLine?(String(decoding: pending, as: UTF8.self)) }
                    group.leave()
                }
                group.wait()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    cont.resume(returning: stdout)
                } else {
                    let text = String(decoding: stderr, as: UTF8.self)
                    cont.resume(throwing: CLIError(exitCode: process.terminationStatus, message: CLIError.message(fromStderr: text), arguments: args))
                }
            }
        }
    }

    /// Runs a `--json` command and decodes its stdout. Some commands (lint) exit 1 with a valid report;
    /// pass `acceptingExitCodes` to decode stdout in that case too.
    public func json<T: Decodable>(_ type: T.Type, _ args: [String], onStderrLine: (@Sendable (String) -> Void)? = nil) async throws -> T {
        let data = try await run(args, onStderrLine: onStderrLine)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CLIError(exitCode: 0, message: "Unexpected output from llm-wiki \(args.first ?? ""): \(error.localizedDescription)", arguments: args)
        }
    }

    // MARK: - Commands used by the app

    public func version() async throws -> String {
        String(decoding: try await run(["--version"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func listWikis() async throws -> [WikiSummary] {
        try await json([WikiSummary].self, ["wikis", "list", "--json"])
    }

    public func pages(wiki: String) async throws -> PagesResponse {
        try await json(PagesResponse.self, ["--wiki", wiki, "pages", "--json"])
    }

    public func show(wiki: String, page: String) async throws -> PageView {
        try await json(PageView.self, ["--wiki", wiki, "show", page, "--json"])
    }

    /// The whole wiki as a graph: pages, links, cited source files, broken links.
    public func graph(wiki: String) async throws -> WikiGraph {
        try await json(WikiGraph.self, ["--wiki", wiki, "graph", "--json"])
    }

    public func search(wiki: String?, allWikis: Bool, query: String, limit: Int = 30) async throws -> [SearchHit] {
        var args = allWikis ? [String]() : ["--wiki", wiki ?? ""]
        args += ["search", query, "--json", "--limit", String(limit)]
        if allWikis { args.append("--all-wikis") }
        return try await json([SearchHit].self, args)
    }

    public func query(wikis: [String], question: String, file: Bool, onStderrLine: (@Sendable (String) -> Void)? = nil) async throws -> QueryResponse {
        var args: [String]
        if wikis.count == 1 {
            args = ["--wiki", wikis[0], "query", question, "--json"]
            if file { args.append("--file") }
        } else {
            args = ["query", question, "--json", "--wikis", wikis.joined(separator: ",")]
        }
        return try await json(QueryResponse.self, args, onStderrLine: onStderrLine)
    }

    public func ingest(wiki: String, sources: [String], dryRun: Bool, render: Bool = false, onStderrLine: (@Sendable (String) -> Void)? = nil) async throws -> IngestResponse {
        var args = ["--wiki", wiki, "ingest"] + sources + ["--json"]
        if dryRun { args.append("--dry-run") }
        if render { args.append("--render") }
        return try await json(IngestResponse.self, args, onStderrLine: onStderrLine)
    }

    public func initWiki(directory: String, format: String, name: String, description: String?, makeCurrent: Bool, onStderrLine: (@Sendable (String) -> Void)? = nil) async throws {
        var args = ["init", directory, "--format", format, "--name", name]
        if let description, !description.isEmpty { args += ["--description", description] }
        if makeCurrent { args.append("--use") }
        _ = try await run(args, onStderrLine: onStderrLine)
    }

    /// Compares every outside source (URLs, files from outside the wiki) with its latest raw copy by SHA-256.
    public func checkSources(wiki: String, onStderrLine: (@Sendable (String) -> Void)? = nil) async throws -> SourcesCheckResponse {
        try await json(SourcesCheckResponse.self, ["--wiki", wiki, "sources", "check", "--json"], onStderrLine: onStderrLine)
    }

    /// Re-ingests every changed outside source (new raw copy, then compiled into the wiki).
    public func updateSources(wiki: String, onStderrLine: (@Sendable (String) -> Void)? = nil) async throws -> SourcesUpdateResponse {
        try await json(SourcesUpdateResponse.self, ["--wiki", wiki, "sources", "update", "--json"], onStderrLine: onStderrLine)
    }

    public func configReport() async throws -> String {
        String(decoding: try await run(["config"]), as: UTF8.self)
    }
}
