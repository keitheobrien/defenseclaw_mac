// Self-update against GitHub Releases (keitheobrien/defenseclaw_mac).
//
// Check: unauthenticated GitHub API first (works if the repo is public),
// falling back to the user's authenticated `gh` CLI (required while the
// repo is private). Install: download the release zip, unpack with ditto,
// swap the running .app bundle in place, strip quarantine, and relaunch.

import AppKit
import Foundation

struct ReleaseInfo: Sendable, Equatable {
    var tag: String          // e.g. "v0.3.1"
    var version: String      // e.g. "0.3.1"
    var assetName: String
    var assetURL: String     // browser_download_url (usable only when repo is public)
    var htmlURL: String
    var notes: String
}

enum UpgradeState: Equatable {
    case idle
    case checking
    case downloading
    case installing
    case failed(String)
}

actor UpdateChecker {
    static let repo = "keitheobrien/defenseclaw_mac"

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Numeric dotted-version comparison: true when `candidate` > `current`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Check

    /// Returns the latest release, or nil when it can't be determined.
    func latestRelease() async -> ReleaseInfo? {
        if let release = await latestViaAPI() { return release }
        return await latestViaGH()
    }

    private func parseRelease(_ dict: [String: Any]) -> ReleaseInfo? {
        guard let tag = dict["tag_name"] as? String else { return nil }
        let assets = (dict["assets"] as? [[String: Any]]) ?? []
        let zip = assets.first { (($0["name"] as? String) ?? "").hasSuffix(".zip") }
        return ReleaseInfo(
            tag: tag,
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            assetName: (zip?["name"] as? String) ?? "",
            assetURL: (zip?["browser_download_url"] as? String) ?? "",
            htmlURL: (dict["html_url"] as? String) ?? "https://github.com/\(Self.repo)/releases",
            notes: (dict["body"] as? String) ?? ""
        )
    }

    private func latestViaAPI() async -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parseRelease(dict)
    }

    private func latestViaGH() async -> ReleaseInfo? {
        guard let gh = Self.locateGH() else { return nil }
        let result = Self.runProcess(gh, ["api", "repos/\(Self.repo)/releases/latest"])
        guard result.exitCode == 0,
              let data = result.output.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return parseRelease(dict)
    }

    // MARK: - Download + install + restart

    /// Downloads the release zip, swaps the current bundle, and relaunches.
    /// Returns an error message, or never (the app restarts) on success.
    func downloadAndInstall(_ release: ReleaseInfo, progress: @Sendable @escaping (UpgradeState) -> Void) async -> String? {
        progress(.downloading)
        let stage = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-update-\(release.version)")
        try? FileManager.default.removeItem(at: stage)
        try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let zipPath = stage.appendingPathComponent(release.assetName.isEmpty ? "update.zip" : release.assetName)

        // Public path: direct asset download. Private repo: gh release download.
        var downloaded = false
        if !release.assetURL.isEmpty, let url = URL(string: release.assetURL) {
            if let (tmp, response) = try? await URLSession.shared.download(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                try? FileManager.default.removeItem(at: zipPath)
                downloaded = (try? FileManager.default.moveItem(at: tmp, to: zipPath)) != nil
            }
        }
        if !downloaded {
            guard let gh = Self.locateGH() else {
                return "Could not download the release: direct download failed and the gh CLI was not found."
            }
            let result = Self.runProcess(gh, ["release", "download", release.tag,
                                              "--repo", Self.repo, "--pattern", "*.zip",
                                              "--dir", stage.path, "--clobber"])
            guard result.exitCode == 0 else {
                return "gh release download failed (exit \(result.exitCode)): \(String(result.output.suffix(200)))"
            }
            // gh names the file after the asset; find it.
            guard let zip = (try? FileManager.default.contentsOfDirectory(atPath: stage.path))?
                .first(where: { $0.hasSuffix(".zip") })
            else { return "Downloaded release contained no zip asset." }
            if zip != zipPath.lastPathComponent {
                try? FileManager.default.moveItem(at: stage.appendingPathComponent(zip), to: zipPath)
            }
        }

        progress(.installing)
        // Unpack with ditto (preserves bundle structure + signature).
        let unpackDir = stage.appendingPathComponent("unpacked")
        try? FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        let unzip = Self.runProcess("/usr/bin/ditto", ["-xk", zipPath.path, unpackDir.path])
        guard unzip.exitCode == 0 else { return "Unpack failed: \(unzip.output)" }
        guard let appName = (try? FileManager.default.contentsOfDirectory(atPath: unpackDir.path))?
            .first(where: { $0.hasSuffix(".app") })
        else { return "No .app bundle inside the release zip." }
        let newApp = unpackDir.appendingPathComponent(appName)

        // Swap the running bundle: move the old aside (the running process keeps
        // executing from the moved inode), copy the new one into place.
        let targetPath = Bundle.main.bundlePath
        let backup = stage.appendingPathComponent("previous.app")
        do {
            try FileManager.default.moveItem(atPath: targetPath, toPath: backup.path)
        } catch {
            return "Could not replace \(targetPath): \(error.localizedDescription)"
        }
        let copy = Self.runProcess("/usr/bin/ditto", [newApp.path, targetPath])
        guard copy.exitCode == 0 else {
            // Roll back.
            try? FileManager.default.moveItem(atPath: backup.path, toPath: targetPath)
            return "Install failed: \(copy.output)"
        }
        _ = Self.runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", targetPath])

        // Relaunch: detached child outlives this process.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"\(targetPath)\""]
        try? relaunch.run()

        await MainActor.run { NSApp.terminate(nil) }
        return nil // unreachable in practice
    }

    // MARK: - Process helpers

    nonisolated static func locateGH() -> String? {
        for candidate in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        let probe = runProcess("/usr/bin/env", ["zsh", "-lc", "command -v gh"])
        let path = probe.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return probe.exitCode == 0 && !path.isEmpty ? path : nil
    }

    nonisolated static func runProcess(_ launchPath: String, _ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            return (126, "failed to launch \(launchPath): \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
