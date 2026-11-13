// Copyright 2026 Cisco Systems, Inc. and its affiliates
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation
import Security
import ServiceManagement

struct DoctorCheck {
    enum Result { case pass, warn, fail }
    var name: String
    var result: Result
    var detail: String
}

private actor InvocationProbe {
    var calls: [(GatewayAdminAction, InstallationContext)] = []
    var released = false
    func record(_ action: GatewayAdminAction, _ context: InstallationContext) { calls.append((action, context)) }
    func release() { released = true }
    func count() -> Int { calls.count }
    func isReleased() -> Bool { released }
    func firstContext() -> InstallationContext? { calls.first?.1 }
    func actions() -> [GatewayAdminAction] { calls.map(\.0) }
    func allContextsMatch(_ context: InstallationContext) -> Bool { calls.allSatisfy { $0.1 == context } }
}

@main
struct GatewayAdministratorTests {
    static func main() async {
        CLIProcessGroupLauncher.execIfRequested()
        testExactActionPolicy()
        testPathPolicy()
        testCodeRequirements()
        testInitialRegistrationPolicy()
        testCancellationState()
        testNativeAuthorizationResults()
        await testRoutingAndInstallationBinding()
        await testRefusalBeforeAuthorization()
        await testTaskCancellationAfterReservationRefusesDispatch()
        await testRebindCancelsPendingAuthorization()
        await testCancellationAfterDispatchWaitsForResult()
        await testRuntimeUpgradeRecovery()
        print("GatewayAdministratorTests passed")
    }

