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
