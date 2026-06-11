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
