// App preferences (spec §10) — distinct from DefenseClaw's own Setup panel.

import SwiftUI
import ServiceManagement

struct AppSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            MonitoringSettings()
                .tabItem { Label("Monitoring", systemImage: "waveform.path.ecg") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            ConnectionSettings()
                .tabItem { Label("Connection", systemImage: "network") }
        }
        .frame(width: 480, height: 320)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var appState
    @AppStorage("showDockIcon") private var showDockIcon = true
    @AppStorage("hideOnClose") private var hideOnClose = true
    @AppStorage("hideOnMinimize") private var hideOnMinimize = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Toggle("Show Dock icon", isOn: $showDockIcon)
                .onChange(of: showDockIcon) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "showDockIconResolved")
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                    if newValue { NSApp.activate(ignoringOtherApps: true) }
                }
            Toggle("Hide app when window closes (keep running in menu bar)", isOn: $hideOnClose)
            Toggle("Hide to menu bar when minimized (removes Dock icon until reopened)", isOn: $hideOnMinimize)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Section("Updates — Mac app (this application)") {
                LabeledContent("Installed", value: UpdateChecker.currentVersion)
                if let update = appState.availableUpdate {
                    LabeledContent("Available", value: update.tag)
                    HStack {
                        Button("Upgrade App & Restart") { appState.performUpgrade() }
                        switch appState.upgradeState {
                        case .downloading: Text("Downloading…").font(.caption).foregroundStyle(.secondary)
                        case .installing: Text("Installing…").font(.caption).foregroundStyle(.secondary)
                        case .failed(let why): Text(why).font(.caption).foregroundStyle(Cisco.red)
                        default: EmptyView()
                        }
                    }
                } else {
                    LabeledContent("Status",
                                   value: appState.lastCheckFailed
                                       ? "Could not check (offline or GitHub rate-limited)"
                                       : "Up to date")
                }
            }

            Section("Updates — DefenseClaw runtime (CLI + gateway)") {
                LabeledContent("Installed", value: appState.installedRuntimeVersion ?? "unknown")
                if let update = appState.availableRuntimeUpdate {
                    LabeledContent("Available", value: update.tag)
                    HStack {
                        Button("Upgrade Runtime") { appState.performRuntimeUpgrade() }
                        switch appState.runtimeUpgradeState {
                        case .installing, .downloading:
                            Text(appState.runtimeUpgradeLogTail.isEmpty ? "Running `defenseclaw upgrade`…" : appState.runtimeUpgradeLogTail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        case .failed(let why):
                            Text(why).font(.caption).foregroundStyle(Cisco.red).lineLimit(2)
                        default: EmptyView()
                        }
                    }
                    Text("Runs `defenseclaw upgrade --yes`: downloads release artifacts, migrates, and restarts the gateway. Configuration is preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Status",
                                   value: appState.lastCheckFailed
                                       ? "Could not check (offline or GitHub rate-limited)"
                                       : "Up to date")
                }
                Button(appState.upgradeState == .checking ? "Checking…" : "Check Both for Updates") {
                    Task { await appState.checkForUpdates(force: true) }
                }
                .disabled(appState.upgradeState == .checking)
            }
            Text("The menu bar shield is always available while DefenseClaw is running.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct MonitoringSettings: View {
    @AppStorage("pulseInterval") private var pulseInterval: Double = 5
    @AppStorage("backgroundInterval") private var backgroundInterval: Double = 60
    @AppStorage("backgroundMonitoring") private var backgroundMonitoring = true

    var body: some View {
        Form {
            LabeledContent("Health pulse") {
                Slider(value: $pulseInterval, in: 2...60, step: 1) {
                    Text("Pulse")
                } minimumValueLabel: { Text("2s") } maximumValueLabel: { Text("60s") }
                .frame(width: 220)
            }
            Text("Currently every \(Int(pulseInterval))s — drives the menu bar icon, health card, and alert detection.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Background refresh") {
                Slider(value: $backgroundInterval, in: 15...300, step: 15) {
                    Text("Background")
                } minimumValueLabel: { Text("15s") } maximumValueLabel: { Text("5m") }
                .frame(width: 220)
            }
            Toggle("Keep monitoring while window is hidden", isOn: $backgroundMonitoring)
        }
        .padding(20)
    }
}

private struct NotificationSettings: View {
    @AppStorage("notifyCritical") private var notifyCritical = true
    @AppStorage("notifyHigh") private var notifyHigh = true
    @AppStorage("notifyGatewayOffline") private var notifyGatewayOffline = true
    @AppStorage("seenAlertHighWater") private var seenAlertHighWater: Double = 0

    var body: some View {
        Form {
            Toggle("Notify on CRITICAL findings", isOn: $notifyCritical)
            Toggle("Notify on HIGH findings", isOn: $notifyHigh)
            Toggle("Notify when gateway goes offline / recovers", isOn: $notifyGatewayOffline)
            Text("Notifications include target and severity only — never prompt or payload contents.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Reset seen-alert history") { seenAlertHighWater = 0 }
        }
        .padding(20)
    }
}

private struct ConnectionSettings: View {
    @Environment(AppState.self) private var appState
    @AppStorage(CLIRunner.pathOverrideKey) private var binaryPath = ""

    var body: some View {
        Form {
            LabeledContent("Gateway", value: "http://\(appState.config.gatewayHost):\(appState.config.gatewayPort)")
            LabeledContent("Config", value: ConfigStore.configURL.path)
            LabeledContent("Audit DB", value: ConfigStore.auditDBURL.path)
            LabeledContent("Token", value: appState.config.gatewayToken == nil ? "not set" : "configured (hidden)")
            TextField("defenseclaw binary path (optional override)", text: $binaryPath)
                .textFieldStyle(.roundedBorder)
            Button("Reload config.yaml now") { appState.reloadConfig() }
        }
        .padding(20)
    }
}
