import Darwin
import Foundation

struct DoctorCheck {
    enum Result { case pass, warn, fail }
    var name: String
    var result: Result
    var detail: String
}

actor UpgradeTestCalls {
    var actions: [GatewayAdminAction] = []
    func record(_ action: GatewayAdminAction) { actions.append(action) }
}

@main
struct RuntimeUpgradeAgentsTests {
    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    static func main() async throws {
        CLIProcessGroupLauncher.execIfRequested()
        if URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "opencode" {
            fixtureAgent()
            return
        }
        identification()
        summaries()
        try nativeProcessDetection()
        for scenario in ["blocked", "success", "amp", "v1", "version-failure", "stop-failure", "respawn", "cancelled", "cancel-finishing", "scan-failure", "selection-change"] {
            try await orchestration(scenario)
        }
        print("RuntimeUpgradeAgentsTests passed")
    }

    static func fixtureAgent() {
        let directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let scenario = (try? String(contentsOf: directory.appendingPathComponent("scenario"), encoding: .utf8)) ?? "success"
        if CommandLine.arguments.dropFirst() == ["--version"] {
            if scenario == "version-failure" { exit(3) }
            print(scenario == "v1" ? "1.9.0" : "2.2.5")
            return
        }
        if CommandLine.arguments.dropFirst() == ["service", "stop"] {
            try! Data().write(to: directory.appendingPathComponent("stop-called"))
            if scenario == "stop-failure" { print("fixture stop failed"); exit(3) }
            if scenario == "cancelled" { sleep(30) }
            if scenario != "respawn" { try? FileManager.default.removeItem(at: directory.appendingPathComponent("running")) }
            if scenario == "cancel-finishing" { print("fixture service stopped") }
            return
        }
        if CommandLine.arguments.dropFirst() == ["--hold"] { sleep(30); return }
        exit(64)
    }

    static func identification() {
        let processes: [RuntimeUpgradeAgents.ProcessIdentity] = [
            .init(pid: 21, uid: 501, executable: "/installed/opencode"),
            .init(pid: 22, uid: 502, executable: "/installed/opencode"),
            .init(pid: 23, uid: 501, executable: "/unrelated/opencode"),
            .init(pid: 24, uid: 501, executable: "/installed/amp"),
        ]
        let found = RuntimeUpgradeAgents.match(processes, entries: ["/installed/opencode": .openCode, "/installed/amp": .amp], uid: 501)
        expect(found.map(\.pid) == [21, 24], "only exact installed executable paths belonging to this account block")
        for version in ["2.2.5", "v2.2.5", "opencode v2.3.2", "opencode 2.3.0-beta.1\n"] {
            expect(RuntimeUpgradeAgents.isV2(version), "V2 recognized: \(version)")
        }
        for version in ["1.2.5", "3.0.0", "error 2.2.5", "2.2.5\nother output"] {
            expect(!RuntimeUpgradeAgents.isV2(version), "ambiguous/non-V2 version rejected: \(version)")
        }
    }

    static func summaries() {
        let reported = "  ✓ DefenseClaw 1.0.10 is staged and checked\n  ✗ Close OpenCode and Amp completely before installing or upgrading DefenseClaw; gateway still running: OpenCode (PID 92506)\n"
        expect(RuntimeUpgradeAgents.failureSummary(reported)?.contains("Close OpenCode and Amp") == true,
               "the real installer failure must be visible instead of generic exit 1")
        let blocked = RuntimeUpgradeAgents.blocked([.init(kind: .openCode, pid: 21, executable: "/installed/opencode")])
        expect(blocked.runtimeUpgradeNeedsOpenCodeStop, "typed stop action is offered for OpenCode only")
        expect(RuntimeUpgradeAgents.failureSummary(blocked.output)?.contains("background server") == true, "preflight guidance explains why closing the window is insufficient")
        expect(!RuntimeUpgradeAgents.blocked([.init(kind: .amp, pid: 24, executable: "/installed/amp")]).runtimeUpgradeNeedsOpenCodeStop,
               "Amp cannot be stopped using OpenCode's service command")
    }

