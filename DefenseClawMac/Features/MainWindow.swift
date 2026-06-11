// Main window (spec §5.2): sidebar grouped Monitor / Govern / Discover / Configure.

import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var appState

    private let groups: [(String, [PanelID])] = [
        ("Monitor", [.overview, .alerts, .logs, .audit, .activity]),
        ("Govern", [.skills, .mcps, .plugins, .tools]),
        ("Discover", [.inventory, .aiDiscovery, .registries]),
        ("Configure", [.setup]),
    ]

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            List(selection: $state.selectedPanel) {
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { panel in
                            Label {
                                HStack {
                                    Text(panel.title)
                                    Spacer()
                                    badge(for: panel)
                                }
                            } icon: {
                                Image(systemName: panel.systemImage)
                            }
                            .tag(panel)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .tint(Cisco.blue)
        } detail: {
            panelView
                .navigationTitle(appState.selectedPanel.title)
        }
        .overlay(alignment: .top) {
            if let err = appState.lastGatewayError, case .unauthorized = err {
                tokenBanner
            } else if appState.availableUpdate != nil, !appState.updateBannerDismissed {
                updateBanner
            }
        }
        .sheet(isPresented: .constant(!appState.installDetected)) {
            FirstRunView()
                .environment(appState)
        }
    }

    @ViewBuilder
    private func badge(for panel: PanelID) -> some View {
        switch panel {
        // Badge = critical/high count, matching the TUI's "N critical/high alert(s)".
        case .alerts where appState.unackedAlerts.contains(where: { $0.severity >= .high }):
            Text("\(appState.unackedAlerts.filter { $0.severity >= .high }.count)")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Cisco.red, in: Capsule())
                .foregroundStyle(.white)
        case .overview:
            if case .degraded = appState.menuBarState {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Cisco.orange)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var panelView: some View {
        switch appState.selectedPanel {
        case .overview: OverviewView()
        case .alerts: AlertsView()
        case .logs: LogsView()
        case .audit: AuditView()
        case .activity: ActivityView()
        case .skills: SkillsView()
        case .mcps: MCPsView()
        case .plugins: PluginsView()
        case .tools: ToolsView()
        case .inventory: InventoryView()
        case .aiDiscovery: AIDiscoveryView()
        case .registries: RegistriesView()
        case .setup: SetupView()
        }
    }

    private var updateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text("DefenseClaw for macOS \(appState.availableUpdate?.tag ?? "") is available")
                    .font(.callout.weight(.semibold))
                Text(upgradeStatusText)
                    .font(.caption2)
                    .opacity(0.85)
            }
            switch appState.upgradeState {
            case .downloading, .installing:
                ProgressView().controlSize(.small).padding(.leading, 4)
            default:
                Button("Upgrade & Restart") { appState.performUpgrade() }
                    .controlSize(.small)
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                if let url = appState.availableUpdate.flatMap({ URL(string: $0.htmlURL) }) {
                    Link("Release notes", destination: url)
                        .font(.caption)
                }
                Button { appState.updateBannerDismissed = true } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(Cisco.blue.opacity(0.95), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
        .padding(.top, 6)
    }

    private var upgradeStatusText: String {
        switch appState.upgradeState {
        case .idle, .checking: "Current version: \(UpdateChecker.currentVersion) — ⌘⇧U to upgrade and restart"
        case .downloading: "Downloading release…"
        case .installing: "Installing and restarting…"
        case .failed(let why): "Upgrade failed: \(why)"
        }
    }

    private var tokenBanner: some View {
        HStack {
            Image(systemName: "key.slash")
            Text("Gateway token rejected — config.yaml token may have been rotated.")
                .font(.callout)
            Button("Reload Config") { appState.reloadConfig() }
                .controlSize(.small)
        }
        .padding(10)
        .background(Cisco.orange.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.black)
        .padding(.top, 6)
    }
}
