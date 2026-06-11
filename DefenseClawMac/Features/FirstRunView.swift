// First-run / onboarding (spec §9.14): detect the local install, guide if absent.

import SwiftUI

struct FirstRunView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var cliFound = false
    @State private var checked = false

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

            VStack(alignment: .leading, spacing: 6) {
                Text("Install DefenseClaw with:").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("curl -LsSf https://raw.githubusercontent.com/cisco-ai-defense/defenseclaw/main/scripts/install.sh | bash")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button {
                        copyToPasteboard("curl -LsSf https://raw.githubusercontent.com/cisco-ai-defense/defenseclaw/main/scripts/install.sh | bash")
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                }
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
}
