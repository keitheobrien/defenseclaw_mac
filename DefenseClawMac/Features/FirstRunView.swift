// First-run / onboarding (spec §9.14): detect the local install, guide if absent.

import SwiftUI

struct FirstRunView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var cliFound = false
    @State private var checked = false

    private static let installerURL = URL(
        string: "https://raw.githubusercontent.com/cisco-ai-defense/defenseclaw/main/scripts/install.sh"
    )!
    private static let downloadCommand = "curl -fL --proto '=https' --tlsv1.2 --output ~/Downloads/defenseclaw-install.sh \(installerURL.absoluteString)"
    private static let runCommand = "bash ~/Downloads/defenseclaw-install.sh"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44))
                .foregroundStyle(Cisco.blue)
            Text("Welcome to DefenseClaw for macOS")
                .font(.title2.weight(.semibold))
            Text("This app is a companion to a local DefenseClaw installation. It could not find one yet.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                checkRow("config.yaml at ~/.defenseclaw", ok: appState.installDetected)
                checkRow("Gateway reachable on port \(appState.config.gatewayPort)", ok: appState.gatewayReachable)
                checkRow("defenseclaw CLI on PATH", ok: cliFound)
            }
            .padding(14)
            .background(Cisco.surfacePanel, in: RoundedRectangle(cornerRadius: 10))

            GroupBox("Install the DefenseClaw Runtime") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Download the installer, review its contents, then run it from Terminal. The app never executes the script for you.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Link(destination: Self.installerURL) {
                        Label("Review Install Script", systemImage: "safari")
                    }
                    installCommandRow("1. Download", command: Self.downloadCommand)
                    installCommandRow("2. Run After Review", command: Self.runCommand)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Check Again") {
                    appState.reloadConfig()
                    Task {
                        cliFound = await appState.cli.locateBinary() != nil
                        appState.installDetected = await appState.configStore.installPresent
                    }
                }
                Button("Continue Anyway") {
                    appState.installDetected = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .task {
            guard !checked else { return }
            checked = true
            cliFound = await appState.cli.locateBinary() != nil
        }
    }

    private func checkRow(_ label: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Cisco.green : Cisco.red)
            Text(label).font(.callout)
            Spacer()
        }
    }

    private func installCommandRow(_ label: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    copyToPasteboard(command)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy Command")
            }
        }
    }
}
