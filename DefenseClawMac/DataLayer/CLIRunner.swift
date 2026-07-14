// Direct argv execution for DefenseClaw commands. Catalog actions, setup,
// diagnostics, and the command palette all share this runner so arguments are
// never interpolated through a shell.

import Darwin
import Foundation

struct CLIResult: Sendable {
    var exitCode: Int32
    var output: String
    var cancelled: Bool = false
    var succeeded: Bool { exitCode == 0 && !cancelled }
}

enum CLICancellationDisposition: Sendable, Equatable {
    case requested
    case alreadyRequested
    case finishing
    case notFound
}

/// Coordinates the detached pipe reader with direct-process termination.
/// Descendants may inherit stdout/stderr and keep the pipe open after the
/// command itself exits, so EOF alone is not a reliable completion signal.
private final class CLIOutputReadControl: @unchecked Sendable {
    private let lock = NSLock()
    private var parentExited = false

    func markParentExited() {
        lock.lock()
        parentExited = true
        lock.unlock()
    }

    var hasParentExited: Bool {
        lock.lock()
        defer { lock.unlock() }
        return parentExited
    }
}

actor CLIRunner {
    /// User override (App Settings ▸ Connection) wins; otherwise search standard locations.
    static let pathOverrideKey = "defenseclawBinaryPath"

    private struct ActiveRun {
        let token: UUID
        let process: Process
        var cancellationRequested: Bool
    }

    private enum RunState {
        case reserved(cancelRequested: Bool)
        case running(ActiveRun)
    }

    private var cachedPaths: [String: String] = [:]
    private var runStates: [UUID: RunState] = [:]

    /// Reserve an Activity run before its visible row is published so a
    /// cancellation racing process launch is retained instead of discarded.
    func reserve(runID: UUID) -> Bool {
        guard runStates[runID] == nil else { return false }
        runStates[runID] = .reserved(cancelRequested: false)
        return true
    }

    func locateBinary() -> String? {
        locateBinary(named: "defenseclaw")
    }

    func locateBinary(named name: String) -> String? {
        // Absolute paths (e.g. the DefenseClaw venv python) pass through.
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        // Override outranks the cache: a path freshly set in Settings must
        // win immediately even while the previously cached binary still
        // exists (the cache otherwise pins the old install forever).
        if name == "defenseclaw",
           let override = UserDefaults.standard.string(forKey: Self.pathOverrideKey),
           FileManager.default.isExecutableFile(atPath: override) {
            cachedPaths[name] = override
            return override
        }
        if let cached = cachedPaths[name], FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            cachedPaths[name] = candidate
            return candidate
        }
        if let found = which(name) {
            cachedPaths[name] = found
            return found
        }
        return nil
    }

    /// Augmented-PATH lookup for an arbitrary tool (scanner probe fallback).
    /// Subprocess-backed — callers cache the result; never run on the pulse.
    func locateTool(_ name: String) -> String? {
        which(name)
    }

    private func which(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        proc.environment = Self.subprocessEnvironment()
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return proc.terminationStatus == 0 && !out.isEmpty ? out : nil
    }

    /// Finder/LaunchServices apps do not inherit the user's interactive shell
    /// PATH. Preserve any path supplied by the parent process, then add the
    /// standard macOS package-manager and Docker Desktop locations used by the
    /// DefenseClaw CLI and its helper tools.
    static func subprocessEnvironment(
        inheriting environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> [String: String] {
        var result = environment
        let inherited = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let fallbacks = [
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.docker/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/opt/local/bin",
            "/opt/local/sbin",
            "/Applications/Docker.app/Contents/Resources/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        var seen = Set<String>()
        let merged = (inherited + fallbacks).filter { directory in
            !directory.isEmpty && seen.insert(directory).inserted
        }
        result["PATH"] = merged.joined(separator: ":")
        return result
    }

    /// Runs `defenseclaw <args>`, streaming combined output lines to `onLine`.
    func run(
        arguments: [String],
        runID: UUID? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async -> CLIResult {
        await run(binary: "defenseclaw", arguments: arguments, runID: runID, onLine: onLine)
    }

    /// Runs a DefenseClaw executable with optional stdin. `standardInput` is
    /// used for hidden-prompt flows such as `keys set`, keeping secrets out of
    /// argv and process listings.
    func run(
        binary binaryName: String,
        arguments: [String],
        standardInput: String? = nil,
        runID: UUID? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async -> CLIResult {
        let executionID = runID ?? UUID()
        if runID != nil {
            switch runStates[executionID] {
            case .reserved(let cancelRequested):
                runStates[executionID] = nil
                if cancelRequested {
                    return CLIResult(
                        exitCode: 130,
                        output: "Command cancelled before launch.\n",
                        cancelled: true
                    )
                }
            case .running:
                return CLIResult(
                    exitCode: 125,
                    output: "A command with this run identifier is already active.\n"
                )
            case nil:
                break
            }
        }

        guard let binary = locateBinary(named: binaryName) else {
            let setting = binaryName == "defenseclaw" ? " Set its path in Settings ▸ Connection." : ""
            return CLIResult(exitCode: 127, output: "\(binaryName) binary not found.\(setting)")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = arguments
        var env = Self.subprocessEnvironment()
        env["NO_COLOR"] = "1"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        let inputPipe = standardInput == nil ? nil : Pipe()
        proc.standardInput = inputPipe

        do {
            try proc.run()
        } catch {
            return CLIResult(exitCode: 126, output: "Failed to launch \(binary): \(error.localizedDescription)")
        }
        let runToken = UUID()
        runStates[executionID] = .running(ActiveRun(
            token: runToken,
            process: proc,
            cancellationRequested: false
        ))

        if let standardInput, let inputPipe {
            inputPipe.fileHandleForWriting.write(Data((standardInput + "\n").utf8))
            try? inputPipe.fileHandleForWriting.close()
        }

        let readControl = CLIOutputReadControl()
        let terminationTask = Task.detached(priority: .utility) {
            proc.waitUntilExit()
            readControl.markParentExited()
            return proc.terminationStatus
        }

        // Keep process waiting and pipe reads off the actor so Cancel remains
        // responsive. poll(2) also bounds a descendant-held output pipe after
        // the direct command has exited.
        let outputTask = Task.detached(priority: .utility) {
            var output = Data()
            var pendingLine = Data()
            var readBuffer = [UInt8](repeating: 0, count: 64 * 1_024)
            var parentExitObservedAt: ContinuousClock.Instant?

            readLoop: while true {
                if readControl.hasParentExited {
                    let now = ContinuousClock.now
                    if let observedAt = parentExitObservedAt,
                       now - observedAt >= .milliseconds(500) {
                        break readLoop
                    }
                    if parentExitObservedAt == nil { parentExitObservedAt = now }
                }

                var descriptor = pollfd(
                    fd: pipe.fileHandleForReading.fileDescriptor,
                    events: Int16(POLLIN | POLLHUP | POLLERR),
                    revents: 0
                )
                let pollResult = Darwin.poll(&descriptor, 1, 100)
                if pollResult == 0 {
                    if readControl.hasParentExited { break readLoop }
                    continue readLoop
                }
                if pollResult < 0 {
                    if errno == EINTR { continue readLoop }
                    let message = "[output stream error: \(String(cString: strerror(errno)))]\n"
                    output.append(Data(message.utf8))
                    onLine?(message.trimmingCharacters(in: .newlines))
                    break readLoop
                }

                let byteCount = readBuffer.withUnsafeMutableBytes { buffer in
                    Darwin.read(
                        pipe.fileHandleForReading.fileDescriptor,
                        buffer.baseAddress,
                        buffer.count
                    )
                }
                if byteCount == 0 { break readLoop }
                if byteCount < 0 {
                    if errno == EINTR { continue readLoop }
                    let message = "[output stream error: \(String(cString: strerror(errno)))]\n"
                    output.append(Data(message.utf8))
                    onLine?(message.trimmingCharacters(in: .newlines))
                    break readLoop
                }

                let chunk = Data(readBuffer.prefix(byteCount))
                output.append(chunk)
                pendingLine.append(chunk)
                while let newline = pendingLine.firstIndex(of: 0x0A) {
                    let line = String(decoding: pendingLine[..<newline], as: UTF8.self)
                    onLine?(line)
                    pendingLine.removeSubrange(...newline)
                }
            }

            if !pendingLine.isEmpty {
                onLine?(String(decoding: pendingLine, as: UTF8.self))
            }
            return String(decoding: output, as: UTF8.self)
        }

        let completion = await withTaskCancellationHandler {
            let output = await outputTask.value
            let exitCode = await terminationTask.value
            return (output, exitCode)
        } onCancel: {
            Task {
                await self.requestCancellation(executionID: executionID, token: runToken)
            }
        }

        let explicitlyCancelled: Bool
        if case .running(let active) = runStates[executionID], active.token == runToken {
            explicitlyCancelled = active.cancellationRequested
            runStates[executionID] = nil
        } else {
            explicitlyCancelled = false
        }
        return CLIResult(
            exitCode: completion.1,
            output: completion.0,
            cancelled: Task.isCancelled || explicitlyCancelled
        )
    }

    /// Request bounded cancellation of an Activity-owned process. Repeated
    /// requests share one escalation ladder and cannot target a later run that
    /// happens to reuse the same public identifier.
    @discardableResult
    func cancel(runID: UUID) -> CLICancellationDisposition {
        requestCancellation(executionID: runID, token: nil)
    }

    private func requestCancellation(
        executionID: UUID,
        token expectedToken: UUID?
    ) -> CLICancellationDisposition {
        guard let state = runStates[executionID] else { return .notFound }
        switch state {
        case .reserved(let cancelRequested):
            guard !cancelRequested else { return .alreadyRequested }
            runStates[executionID] = .reserved(cancelRequested: true)
            return .requested
        case .running(var active):
            if let expectedToken, active.token != expectedToken { return .notFound }
            guard !active.cancellationRequested else { return .alreadyRequested }
            guard active.process.isRunning else { return .finishing }
            active.cancellationRequested = true
            runStates[executionID] = .running(active)
            active.process.interrupt()
            scheduleCancellationEscalation(executionID: executionID, token: active.token)
            return .requested
        }
    }

    private func scheduleCancellationEscalation(executionID: UUID, token: UUID) {
        Task.detached { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.terminateIfNeeded(executionID: executionID, token: token)
            try? await Task.sleep(for: .seconds(1))
            await self?.killIfNeeded(executionID: executionID, token: token)
        }
    }

    private func terminateIfNeeded(executionID: UUID, token: UUID) {
        guard case .running(let active) = runStates[executionID],
              active.token == token,
              active.cancellationRequested,
              active.process.isRunning else { return }
        active.process.terminate()
    }

    private func killIfNeeded(executionID: UUID, token: UUID) {
        guard case .running(let active) = runStates[executionID],
              active.token == token,
              active.cancellationRequested,
              active.process.isRunning else { return }
        Darwin.kill(active.process.processIdentifier, SIGKILL)
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
