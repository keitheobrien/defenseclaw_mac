import SwiftUI

struct FirstRunView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var cliFound = false
    @State private var checked = false
    @State private var connector = "codex"
    @State private var profile = "observe"
    @State private var scannerMode = "local"
    @State private var llmJudge = false
    @State private var failMode = "open"
    @State private var humanApproval = false
    @State private var hiltSeverity = "HIGH"
    @State private var startGateway = false
    @State private var verify = true
    @State private var runID: UUID?
    @State private var exitCode: Int32?

    private static let connectors = [
        "codex", "claudecode", "zeptoclaw", "openclaw", "hermes", "cursor",
        "windsurf", "geminicli", "copilot", "openhands", "antigravity", "opencode",
    ]
    private static let installerURL = URL(
        string: "https://raw.githubusercontent.com/cisco-ai-defense/defenseclaw/main/scripts/install.sh"
    )!
    private static let downloadCommand = "curl -fL --proto '=https' --tlsv1.2 --output ~/Downloads/defenseclaw-install.sh \(installerURL.absoluteString)"
    private static let runCommand = "bash ~/Downloads/defenseclaw-install.sh"

    private var runningEntry: CommandActivityEntry? {
        guard let runID else { return nil }
        return appState.activity.entries.first { $0.id == runID }
    }

    private var isRunning: Bool { runningEntry?.status == .running }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 38))
                    .foregroundStyle(Cisco.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set Up DefenseClaw").font(.title2.weight(.semibold))
                    Text(cliFound
                         ? "Choose the operating defaults for this Mac. DefenseClaw will initialize, optionally start the gateway, and verify the result."
                         : "Install the DefenseClaw runtime first, then return here to configure it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                checkRow("Runtime", ok: cliFound)
                checkRow("Configuration", ok: appState.installDetected)
                checkRow("Gateway", ok: appState.gatewayReachable)
            }

            if cliFound { setupForm } else { installer }

            if let entry = runningEntry {
                execution(entry)
            }

            HStack {
                Button("Check Again") { checkInstallation() }
                Button("Continue Without Setup") {
                    appState.installDetected = true
                    dismiss()
                }
                Spacer()
                if isRunning {
                    Button(role: .destructive) {
                        if let runID { appState.activity.cancel(runID) }
                    } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                } else if cliFound {
                    Button {
                        initialize()
                    } label: {
                        Label(exitCode == 0 ? "Run Setup Again" : "Initialize DefenseClaw", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 680, height: cliFound ? 700 : 560)
        .task {
            guard !checked else { return }
            checked = true
            cliFound = await appState.cli.locateBinary() != nil
        }
    }

    private var setupForm: some View {
        Form {
            Section("Agent and Policy") {
                Picker("Connector", selection: $connector) {
                    ForEach(Self.connectors, id: \.self) { Text($0).tag($0) }
                }
                Picker("Profile", selection: $profile) {
                    Text("Observe - detect and log").tag("observe")
                    Text("Action - enforce policy").tag("action")
                }
                Picker("Scanner Mode", selection: $scannerMode) {
                    Text("Local").tag("local")
                    Text("Remote").tag("remote")
                    Text("Both").tag("both")
                }
                Toggle("Enable LLM judge", isOn: $llmJudge)
            }
            Section("Enforcement") {
                Picker("Hook Failure Mode", selection: $failMode) {
                    Text("Open - allow and log").tag("open")
                    Text("Closed - block").tag("closed")
                }
                if profile == "action" {
                    Toggle("Require human approval", isOn: $humanApproval)
                    if humanApproval {
                        Picker("Approval Minimum Severity", selection: $hiltSeverity) {
                            ForEach(["CRITICAL", "HIGH", "MEDIUM", "LOW"], id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
            }
            Section("Finish") {
                Toggle("Start gateway after setup", isOn: $startGateway)
                Toggle("Verify readiness", isOn: $verify)
            }
        }
        .formStyle(.grouped)
    }

    private var installer: some View {
        GroupBox("Install the DefenseClaw Runtime") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Download the installer, review its contents, then run it from Terminal. The Mac app does not execute a remote script automatically.")
                    .font(.callout).foregroundStyle(.secondary)
                Link(destination: Self.installerURL) {
                    Label("Review Install Script", systemImage: "safari")
                }
                installCommandRow("1. Download", command: Self.downloadCommand)
                installCommandRow("2. Run After Review", command: Self.runCommand)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func execution(_ entry: CommandActivityEntry) -> some View {
        GroupBox("Setup Output") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if entry.status == .running { ProgressView().controlSize(.small) }
                    Image(systemName: statusIcon(entry.status))
                        .foregroundStyle(entry.status == .failed ? Cisco.red : (entry.status == .succeeded ? Cisco.green : .secondary))
                    Text(entry.statusLabel).font(.callout.weight(.semibold))
                    Spacer()
                    Button {
                        appState.selectedPanel = .activity
                        dismiss()
                    } label: { Label("Open Activity", systemImage: "arrow.up.right.square") }
                    .controlSize(.small)
                }
                ScrollView {
                    Text(entry.output.isEmpty ? "Waiting for output..." : entry.output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 110)
            }
        }
    }

    private func initialize() {
        let id = UUID()
        runID = id
        exitCode = nil
        Task {
            var arguments = [
                "init", "--non-interactive", "--yes", "--json-summary",
                "--connector", connector,
                "--profile", profile,
                "--scanner-mode", scannerMode,
                llmJudge ? "--with-judge" : "--no-judge",
                "--fail-mode", failMode,
            ]
            if profile == "action" {
                arguments.append(humanApproval ? "--human-approval" : "--no-human-approval")
                if humanApproval { arguments += ["--hilt-min-severity", hiltSeverity] }
            }
            arguments.append(startGateway ? "--start-gateway" : "--no-start-gateway")
            arguments.append(verify ? "--verify" : "--no-verify")

            let result = await appState.runCommand(
                runID: id,
                title: "Initialize DefenseClaw",
                arguments: arguments,
                category: "setup",
                origin: "First Run",
                successEffects: ["Configuration initialized"] + (startGateway ? ["Gateway started"] : []),
                suggestedNextAction: "Review system health on Overview.",
                refreshOnSuccess: true
            )
            exitCode = result.exitCode
            if result.succeeded {
                let config = await appState.configStore.reload()
                appState.config = config
                appState.installDetected = await appState.configStore.installPresent
                await appState.gateway.update(config: config)
                await appState.pulse()
                if appState.installDetected { dismiss() }
            }
        }
    }

    private func checkInstallation() {
        appState.reloadConfig()
        Task {
            cliFound = await appState.cli.locateBinary() != nil
            appState.installDetected = await appState.configStore.installPresent
        }
    }

    private func checkRow(_ label: String, ok: Bool) -> some View {
        Label(label, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle")
            .font(.caption)
            .foregroundStyle(ok ? Cisco.green : .secondary)
    }

    private func installCommandRow(_ label: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Text(command).font(.caption.monospaced()).lineLimit(2).textSelection(.enabled)
                Spacer(minLength: 8)
                Button { copyToPasteboard(command) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy Command")
            }
        }
    }

    private func statusIcon(_ status: CommandActivityStatus) -> String {
        switch status {
        case .running: "hourglass"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle.fill"
        }
    }
}
