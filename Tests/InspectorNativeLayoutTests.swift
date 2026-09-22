// Opt-in native regression for the macOS split-view constraint-update loop.
// Uses only synthetic events and a separate accessory application; no AppState,
// installed application, gateway, audit database, or user configuration is read.
// The fixture matches Alerts' Table/header/inspector sizing. The fixed branch
// calls the production modifier; the baseline deliberately omits that modifier.
// The shell runner enforces an external watchdog because a layout loop can
// prevent every timer and task on the application's main thread from progressing.

import AppKit
import SwiftUI

private enum Settings {
    static let arguments = CommandLine.arguments
    static func argument(_ name: String, fallback: String) -> String {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return fallback }
        return arguments[index + 1]
    }
    static let variant = argument("--variant", fallback: "fixed")
    static let width = Double(argument("--width", fallback: "980")) ?? 980
    static let duration = 12.0
    static let resizeFrom = 1677.0
    static let contentStable = variant == "fixed"
}

private func log(_ message: String) {
    print("PROBE \(Date().timeIntervalSince1970) \(message)")
    fflush(stdout)
}

@MainActor
final class ProbeController: ObservableObject {
    @Published var panel: String? = "Activity"
    @Published var selection = Set<String>()
    @Published var hydrated = false
    @Published var historyCount = 0
    var started = false
    var completed = false
    var selectionCount = 0
    var hydrationCount = 0
    var closeCount = 0

    func run() {
        guard !started else { return }
        started = true
        log("START variant=\(Settings.variant) width=\(Settings.width)")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            for window in NSApp.windows where window.isVisible && window.canBecomeMain {
                let startWidth = Settings.resizeFrom > 0 ? Settings.resizeFrom : Settings.width
                window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY, width: startWidth, height: 760), display: true)
                log("INITIAL WINDOW frame=\(window.frame) contentMin=\(window.contentMinSize)")
            }
            log("WINDOW COUNT \(NSApp.windows.count)")
            panel = "Logs"
            log("PANEL Logs")
            try? await Task.sleep(for: .milliseconds(250))
            panel = "Alerts"
            log("PANEL Alerts")
            try? await Task.sleep(for: .milliseconds(350))
            if Settings.resizeFrom > 0 {
                selection = ["0"]
                try? await Task.sleep(for: .milliseconds(500))
                selection = []
                try? await Task.sleep(for: .milliseconds(350))
                for window in NSApp.windows where window.isVisible && window.canBecomeMain {
                    window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY, width: Settings.width, height: 760), display: true)
                    log("RESIZED WINDOW frame=\(window.frame) contentMin=\(window.contentMinSize)")
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            for round in 0..<8 {
                selection = [String(round % 4)]
                selectionCount += 1
                log("SELECT \(round % 4)")
                try? await Task.sleep(for: .milliseconds(500))
                if round % 2 == 1 {
                    selection = []
                    closeCount += 1
                    log("CLOSE")
                    try? await Task.sleep(for: .milliseconds(180))
                }
            }
            completed = true
            log("SEQUENCE COMPLETE")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Settings.duration) {
            guard self.completed, self.selectionCount == 8,
                  self.hydrationCount >= 8, self.closeCount == 4 else {
                log("FAIL incomplete sequence selections=\(self.selectionCount) hydrations=\(self.hydrationCount) closes=\(self.closeCount)")
                exit(91)
            }
            let visibleWindows = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
            guard visibleWindows.count == 1,
                  abs(visibleWindows[0].frame.width - Settings.width) < 1 else {
                log("FAIL missing visible window or incorrect final width")
                exit(92)
            }
            for window in visibleWindows {
                log("FINAL WINDOW frame=\(window.frame) contentMin=\(window.contentMinSize)")
            }
            log("PASS survived")
            NSApp.terminate(nil)
        }
    }

    func loadDetail() {
        hydrated = false
        historyCount = 0
        let selected = selection
        guard !selected.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(25))
            guard self.selection == selected else { return }
            hydrationCount += 1
            hydrated = true
            historyCount = 5
            log("HYDRATE \(selected.sorted())")
        }
    }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSSetUncaughtExceptionHandler { exception in
            log("EXCEPTION \(exception.name.rawValue): \(exception.reason ?? "nil")")
            log(exception.callStackSymbols.joined(separator: "\n"))
            exit(90)
        }
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct DefenseClawLayoutProbe: App {
    @NSApplicationDelegateAdaptor(ProbeDelegate.self) var delegate
    @StateObject private var controller = ProbeController()

    var body: some Scene {
        Window("DefenseClawLayoutProbe", id: "main") {
            MainProbeView(controller: controller)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { controller.run() }
        }
        .defaultSize(width: Settings.width, height: 760)
    }
}

