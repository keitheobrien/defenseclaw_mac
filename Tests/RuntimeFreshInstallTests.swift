// Opt-in host for the real installer. All canonical paths must resolve inside
// the disposable HOME supplied by the runner before AppState is constructed.
import AppKit
import Foundation

@main
struct RuntimeFreshInstallTests {
    @MainActor static func main() {
        CLIProcessGroupLauncher.execIfRequested()
        let expected = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DC_TEST_HOME"]!).resolvingSymlinksInPath()
        let temporaryRoot = URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath().path
        precondition(expected.path.hasPrefix(temporaryRoot + "/defenseclawmac-fresh-"))
        print("Isolated home:", FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path, "expected:", expected.path)
        fflush(stdout)
        precondition(FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path == expected.path)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let state = AppState()
        precondition(state.installationContext.homeRoot.deletingLastPathComponent().resolvingSymlinksInPath().path == expected.path)
        precondition(state.installationContext.venvURL.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath().path == expected.path)
        Task { @MainActor in
            await state.installBundledRuntime()
            guard case .succeeded = state.runtimeInstallState else {
                print("FAIL fresh install: \(state.runtimeInstallState)")
                for entry in state.activity.entries { print(entry.title, entry.output) }
                fflush(stdout)
                exit(1)
            }
            let version = RuntimePayload.bundled!.version
            let bin = expected.appendingPathComponent(".local/bin")
            for name in ["defenseclaw", "defenseclaw-gateway", "defenseclaw-acp"] {
                let result = await state.cli.run(binary: bin.appendingPathComponent(name).path, arguments: ["--version"], mutation: false)
                precondition(result.succeeded && UpdateChecker.parseVersion(result.output) == version, "installed component version")
            }
            let data = state.installationContext.homeRoot
            precondition(FileManager.default.fileExists(atPath: data.appendingPathComponent("installer/install.sh").path))
            precondition((try? String(contentsOf: data.appendingPathComponent("VERSION"), encoding: .utf8)) == version + "\n")
            precondition(!FileManager.default.fileExists(atPath: data.appendingPathComponent(".fresh-install-activation-journal.json").path))
            await state.installBundledRuntime()
            guard case .failed = state.runtimeInstallState else { fatalError("existing runtime must not be overwritten") }
            print("PASS real fresh install: CLI, gateway, ACP, installer, VERSION; repeat refused")
            fflush(stdout)
            app.terminate(nil)
        }
        app.run()
    }
}