    private static func testRuntimeUpgradeRecovery() async {
        let fm = FileManager.default
        for scenario in ["success", "updater-failure", "denied", "blocked", "restart-failure", "ordinary", "ordinary-blocked", "cancelled", "help", "read-only", "cancel-activity", "selection-change"] {
            let fixture = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".defenseclawmac-upgrade-test-" + UUID().uuidString)
            let home = fixture.appendingPathComponent("runtime")
            let bin = home.appendingPathComponent(".venv/bin")
            try! fm.createDirectory(at: bin, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let cli = bin.appendingPathComponent("defenseclaw")
            let status = scenario == "updater-failure" ? 9 : 0
            try! Data("#!/bin/sh\nprintf 'fixture updater output\\n'\nif [ \"${2:-}\" = --help ]; then exit 0; fi\n/usr/bin/touch \"$DEFENSECLAW_HOME/upgrade-ran\"\nexit \(status)\n".utf8).write(to: cli)
            _ = chmod(cli.path, 0o700)
            let quarantine = home.appendingPathComponent("quarantine")
            try! fm.createDirectory(at: quarantine, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            if scenario == "blocked" || scenario == "ordinary-blocked" { _ = chmod(quarantine.path, 0o000) }
            defer { _ = chmod(quarantine.path, 0o700); try? fm.removeItem(at: fixture) }
            let selected = InstallationContext.resolve(environment: ["DEFENSECLAW_HOME": home.path],
                appConfigOverride: nil, userHome: fixture, fileExists: fm.fileExists(atPath:), readText: { _ in nil })
            let probe = InvocationProbe()
            let runner = CLIRunner(context: selected, administratorEnabled: { !scenario.hasPrefix("ordinary") },
                administratorExecutor: { action, context, operation in
                    await probe.record(action, context)
                    if scenario == "denied", action == .stop {
                        return CLIResult(exitCode: 77, output: "fixture authorization denied\n")
                    }
                    expect(operation.beginDispatch(), "recovery must execute in a fresh, uncancelled task")
                    if ["cancel-activity", "selection-change"].contains(scenario), action == .stop {
                        while !(await probe.isReleased()) { await Task.yield() }
                    }
                    if scenario == "cancelled", action == .stop {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                    if scenario == "restart-failure", action == .restart {
                        return CLIResult(exitCode: 77, output: "fixture restart denied\n")
                    }
                    return CLIResult(exitCode: 0, output: "fixture administrator \(action.rawValue)\n")
                })
            let runID = UUID()
            let task = Task {
                await runner.run(binary: cli.path,
                    arguments: scenario == "help" ? ["upgrade", "--help"] : ["upgrade", "--yes", "--version", "1.0.2"],
                    mutation: scenario != "read-only", runID: runID)
            }
            if ["cancel-activity", "selection-change"].contains(scenario) {
                await waitForCall(probe)
                let concurrent = await runner.run(binary: "/usr/bin/true", arguments: [], mutation: false)
                expect(concurrent.exitCode == 75, "preparation must hold exclusive runtime access")
                if scenario == "cancel-activity" {
                    let cancellation = await runner.cancel(runID: runID)
                    expect(cancellation == .finishing, "a dispatched Stop must finish before cancellation recovery")
                } else {
                    await runner.rebind(to: context("-reselected"))
                }
                await probe.release()
            }
            let result = await task.value
            let actions = await probe.actions()
            let ran = fm.fileExists(atPath: home.appendingPathComponent("upgrade-ran").path)
            if scenario == "help" || scenario == "read-only" {
                expect(actions.isEmpty && !ran, "help and read-only requests must never prepare or replace a runtime")
                expect(scenario == "help" ? result.succeeded : result.exitCode == 77, "help succeeds and read-only replacement refuses")
            } else if scenario == "denied" {
                expect(actions == [.stop] && !ran && result.exitCode == 77, "denial must prevent updater and extra authorization")
            } else if scenario == "ordinary" {
                expect(actions.isEmpty && ran && result.succeeded, "administrator mode off must make no helper call")
            } else if scenario == "ordinary-blocked" {
                expect(actions.isEmpty && !ran && result.exitCode == 77,
                       "unreadable data with administrator mode off must refuse before replacement or authorization")
                expect(result.output.contains("quarantine") && result.output.contains("Stop the gateway as administrator"),
                       "leftover private state must explain its path and the ownership recovery action")
            } else {
                expect(actions == [.stop, .restart], "every prepared upgrade must restore the gateway: \(scenario), actions=\(actions), result=\(result.output)")
                expect(ran == !["blocked", "cancelled", "cancel-activity", "selection-change"].contains(scenario), "preflight and cancellation must precede replacement: \(scenario), ran=\(ran), result=\(result.output)")
                if scenario == "success" { expect(result.succeeded, "successful update and restart must succeed") }
                if scenario == "updater-failure" { expect(result.exitCode == 9, "recovery must preserve installer failure") }
                if scenario == "blocked" { expect(result.output.contains("quarantine") && result.exitCode == 77, "blocked data must be explained") }
                if scenario == "restart-failure" { expect(!result.succeeded && result.output.contains("Restart Gateway as Administrator"), "restart failure cannot report success") }
                if scenario == "cancelled" || scenario == "cancel-activity" { expect(result.cancelled && !ran, "cancellation must still recover the gateway") }
                if scenario == "selection-change" {
                    expect(result.exitCode == 75 && !ran, "reselection must prevent runtime replacement")
                    let originalContext = await probe.allContextsMatch(selected)
                    expect(originalContext, "recovery must remain pinned to the stopped installation")
                }
            }
            let after = await runner.run(binary: "/usr/bin/true", arguments: [], mutation: false)
            expect(after.succeeded, "upgrade must release reservations and exclusivity: \(scenario)")
        }
    }

    private static func expect(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    private static func context(_ suffix: String = "") -> InstallationContext {
        InstallationContext.resolve(environment: [:], appConfigOverride: nil,
            userHome: URL(fileURLWithPath: "/Users/admin-test\(suffix)"),
            fileExists: { _ in false }, readText: { _ in nil })
    }

    private static func testExactActionPolicy() {
        for action in GatewayAdminAction.allCases {
            expect(GatewayAdministratorClient.selectedAction(binary: "defenseclaw-gateway", arguments: [action.rawValue], enabled: true) == action, "exact lifecycle accepted")
        }
        for arguments in [[String](), ["start", "--config", "/tmp/other"], ["START"], ["start; id"], ["status"], ["watchdog", "start"]] {
            expect(GatewayAdministratorClient.selectedAction(binary: "defenseclaw-gateway", arguments: arguments, enabled: true) == nil, "non-lifecycle request rejected")
        }
        expect(GatewayAdministratorClient.selectedAction(binary: "/tmp/defenseclaw-gateway", arguments: ["start"], enabled: true) == nil, "arbitrary executable never elevated")
        expect(GatewayAdministratorClient.selectedAction(binary: "defenseclaw-gateway", arguments: ["start"], enabled: false) == nil, "opt-in respected")
    }

    private static func testPathPolicy() {
        for path in ["relative", "/Users/me/../other", "/Users/me//a", "/Users/me/./a", "/Users/me/a\n", "/Users/me/a\0", "/Users/me/"] {
            expect(!GatewayAdminPolicy.isCanonicalAbsolutePath(path), "noncanonical path rejected: \(path.debugDescription)")
        }
        expect(GatewayAdminPolicy.isStrictDescendant("/Users/me/My DefenseClaw/config.yaml", of: "/Users/me"), "spaces remain literal")
        expect(!GatewayAdminPolicy.isStrictDescendant("/Users/me2/config.yaml", of: "/Users/me"), "sibling prefix rejected")
        expect(!GatewayAdminPolicy.isStrictDescendant("/Users/me", of: "/Users/me"), "home itself is not an installation child")
        expect(!GatewayAdminPolicy.isStrictDescendant("/etc/config.yaml", of: "/"), "root cannot become authorized installation")
    }

    private static func testCodeRequirements() {
        for expression in [GatewayAdminPolicy.appRequirement, GatewayAdminPolicy.helperRequirement, GatewayAdminPolicy.gatewayRequirement] {
            var requirement: SecRequirement?
            expect(SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess, "signing requirement parses")
            expect(expression.contains("9R236BB67S") && expression.contains("anchor apple generic"), "trusted team and Apple anchor required")
        }
    }

    private static func testInitialRegistrationPolicy() {
        expect(GatewayAdministratorClient.needsRegistration(status: .notFound, bundledServiceAvailable: true), "macOS notFound can enter first-time registration when the helper exists")
        expect(GatewayAdministratorClient.needsRegistration(status: .notRegistered, bundledServiceAvailable: true), "unregistered service is registered")
        expect(!GatewayAdministratorClient.needsRegistration(status: .notFound, bundledServiceAvailable: false), "missing helper cannot be registered")
        expect(!GatewayAdministratorClient.needsRegistration(status: .enabled, bundledServiceAvailable: true), "approved service is not re-registered")
        expect(!GatewayAdministratorClient.needsRegistration(status: .requiresApproval, bundledServiceAvailable: true), "pending approval is not confused with missing registration")
    }

    private static func testCancellationState() {
        let pending = GatewayAdministratorOperation()
        expect(pending.cancel() == .requested, "pending request can cancel")
        expect(pending.cancel() == .alreadyRequested, "repeated cancel retained")
        expect(!pending.beginDispatch(), "cancelled authorization cannot dispatch")
        let active = GatewayAdministratorOperation()
        expect(active.beginDispatch(), "authorized operation can dispatch")
        expect(!active.beginDispatch(), "operation dispatch is single-use")
        expect(active.cancel() == .finishing, "in-flight lifecycle waits for truthful completion")
    }

    private static func testNativeAuthorizationResults() {
        let cancelled = GatewayAdministratorClient.resultForHelperReply(exitCode: 130, output: "Native authorization cancelled")
        expect(cancelled.cancelled && !cancelled.succeeded, "native authorization cancellation is recorded as cancelled")
        expect(cancelled.output == "Native authorization cancelled", "helper cancellation explanation is preserved")
        let denied = GatewayAdministratorClient.resultForHelperReply(exitCode: 77, output: "Authorization denied")
        expect(!denied.cancelled && !denied.succeeded, "authorization denial remains a failure")
        let completed = GatewayAdministratorClient.resultForHelperReply(exitCode: 0, output: "Gateway started")
        expect(completed.succeeded && !completed.cancelled, "authorized gateway completion remains successful")
    }

    private static func testRoutingAndInstallationBinding() async {
        let probe = InvocationProbe()
        let selected = context()
        let runner = CLIRunner(context: selected, administratorEnabled: { true }, administratorExecutor: { action, context, _ in
            await probe.record(action, context)
            return CLIResult(exitCode: 0, output: "started via helper")
        })
        let result = await runner.run(binary: "defenseclaw-gateway", arguments: ["start"])
        expect(result.succeeded && result.output == "started via helper", "helper result preserved")
        let recorded = await probe.firstContext()
        expect(recorded == selected, "selected installation identity reaches the helper")
    }

    private static func testRefusalBeforeAuthorization() async {
        let probe = InvocationProbe()
        let execute: @Sendable (GatewayAdminAction, InstallationContext, GatewayAdministratorOperation) async -> CLIResult = { action, context, _ in
            await probe.record(action, context)
            return CLIResult(exitCode: 0, output: "unexpected")
        }
        let runner = CLIRunner(context: context(), administratorEnabled: { true }, administratorExecutor: execute)
        let extra = await runner.run(binary: "defenseclaw-gateway", arguments: ["start", "--anything"])
        expect(extra.exitCode == 64, "extra arguments rejected without fallback")
        let redirected = await runner.run(binary: "defenseclaw-gateway", arguments: ["start"], environment: ["DEFENSECLAW_HOME": "/tmp/other"])
        expect(redirected.exitCode == 64, "environment overrides rejected")
        let stdin = await runner.run(binary: "defenseclaw-gateway", arguments: ["start"], standardInput: "not a password transport")
        expect(stdin.exitCode == 64, "stdin does not become privileged transport")
        let readOnly = CLIRunner(context: context().reducingToInvalidReadOnly("managed fixture"), administratorEnabled: { true }, administratorExecutor: execute)
        let denied = await readOnly.run(binary: "defenseclaw-gateway", arguments: ["restart"], mutation: false)
        expect(denied.exitCode == 77, "read-only policy cannot be bypassed by mutation flag")
        let id = UUID()
        expect(awaitValue(await runner.reserve(runID: id)), "run reserved")
        _ = await runner.cancel(runID: id)
        let cancelled = await runner.run(binary: "defenseclaw-gateway", arguments: ["start"], runID: id)
        expect(cancelled.cancelled, "prelaunch cancellation preserved")
        let count = await probe.count()
        expect(count == 0, "no rejected request reaches authorization")
    }

    private static func testTaskCancellationAfterReservationRefusesDispatch() async {
        let probe = InvocationProbe()
        let runner = CLIRunner(context: context(), administratorEnabled: { true }, administratorExecutor: { action, context, _ in
            await probe.record(action, context)
            return CLIResult(exitCode: 0, output: "started via helper")
        })
        let id = UUID()
        let task = Task {
            let reserved = await runner.reserve(runID: id)
            expect(reserved, "Activity reservation succeeds before task cancellation")
            // Match cancellation after Activity reserves its row but before
            // the runner enters its dispatch actor; do not use runner.cancel.
            withUnsafeCurrentTask { $0?.cancel() }
            return await runner.run(binary: "defenseclaw-gateway", arguments: ["start"], runID: id)
        }
        let result = await task.value
        expect(result.exitCode == 130 && result.cancelled && !result.succeeded,
               "cancelled caller gets the normal cancellation result before authorization")
        let calls = await probe.count()
        expect(calls == 0, "cancelled caller never invokes the administrator executor")
        let disposition = await runner.cancel(runID: id)
        expect(disposition == .notFound, "cancelled dispatch consumes its reservation without leaving a pending operation")

        let reservedAgain = await runner.reserve(runID: id)
        expect(reservedAgain, "cancelled reservation can be reused by a later independent operation")
        let later = await runner.run(binary: "defenseclaw-gateway", arguments: ["start"], runID: id)
        let laterCalls = await probe.count()
        expect(later.succeeded && !later.cancelled && laterCalls == 1,
               "fresh uncancelled operation is not blocked or cancelled by stale run state")
    }

    private static func awaitValue(_ value: Bool) -> Bool { value }

    private static func waitForCall(_ probe: InvocationProbe) async {
        for _ in 0..<100 {
            if await probe.count() > 0 { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        expect(false, "fake authorization started")
    }

    private static func testRebindCancelsPendingAuthorization() async {
        let probe = InvocationProbe()
        let runner = CLIRunner(context: context(), administratorEnabled: { true }, administratorExecutor: { action, context, operation in
            await probe.record(action, context)
            while !(await probe.isReleased()) { try? await Task.sleep(for: .milliseconds(10)) }
            return CLIResult(exitCode: operation.beginDispatch() ? 0 : 130, output: "authorization completed", cancelled: operation.isCancelled)
        })
        let task = Task { await runner.run(binary: "defenseclaw-gateway", arguments: ["start"]) }
        await waitForCall(probe)
        await runner.rebind(to: context("-other"))
        await probe.release()
        let result = await task.value
        expect(result.cancelled && !result.succeeded, "installation switch cancels a pending root launch")
    }

    private static func testCancellationAfterDispatchWaitsForResult() async {
        let probe = InvocationProbe()
        let runner = CLIRunner(context: context(), administratorEnabled: { true }, administratorExecutor: { action, context, operation in
            expect(operation.beginDispatch(), "dispatch succeeds")
            await probe.record(action, context)
            while !(await probe.isReleased()) { try? await Task.sleep(for: .milliseconds(10)) }
            return CLIResult(exitCode: 0, output: "gateway stopped")
        })
        let id = UUID()
        let task = Task { await runner.run(binary: "defenseclaw-gateway", arguments: ["stop"], runID: id) }
        await waitForCall(probe)
        let disposition = await runner.cancel(runID: id)
        expect(disposition == .finishing, "cancel cannot imply root operation undone")
        await probe.release()
        let result = await task.value
        expect(result.succeeded && !result.cancelled, "actual helper completion reported")
    }
}
