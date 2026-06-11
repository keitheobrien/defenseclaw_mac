// Runs the `defenseclaw` CLI for the operations the TUI shells out for:
// Setup wizard "Apply" (defenseclaw setup … --yes) and the doctor deep-dive.
// Direct argv execution — no shell interpolation.

import Foundation

struct CLIResult: Sendable {
    var exitCode: Int32
    var output: String
    var succeeded: Bool { exitCode == 0 }
}

actor CLIRunner {
    /// User override (App Settings ▸ Connection) wins; otherwise search standard locations.
    static let pathOverrideKey = "defenseclawBinaryPath"

    private var cachedPath: String?

    func locateBinary() -> String? {
        if let cached = cachedPath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        if let override = UserDefaults.standard.string(forKey: Self.pathOverrideKey),
           FileManager.default.isExecutableFile(atPath: override) {
            cachedPath = override
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/defenseclaw",
            "/opt/homebrew/bin/defenseclaw",
            "/usr/local/bin/defenseclaw",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            cachedPath = candidate
            return candidate
        }
        // Last resort: consult login-shell PATH.
        if let found = which("defenseclaw") {
            cachedPath = found
            return found
        }
        return nil
    }

    private func which(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["zsh", "-lc", "command -v \(name)"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return proc.terminationStatus == 0 && !out.isEmpty ? out : nil
    }

    /// Runs `defenseclaw <args>`, streaming combined output lines to `onLine`.
    func run(arguments: [String], onLine: (@Sendable (String) -> Void)? = nil) async -> CLIResult {
        guard let binary = locateBinary() else {
            return CLIResult(exitCode: 127, output: "defenseclaw binary not found. Set its path in Settings ▸ Connection.")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        var collected = ""
        do {
            try proc.run()
        } catch {
            return CLIResult(exitCode: 126, output: "Failed to launch \(binary): \(error.localizedDescription)")
        }

        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                collected += line + "\n"
                onLine?(line)
            }
        } catch {
            collected += "\n[output stream error: \(error.localizedDescription)]\n"
        }
        proc.waitUntilExit()
        return CLIResult(exitCode: proc.terminationStatus, output: collected)
    }

    /// Lightweight doctor probe (TUI Shift+D) — parsed into check rows.
    func doctor() async -> [DoctorCheck] {
        let result = await run(arguments: ["doctor"])
        guard result.succeeded || !result.output.isEmpty else {
            return [DoctorCheck(name: "defenseclaw doctor", result: .fail, detail: result.output)]
        }
        var checks: [DoctorCheck] = []
        for line in result.output.split(separator: "\n").map(String.init) {
            let lower = line.lowercased()
            let outcome: DoctorCheck.Result
            if lower.contains("pass") || lower.contains("✓") || lower.contains("ok") {
                outcome = .pass
            } else if lower.contains("warn") || lower.contains("⚠") {
                outcome = .warn
            } else if lower.contains("fail") || lower.contains("✗") || lower.contains("error") {
                outcome = .fail
            } else {
                continue
            }
            let name = line
                .replacingOccurrences(of: "✓", with: "")
                .replacingOccurrences(of: "⚠", with: "")
                .replacingOccurrences(of: "✗", with: "")
                .trimmingCharacters(in: .whitespaces)
            checks.append(DoctorCheck(name: String(name.prefix(80)), result: outcome, detail: line))
        }
        if checks.isEmpty {
            checks.append(DoctorCheck(
                name: "doctor",
                result: result.succeeded ? .pass : .fail,
                detail: String(result.output.suffix(400))
            ))
        }
        return checks
    }
}
