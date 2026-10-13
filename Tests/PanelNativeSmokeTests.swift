// Disposable native host for the production views. The runner supplies only a
// synthetic installation and replaces @main in a temporary source copy.
import AppKit
import SwiftUI

@main
struct PanelNativeSmokeTests {
    @MainActor static func main() {
        CLIProcessGroupLauncher.execIfRequested()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.environment["PARITY_UPGRADE_ONLY"] == "1" {
            precondition(FileManager.default.homeDirectoryForCurrentUser.path == ProcessInfo.processInfo.environment["HOME"], "upgrade test must use only the disposable home")
        }
        let state = AppState()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1180, height: 800),
                              styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PARITY_SCREENSHOTS"]!)
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        func tables(_ view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables)
        }
        func accessibilityNodes(_ root: NSObject) -> [NSObject] {
            var seen = Set<ObjectIdentifier>()
            func visit(_ node: NSObject, depth: Int) -> [NSObject] {
                guard depth < 20, seen.count < 5000, seen.insert(ObjectIdentifier(node)).inserted else { return [] }
                let children = node.accessibilityAttributeValue(.children) as? [NSObject] ?? []
                return [node] + children.flatMap { visit($0, depth: depth + 1) }
            }
            return visit(root, depth: 0)
        }
        func capture(_ name: String, _ host: NSView) {
            let destination = output.appendingPathComponent(name + ".png")
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), destination.path]
            do {
                try shot.run()
                shot.waitUntilExit()
                if shot.terminationStatus == 0 { return }
            } catch { }
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!.write(to: destination)
            print("NOTE bitmap fallback for \(name): window capture unavailable")
        }
        func show(_ name: String, _ view: AnyView) async {
            let host = NSHostingView(rootView: view.environment(state))
            window.contentView = host
            window.title = "Parity fixture: " + name
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(2))
            capture(name, host)
            let nativeTables = tables(host)
            if name == "palette" {
                let commands = CommandRegistry.paletteCommands(supportedSetupCommands: state.runtimeSetupCommands,
                                                               supportedRuntimeCommands: state.runtimeDiscoveryCommands)
                let index = commands.firstIndex { $0.arguments == ["version"] }!
                let table = nativeTables.first!
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                try? await Task.sleep(for: .milliseconds(500))
                let button = accessibilityNodes(host).first {
                    ($0.accessibilityAttributeValue(.role) as? String) == "AXButton"
                        && ($0.accessibilityAttributeValue(.title) as? String) == "Run"
                }
                if let button {
                    let count = state.activity.entries.count
                    button.accessibilityPerformAction(.press)
                    try? await Task.sleep(for: .seconds(2))
                    precondition(state.activity.entries.count > count, "palette version action must reach Activity")
                    capture("palette-version", host)
                    print("PASS palette version button executed and recorded in Activity")
                } else {
                    print("NOT TESTED palette Run button: native accessibility button was unavailable")
                }
            }
            for table in nativeTables where table.numberOfRows > 0 {
                window.makeFirstResponder(table)
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                try? await Task.sleep(for: .milliseconds(350))
                window.setContentSize(NSSize(width: 980, height: 760))
                try? await Task.sleep(for: .milliseconds(350))
                capture(name + "-detail", host)
                table.deselectAll(nil)
            }
            window.setContentSize(NSSize(width: 1180, height: 800))
            print("PASS render \(name); tables=\(nativeTables.count); rows=\(nativeTables.map(\.numberOfRows))")
            fflush(stdout)
        }
        Task { @MainActor in
            await state.pulse()
            await state.pulse()
            let version = await state.runCommand(title: "Fixture version check", arguments: ["--version"],
                                                 mutation: false, category: "diagnostics", origin: "Parity fixture")
            precondition(version.succeeded && version.output.contains("1.0.0"))
            precondition(!state.activity.entries.isEmpty, "CLI command must be recorded in Activity")
            if ProcessInfo.processInfo.environment["PARITY_UPGRADE_ONLY"] == "1" {
                let fixture = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DEFENSECLAW_HOME"]!)
                let versionFile = fixture.appendingPathComponent("runtime-version")
                let sourceMarker = fixture.appendingPathComponent(".local/bin/.defenseclaw-source-root")
                try! FileManager.default.createDirectory(at: sourceMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
                for scenario in ["success", "failure", "cancelled", "unverified", "equal", "newer", "source"] {
                    try! Data((scenario == "equal" ? "1.0.1" : scenario == "newer" ? "1.0.2" : "1.0.0").utf8).write(to: versionFile)
                    if scenario == "failure" { try! Data().write(to: fixture.appendingPathComponent("fail-upgrade")) }
                    if scenario == "unverified" { try! Data().write(to: fixture.appendingPathComponent("unchanged-upgrade")) }
                    if scenario == "source" { try! Data("fixture source".utf8).write(to: sourceMarker) }
                    state.runtimeUpgradeState = .idle
                    await state.refreshInstalledRuntimeVersion()
                    state.availableRuntimeUpdate = ReleaseInfo(tag: "1.0.1", version: "1.0.1", assetName: "", assetURL: "", assetSHA256: "", htmlURL: "https://example.invalid/release", notes: "Fixture")
                    state.publishedRuntimeVersion = "1.0.1"
                    state.runtimeReleaseChecked = true
                    state.selectedSettingsTab = .general
                    if scenario == "success" { await show("runtime-upgrade-ready", AnyView(AppSettingsView())) }
                    let priorIDs = Set(state.activity.entries.map(\.id))
                    state.performRuntimeUpgrade()
                    var streamed = false
                    for _ in 0..<200 {
                        try? await Task.sleep(for: .milliseconds(100))
                        if state.runtimeUpgradeOutput.contains("Fixture runtime upgrade in progress"),
                           let currentID = state.runtimeUpgradeRunID,
                           state.activity.entries.contains(where: { $0.id == currentID && $0.status.isActive }) {
                            if !streamed && scenario == "success", let host = window.contentView { capture("runtime-upgrade-progress", host) }
                            await state.refreshInstalledRuntimeVersion()
                            precondition(state.installedRuntimeVersion == "1.0.0", "background checks must not clear the installed version mid-upgrade")
                            let auditAvailable = await state.audit.isAvailable
                            precondition(!auditAvailable, "audit reader must be suspended during replacement")
                            if !streamed, scenario == "cancelled", let runID = state.runtimeUpgradeRunID {
                                state.activity.cancel(runID)
                            }
                            streamed = true
                            // A second click and unrelated mutations must not overlap.
                            state.performRuntimeUpgrade()
                            let blocked = await state.runCommand(title: "Blocked during upgrade", arguments: ["fixture-mutation"], origin: "Fixture")
                            precondition(blocked.exitCode == 75)
                        }
                        if state.runtimeUpgradeRunID == nil { break }
                    }
                    precondition(state.runtimeUpgradeRunID == nil, "upgrade must finish")
                    let calls = state.activity.entries.filter { !priorIDs.contains($0.id) && $0.category == "upgrade" }
                    let skipped = ["equal", "newer", "source"].contains(scenario)
                    precondition(calls.count == (skipped ? 0 : 1), "exactly one upgrade or no mutation for preserved runtimes")
                    if !skipped { precondition(streamed, "upgrade progress must be live: \(state.runtimeUpgradeOutput)") }
                    if ["failure", "cancelled", "unverified"].contains(scenario) {
                        guard case .failed = state.runtimeUpgradeState else { fatalError("upgrade failure must be reported") }
                    } else {
                        precondition(state.runtimeUpgradeState == .idle)
                    }
                    if scenario == "success" {
                        precondition(state.installedRuntimeVersion == "1.0.1" && state.availableRuntimeUpdate == nil)
                        await show("runtime-upgrade-complete", AnyView(AppSettingsView()))
                    }
                    let resumed = await state.cli.run(arguments: ["--version"], mutation: false)
                    precondition(resumed.succeeded, "runner lock must be released on every outcome")
                    let auditResumed = await state.audit.isAvailable
                    precondition(auditResumed, "audit reader must resume on every outcome")
                    for marker in [fixture.appendingPathComponent("fail-upgrade"), fixture.appendingPathComponent("unchanged-upgrade"), sourceMarker] {
                        try? FileManager.default.removeItem(at: marker)
                    }
                    print("PASS automatic runtime upgrade: \(scenario)")
                }
                print("PASS all native panel/form renders completed")
                fflush(stdout)
                app.terminate(nil)
                return
            }
            if ProcessInfo.processInfo.environment["PARITY_SANDBOX_ONLY"] == "1" {
                let fixture = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DEFENSECLAW_HOME"]!)
                let wizard = TUIWizards.all.first { $0.id == "sandbox" }!
                @MainActor func pressDefaultAction() {
                    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil,
                                                characters: "\r", charactersIgnoringModifiers: "\r",
                                                isARepeat: false, keyCode: 36)!
                    precondition(window.performKeyEquivalent(with: event), "wizard default action must be reachable")
                }
                for failingStage in ["", "setup", "image", "doctor"] {
                    let marker = fixture.appendingPathComponent("fail-sandbox-" + failingStage)
                    if !failingStage.isEmpty { try! Data().write(to: marker) }
                    let host = NSHostingView(rootView: WizardSheet(wizard: wizard).id(UUID()).environment(state))
                    window.contentView = host
                    window.setContentSize(NSSize(width: 660, height: 660))
                    window.makeKeyAndOrderFront(nil)
                    try? await Task.sleep(for: .seconds(1))
                    if failingStage.isEmpty { capture("sandbox-form", host) }
                    pressDefaultAction()
                    try? await Task.sleep(for: .milliseconds(500))
                    if failingStage.isEmpty { capture("sandbox-review", host) }
                    let previousIDs = Set(state.activity.entries.map(\.id))
                    pressDefaultAction()
                    var streamed = false
                    var completed = false
                    let expectedCount = failingStage == "setup" ? 1 : (failingStage == "image" ? 2 : 3)
                    for _ in 0..<160 {
                        try? await Task.sleep(for: .milliseconds(100))
                        let active = state.activity.entries.filter { !previousIDs.contains($0.id) && $0.category == "setup" }
                        if !streamed, active.contains(where: { $0.status == .running && $0.output.contains("Fixture sandbox setup progress") }) {
                            streamed = true
                            if failingStage.isEmpty { capture("sandbox-progress", host) }
                        }
                        if active.count >= expectedCount && active.allSatisfy({ !$0.status.isActive }) {
                            completed = true
                            try? await Task.sleep(for: .milliseconds(500))
                            break
                        }
                    }
                    precondition(completed && streamed, "wizard must stream output and finish within deadline")
                    let calls = state.activity.entries.filter { !previousIDs.contains($0.id) && $0.category == "setup" }
                        .sorted { $0.startedAt < $1.startedAt }
                    precondition(calls.count == expectedCount, "no follow-up stage may run after failure")
                    precondition(calls.last!.status == (failingStage.isEmpty ? .succeeded : .failed))
                    precondition(calls.first!.command.contains("--install-openshell"))
                    capture("sandbox-" + (failingStage.isEmpty ? "success" : "failed-" + failingStage), host)
                    if !failingStage.isEmpty { try! FileManager.default.removeItem(at: marker) }
                    print("PASS sandbox wizard sequence: \(failingStage.isEmpty ? "success" : failingStage + " failure"), live output, Activity, stop on failure")
                }
                print("PASS all native panel/form renders completed")
                fflush(stdout)
                app.terminate(nil)
                return
            }
            state.installedRuntimeVersion = "1.0.0"
            await state.refreshAlerts()
            let panels: [(PanelID, AnyView)] = [
                (.overview, AnyView(OverviewView())), (.alerts, AnyView(AlertsView())),
                (.logs, AnyView(LogsView())), (.audit, AnyView(AuditView())),
                (.activity, AnyView(ActivityView())), (.skills, AnyView(SkillsView())),
                (.mcps, AnyView(MCPsView())), (.plugins, AnyView(PluginsView())),
                (.tools, AnyView(ToolsView())), (.policies, AnyView(PoliciesView())),
                (.sandboxes, AnyView(SandboxesView())), (.inventory, AnyView(InventoryView())),
                (.aiDiscovery, AnyView(AIDiscoveryView())), (.aiRuntime, AnyView(AIRuntimeView())),
                (.registries, AnyView(RegistriesView())), (.setup, AnyView(SetupView()))
            ]
            for (panel, view) in panels {
                state.selectedPanel = panel
                await show(panel.rawValue, AnyView(NavigationStack { view }))
            }
            let discovery = try! await state.gateway.aiUsage()
            precondition(discovery.modelRows.count == 1, "fixture model must be separate from product rows")
            await show("inventory-ide", AnyView(InventoryView(initialCategory: .idePlugins)))
            await show("inventory-identities", AnyView(InventoryView(initialCategory: .agents)))
            await show("models", AnyView(LocalModelsView(models: discovery.modelRows, search: "")))
            state.selectedPanel = .sandboxes
            await state.refreshSandboxes()
            precondition(!state.sandbox.sandboxes.isEmpty, "fixture must supply a sandbox")
            await state.unblockSandboxDestination(host: "example.invalid", sandbox: "fixture-codex", always: false)
            let fixture = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DEFENSECLAW_HOME"]!)
            try! Data().write(to: fixture.appendingPathComponent("offline"))
            await state.refreshSandboxes()
            precondition(!state.sandbox.error.isEmpty && !state.sandbox.sandboxes.isEmpty,
                         "unavailable gateway must retain rows and disclose stale state")
            precondition(!state.sandboxActionsAvailable, "stale sandbox data must disable decisions even with cached healthy gateway status")
            let activityCount = state.activity.entries.count
            await state.unblockSandboxDestination(host: "example.invalid", sandbox: "fixture-codex", always: false)
            precondition(state.activity.entries.count == activityCount, "stale decision must not execute a command")
            await show("sandboxes-unavailable", AnyView(SandboxesView()))
            try! FileManager.default.removeItem(at: fixture.appendingPathComponent("offline"))
            await state.refreshSandboxes()
            precondition(state.sandbox.error.isEmpty, "sandbox refresh recovers after fixture outage")
            precondition(state.sandboxActionsAvailable, "fresh sandbox data restores decisions")
            for (name, tab) in [("general", AppSettingsTab.general), ("monitoring", .monitoring),
                                ("notifications", .notifications), ("connection", .connection)] {
                state.selectedSettingsTab = tab
                await show("settings-" + name, AnyView(AppSettingsView()))
            }
            for (index, wizard) in TUIWizards.all.enumerated() {
                await show("wizard-\(index)", AnyView(WizardSheet(wizard: wizard)))
            }
            await show("redaction", AnyView(RedactionPolicySheet()))
            await show("palette", AnyView(CommandPaletteView()))
            print("PASS all native panel/form renders completed")
            fflush(stdout)
            app.terminate(nil)
        }
        app.run()
    }
}
