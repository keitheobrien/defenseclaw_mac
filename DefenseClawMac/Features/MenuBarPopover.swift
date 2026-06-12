// Menu bar popover (spec §5.1): health header, per-connector lines,
// 24h enforcement micro-bars, recent unacked alerts, footer actions.

import SwiftUI
import Charts

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var counts: (allowed: Int, blocked: Int, scanned: Int) = (0, 0, 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            connectorLines
            enforcementBars
            Divider()
            recentAlerts
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 360)
        .task {
            counts = await appState.audit.enforcementCounts24h()
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(Cisco.blue)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("DefenseClaw").font(.headline)
                Text(appState.gatewayReachable
                     ? "Gateway up · \(uptimeText) · \(appState.health.connectors.count) connector(s)"
                     : "Gateway offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatePill(raw: appState.gatewayReachable ? appState.health.state : "offline")
        }
    }

    private var uptimeText: String {
        let secs = appState.health.uptimeMs / 1000
        if secs > 86400 { return "\(secs / 86400)d up" }
        if secs > 3600 { return "\(secs / 3600)h up" }
        return "\(max(secs, 0) / 60)m up"
    }

    @ViewBuilder
    private var connectorLines: some View {
        ForEach(appState.health.connectors) { c in
            HStack(spacing: 6) {
                Circle().fill(Cisco.stateColor(raw: c.state)).frame(width: 6, height: 6)
                Text(c.name).font(.caption.weight(.medium))
                Text(c.mode).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(c.calls) calls · \(c.blocks) blocks")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var enforcementBars: some View {
        Chart {
            BarMark(x: .value("Count", counts.allowed), y: .value("Kind", "Allowed"))
                .foregroundStyle(Cisco.green)
            BarMark(x: .value("Count", counts.blocked), y: .value("Kind", "Blocked"))
                .foregroundStyle(Cisco.red)
            BarMark(x: .value("Count", counts.scanned), y: .value("Kind", "Scanned"))
                .foregroundStyle(Cisco.blue)
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in AxisValueLabel().font(.caption2) }
        }
        .frame(height: 64)
    }

    @ViewBuilder
    private var recentAlerts: some View {
        let top = Array(appState.unackedAlerts.prefix(5))
        if top.isEmpty {
            Text("No unacknowledged alerts")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(top) { row in
                Button {
                    appState.selectedPanel = .alerts
                    AppDelegate.openMainWindow()
                    openWindow(id: "main")
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Cisco.severityColor(row.severity)).frame(width: 7, height: 7)
                        Text(row.target.isEmpty ? row.action : row.target)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(DCDates.relative(row.timestamp))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = appState.ackError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(Cisco.red)
            }
            footerButtons
        }
    }

    private var footerButtons: some View {
        HStack {
            Button("Open DefenseClaw") {
                AppDelegate.openMainWindow()
                openWindow(id: "main")
            }
            .controlSize(.small)
            Button("Ack All") {
                Task { await appState.acknowledge(appState.unackedAlerts) }
            }
            .controlSize(.small)
            .disabled(appState.unackedAlerts.isEmpty)
            Button(appState.monitoringPaused ? "Resume" : "Pause") {
                appState.monitoringPaused.toggle()
            }
            .controlSize(.small)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
    }
}
