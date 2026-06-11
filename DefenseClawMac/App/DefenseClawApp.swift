// DefenseClaw for macOS — app entry. Menu-bar-first (spec §5):
// MenuBarExtra always present; main window hides to the menu bar on close;
// Dock icon presence is a runtime setting (NSApp activation policy).

import SwiftUI
import ServiceManagement

@main
struct DefenseClawApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @AppStorage("showDockIcon") private var showDockIcon = true

    var body: some Scene {
        Window("DefenseClaw", id: "main") {
            MainWindow()
                .environment(appState)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear { appState.start() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Panel") {
                    NotificationCenter.default.post(name: .dcRefreshPanel, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Go") {
                ForEach(Array(PanelID.allCases.enumerated()), id: \.element) { index, panel in
                    if index < 9 {
                        Button(panel.title) { appState.selectedPanel = panel }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    } else if index == 9 {
                        Button(panel.title) { appState.selectedPanel = panel }
                            .keyboardShortcut("0", modifiers: .command)
                    } else {
                        Button(panel.title) { appState.selectedPanel = panel }
                            .keyboardShortcut(KeyEquivalent(Character("\(index - 9)")), modifiers: [.command, .shift])
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarPopover()
                .environment(appState)
        } label: {
            MenuBarIcon()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            AppSettingsView()
                .environment(appState)
        }
    }
}

// Custom template shields (Assets.xcassets) — system tints them for the
// menu bar's light/dark/active states.
private struct MenuBarIcon: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.menuBarState {
        case .healthy:
            Image("MenuBarShield")
        case .alerting(let count):
            Image("MenuBarShieldFill")
            Text("\(count)")
        case .degraded:
            Image("MenuBarShieldHalf")
        case .offline:
            Image("MenuBarShieldSlash")
        case .scanning:
            Image("MenuBarShield")
            Image(systemName: "arrow.triangle.2.circlepath")
        case .paused:
            Image("MenuBarShield")
            Image(systemName: "pause.fill")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Window state restoration replays a stale sidebar selection through the
        // List binding, desyncing highlight from content — start fresh instead.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        applyActivationPolicy()
    }

    /// Keep running in the menu bar when the last window closes (spec §5.3).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let hideOnClose = UserDefaults.standard.object(forKey: "hideOnClose") as? Bool ?? true
        if hideOnClose, !UserDefaults.standard.bool(forKey: "showDockIconResolved") {
            // Pure menu bar agent once the window is gone.
            NSApp.setActivationPolicy(.accessory)
        }
        return !hideOnClose
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppDelegate.openMainWindow() }
        return true
    }

    func applyActivationPolicy() {
        let showDock = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        UserDefaults.standard.set(showDock, forKey: "showDockIconResolved")
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
    }

    static func openMainWindow() {
        NSApp.setActivationPolicy(
            (UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true) ? .regular : .accessory
        )
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.identifier?.rawValue.contains("main") == true {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Window was released — ask SwiftUI to recreate it via the openWindow URL scheme fallback.
        if let window = NSApp.windows.first(where: { $0.canBecomeKey && !($0 is NSPanel) }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

extension Notification.Name {
    static let dcRefreshPanel = Notification.Name("dcRefreshPanel")
}
