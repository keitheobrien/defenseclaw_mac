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
                .preferredColorScheme(.dark)
                .onAppear { appState.start() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            // Standard macOS placement: app menu, right under "About".
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await appState.checkForUpdates(force: true) }
                    // Surface the result where the versions live: Settings ▸ General.
                    if NSApp.responds(to: Selector(("showSettingsWindow:"))) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
            }
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
                    } else if panel == .setup {
                        // ⌘⇧3 would collide with macOS's screenshot hotkey.
                        Button(panel.title) { appState.selectedPanel = panel }
                            .keyboardShortcut("s", modifiers: [.command, .shift])
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
                .preferredColorScheme(.dark)
        } label: {
            MenuBarIcon()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            AppSettingsView()
                .environment(appState)
                .preferredColorScheme(.dark)
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
    private var miniaturizeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The Cisco palette is designed for a dark surface (the adaptive tokens'
        // dark variants), so pin the whole app to dark aqua regardless of the
        // system's light/dark setting. This forces every window, popover, and
        // the Settings panel to dark and resolves all Color.adaptive(...) tokens
        // to their dark values. (The menu-bar status item template still tints
        // itself to the real menu bar, which is what we want.)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Window state restoration replays a stale sidebar selection through the
        // List binding, desyncing highlight from content — start fresh instead.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        applyActivationPolicy()

        // Hide-on-minimize: clicking the yellow button hides the app entirely —
        // no Dock icon, no minimized-window tile — leaving only the menu bar
        // shield running. Reopen via the menu bar's "Open DefenseClaw".
        miniaturizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMiniaturizeNotification, object: nil, queue: .main
        ) { notification in
            guard UserDefaults.standard.object(forKey: "hideOnMinimize") as? Bool ?? true,
                  let window = notification.object as? NSWindow,
                  !(window is NSPanel)
            else { return }
            // Order the miniaturized window out (removes its Dock tile) and
            // drop to a menu-bar-only accessory app. The window stays in its
            // miniaturized state; openMainWindow() deminiaturizes on reopen.
            // (Deminiaturizing here instead races orderOut and re-shows it.)
            window.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// The menu bar is the app's persistent anchor: closing the main window
    /// (red X) NEVER terminates the process — only "Quit" from the menu bar
    /// popover (or ⌘Q, which routes through NSApp.terminate) ends it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Tidy the Dock when the icon is hidden: drop to a pure menu-bar agent
        // so no empty Dock tile lingers. With the Dock icon shown, keep the
        // tile so the window can be reopened by clicking it.
        let showDock = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
        if !showDock {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
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
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        // Window was released — ask SwiftUI to recreate it via the openWindow URL scheme fallback.
        if let window = NSApp.windows.first(where: { $0.canBecomeKey && !($0 is NSPanel) }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }
}

extension Notification.Name {
    static let dcRefreshPanel = Notification.Name("dcRefreshPanel")
}
