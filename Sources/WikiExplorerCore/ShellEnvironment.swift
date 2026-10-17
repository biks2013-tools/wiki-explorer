import Foundation

/// An app started from the Finder or the Dock does not inherit the user's shell environment: no
/// Homebrew/pnpm PATH (so neither `llm-wiki` nor `node` is found) and none of the API keys exported in
/// the shell profile. The app therefore asks the user's login shell for its environment once, the way
/// editors do, and runs `llm-wiki` with it. The values are never logged or displayed.
public enum ShellEnvironment {
    static let startMarker = "__WIKI_EXPLORER_ENV_START__"
    static let endMarker = "__WIKI_EXPLORER_ENV_END__"

    public struct CaptureError: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Parses the output of `printf START; env -0; printf END` (anything the profile prints around it is ignored).
    public static func parse(_ output: Data) -> [String: String]? {
        let start = Data(startMarker.utf8)
        let end = Data(endMarker.utf8)
        guard let s = output.range(of: start), let e = output.range(of: end, in: s.upperBound..<output.endIndex) else { return nil }
        var env: [String: String] = [:]
        for entry in output[s.upperBound..<e.lowerBound].split(separator: 0) {
            guard let text = String(data: Data(entry), encoding: .utf8), let eq = text.firstIndex(of: "=") else { continue }
            env[String(text[..<eq])] = String(text[text.index(after: eq)...])
        }
        return env
    }

    /// The user's login shell, from the process environment or the password database.
    public static func loginShell(processEnv: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let shell = processEnv["SHELL"], !shell.isEmpty { return shell }
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell { return String(cString: sh) }
        return "/bin/zsh"
    }

    /// Runs the login shell (interactive, so `.zshrc` exports count too) and returns its environment.
    public static func capture(shell: String = loginShell(), timeout: TimeInterval = 15) throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-i", "-c", "printf '%s' '\(startMarker)'; /usr/bin/env -0; printf '%s' '\(endMarker)'"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw CaptureError(message: "Could not start \(shell) to read the shell environment: \(error.localizedDescription)")
        }
        let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        guard let env = parse(data) else {
            throw CaptureError(message: "\(shell) did not report its environment within \(Int(timeout)) s. Check that your shell profile does not wait for input.")
        }
        return env
    }

    /// Absolute path of an executable on the environment's PATH, if any.
    public static func findExecutable(named name: String, in env: [String: String]) -> String? {
        for dir in (env["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