private struct MainProbeView: View {
    @ObservedObject var controller: ProbeController
    var body: some View {
        NavigationSplitView {
            List(selection: $controller.panel) {
                Section("Monitor") {
                    ForEach(["Overview", "Alerts", "Logs", "Audit", "Activity"], id: \.self) { panel in
                        Label(panel, systemImage: "shield").tag(panel)
                    }
                }
                Section("Discover") { Text("Inventory"); Text("AI Discovery"); Text("Runtime") }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            panel
        }
    }
    @ViewBuilder private var panel: some View {
        if controller.panel == "Alerts" {
            AlertsProbeView(controller: controller).navigationTitle("Alerts")
        } else {
            ContentUnavailableView("No \((controller.panel ?? "Activity").lowercased())", systemImage: "tray")
                .navigationTitle(controller.panel ?? "Activity")
        }
    }
}

private struct SyntheticAlert: Identifiable {
    let id: String
    let action: String
    let target: String
    let details: String
    static let rows = (0..<30).map { index in
        SyntheticAlert(id: String(index), action: index % 2 == 0 ? "TOOL_POLICY_BLOCK" : "SCAN_FINDING",
            target: "/Users/synthetic/.local/share/agent/workspace/\(String(repeating: "long-path-segment/", count: index % 4 + 1))example.py",
            details: "decision=block connector=synthetic_tool evaluation_id=synthetic-\(index) rule_ids=[test-policy] max_severity=HIGH metadata=\(String(repeating: "synthetic ", count: index % 4 * 8 + 10))")
    }
}

private struct AlertsProbeView: View {
    @ObservedObject var controller: ProbeController
    @State private var search = ""
    @State private var kind = "all"
    private var selected: SyntheticAlert? { SyntheticAlert.rows.first { controller.selection.contains($0.id) } }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ForEach(["CRITICAL", "HIGH", "MEDIUM", "LOW"], id: \.self) { severity in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(severity).font(.caption).foregroundStyle(.secondary)
                            Text("10").font(.system(size: 26, weight: .bold, design: .rounded))
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                         .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                HStack {
                    Text("Severity").font(.caption)
                    ForEach(["All", "CRITICAL", "HIGH", "MEDIUM", "LOW"], id: \.self) { value in
                        Text(value).font(.caption).padding(.horizontal, 6).padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                    Spacer()
                    Picker("Kind", selection: $kind) { Text("All kinds").tag("all") }.frame(width: 150)
                }
            }.padding(12)
            Divider()
            Table(SyntheticAlert.rows, selection: $controller.selection) {
                TableColumn("Time") { _ in Text("11:33:19").font(.caption.monospacedDigit()) }.width(76)
                TableColumn("Severity") { _ in Text("HIGH").font(.caption2) }.width(86)
                TableColumn("Kind") { _ in Text("audit").font(.caption) }.width(86)
                TableColumn("Action") { Text($0.action).font(.caption) }.width(min: 90, ideal: 130)
                TableColumn("Target") { Text($0.target).font(.caption).lineLimit(1) }.width(min: 110, ideal: 180)
                TableColumn("Details") { Text($0.details).font(.caption).lineLimit(2) }
                TableColumn("Run") { _ in Text("synthetic-run-identifier").font(.caption2.monospaced()).lineLimit(1) }.width(80)
            }
        }
        .modifier(ContentFrame())
        .inspector(isPresented: Binding(get: { selected != nil }, set: { if !$0 { controller.selection = [] } })) {
            if let selected {
                inspector(selected).inspectorColumnWidth(
                    min: InspectorLayoutPolicy.minimumWidth,
                    ideal: InspectorLayoutPolicy.idealWidth,
                    max: InspectorLayoutPolicy.maximumWidth
                )
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search action, target, details")
        .toolbar { Button("Acknowledge Selection", systemImage: "checkmark.circle") {} }
        .onChange(of: controller.selection) { _, _ in controller.loadDetail() }
    }
    private func inspector(_ row: SyntheticAlert) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) { inspectorContent(row) }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private func inspectorContent(_ row: SyntheticAlert) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.action).font(.headline)
                HStack { Text("HIGH").font(.caption2); Text("Audit").font(.caption) }
            }
            Spacer()
            Button { controller.selection = [] } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
        }
        KeyValueProbe(pairs: [("Target", row.target), ("Time", "Sep 22, 2026 at 11:33:19 AM"), ("Connector", "synthetic_agent"), ("Run ID", "run-synthetic-0123456789abcdef")])
        Divider()
        Text("Event Details").font(.caption.weight(.semibold))
        KeyValueProbe(pairs: [("Decision", "Block"), ("Evaluation ID", "synthetic-evaluation-0123456789abcdef0123456789abcdef"), ("Rule IDs", "[policy-synthetic-test]"), ("Max Severity", "HIGH")])
        Divider()
        Text("Raw Details").font(.caption.weight(.semibold))
        Text(row.details + (controller.hydrated ? String(repeating: "\nSynthetic hydrated multiline detail with a long token abcdef0123456789abcdef0123456789abcdef0123456789. ", count: 10) : ""))
            .font(.system(.caption, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .textSelection(.enabled)
        if controller.hydrated {
            Divider()
            Text("Findings").font(.caption.weight(.semibold))
            ForEach(0..<10, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("HIGH").font(.caption2); Text("Synthetic policy finding \(index)").font(.callout.weight(.medium)) }
                    Text("Synthetic policy details \(String(repeating: "example ", count: index + 4))").font(.caption)
                    Label(row.target, systemImage: "mappin.and.ellipse").font(.caption2).textSelection(.enabled)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                 .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        if controller.historyCount > 0 {
            Divider()
            Text("History for This Target").font(.caption.weight(.semibold))
            ForEach(0..<controller.historyCount, id: \.self) { _ in
                HStack { Text("Sep22,11:33").font(.caption2); Text("POLICY_BLOCK").font(.caption).lineLimit(1); Spacer(); Text("HIGH").font(.caption2) }
            }
        }
    }
}

private struct KeyValueProbe: View {
    let pairs: [(String, String)]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                GridRow {
                    Text(pair.0).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
                    Text(pair.1).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ContentFrame: ViewModifier {
    func body(content: Content) -> some View {
        if Settings.contentStable {
            content.dcInspectorMainContent()
        } else { content }
    }
}