    static func nativeProcessDetection() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("upgrade-process-" + UUID().uuidString)
        let directory = home.appendingPathComponent(".opencode/bin")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let agent = directory.appendingPathComponent("opencode")
        try fm.copyItem(at: Bundle.main.executableURL!, to: agent)
        let process = Process()
        process.executableURL = agent
        process.arguments = ["--hold"]
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        usleep(100_000)
        let found = try RuntimeUpgradeAgents.running(home: home.path, path: "")
        expect(found.contains { $0.pid == process.processIdentifier && $0.kind == .openCode }, "kernel process scan finds a detached/background-style native OpenCode executable")
    }

    static func orchestration(_ scenario: String) async throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".defenseclawmac-agent-upgrade-test-" + UUID().uuidString)
        let runtime = root.appendingPathComponent("runtime")
        let bin = runtime.appendingPathComponent(".venv/bin")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let agent = root.appendingPathComponent("opencode")
        try fm.copyItem(at: Bundle.main.executableURL!, to: agent)
        try Data(scenario.utf8).write(to: root.appendingPathComponent("scenario"))
        try Data().write(to: root.appendingPathComponent("running"))
        let cli = bin.appendingPathComponent("defenseclaw")
        try Data("#!/bin/sh\n/usr/bin/touch \"$DEFENSECLAW_HOME/upgrade-ran\"\nprintf 'fixture installer completed\\n'\n".utf8).write(to: cli)
        _ = chmod(cli.path, 0o700)
        let context = InstallationContext.resolve(environment: ["DEFENSECLAW_HOME": runtime.path], appConfigOverride: nil,
            userHome: root, fileExists: fm.fileExists(atPath:), readText: { _ in nil })
        let calls = UpgradeTestCalls()
        let runner = CLIRunner(context: context, upgradeAgents: {
            if scenario == "scan-failure" { throw CocoaError(.fileReadUnknown) }
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent("running").path) { return [] }
            return [.init(kind: scenario == "amp" ? .amp : .openCode, pid: 21, executable: agent.path)]
        }, administratorEnabled: { true }, administratorExecutor: { action, _, _ in
            await calls.record(action)
            return CLIResult(exitCode: 0, output: "fixture gateway \(action.rawValue)\n")
        })
        let id = UUID()
        let task = Task {
            await runner.run(binary: cli.path, arguments: ["upgrade", "--yes", "--version", "1.0.10"],
                stopOpenCodeForUpgrade: scenario != "blocked", runID: id, onLine: { line in
                    if scenario == "cancel-finishing", line.contains("fixture service stopped") {
                        try? await Task.sleep(for: .milliseconds(200))
                        let disposition = await runner.cancel(runID: id)
                        expect(disposition == .finishing, "fixture cancels after the service command has exited")
                    }
                    if scenario == "selection-change", line.contains("Stopping OpenCode") {
                        await runner.rebind(to: .resolve(environment: ["DEFENSECLAW_HOME": root.appendingPathComponent("other").path],
                            appConfigOverride: nil, userHome: root, fileExists: { _ in false }, readText: { _ in nil }))
                    }
                })
        }
        if scenario == "cancelled" {
            for _ in 0..<100 {
                if fm.fileExists(atPath: root.appendingPathComponent("stop-called").path) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            expect(fm.fileExists(atPath: root.appendingPathComponent("stop-called").path), "service stop began before cancellation")
            let concurrent = await runner.run(binary: "/usr/bin/true", arguments: [], mutation: false)
            expect(concurrent.exitCode == 75, "service stop is inside the exclusive upgrade operation")
            _ = await runner.cancel(runID: id)
        }
        let result = await task.value
        let ran = fm.fileExists(atPath: runtime.appendingPathComponent("upgrade-ran").path)
        let stopped = fm.fileExists(atPath: root.appendingPathComponent("stop-called").path)
        let actions = await calls.actions
        if scenario == "success" {
            expect(result.succeeded && ran && stopped && actions == [.stop, .restart], "confirmed stop precedes installer and gateway recovery")
        } else {
            expect(!result.succeeded && !ran && actions.isEmpty, "\(scenario): preflight failure leaves runtime and gateway untouched")
            if ["blocked", "amp", "v1", "version-failure", "scan-failure", "selection-change"].contains(scenario) {
                expect(!stopped, "\(scenario): no service mutation without current consent and valid V2 command")
            }
            if scenario == "blocked" || scenario == "respawn" { expect(result.runtimeUpgradeNeedsOpenCodeStop, "retry remains actionable") }
            if scenario == "cancelled" || scenario == "cancel-finishing" { expect(result.cancelled, "cancelled service stop cancels the entire upgrade") }
        }
        let resumed = await runner.run(binary: "/usr/bin/true", arguments: [], mutation: false)
        expect(resumed.succeeded, "\(scenario): exclusivity released after preparation")
        print("PASS runtime upgrade agent preparation: \(scenario)")
    }
}
