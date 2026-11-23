// Copyright 2026 Cisco Systems, Inc. and its affiliates
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

/// A native agent proven by its kernel executable path and an installed launcher.
/// Never identify or signal an agent from a process name or command-line substring.
struct RuntimeUpgradeAgent: Equatable, Sendable {
    enum Kind: String, Sendable { case openCode = "OpenCode", amp = "Amp" }
    let kind: Kind
    let pid: pid_t
    let executable: String
}

enum RuntimeUpgradeAgents {
    struct ProcessIdentity: Sendable {
        let pid: pid_t
        let uid: uid_t
        let executable: String
    }

    static let openCodeGuidance = "OpenCode is still running. Its background server keeps the DefenseClaw plugin loaded even after the window closes. Quit OpenCode windows and terminal sessions, then choose Stop OpenCode and Upgrade. This interrupts active OpenCode work."

    static func blocked(_ agents: [RuntimeUpgradeAgent]) -> CLIResult {
        let onlyOpenCode = !agents.isEmpty && agents.allSatisfy { $0.kind == .openCode }
        let guidance = onlyOpenCode ? openCodeGuidance
            : "Quit OpenCode and Amp completely, then retry the runtime upgrade. OpenCode may also need its background server stopped with 'opencode service stop'."
        let names = agents.map { "\($0.kind.rawValue) (PID \($0.pid))" }.joined(separator: ", ")
        return CLIResult(exitCode: 75,
            output: "Runtime upgrade paused before installation: \(guidance)\nStill running: \(names)\n",
            runtimeUpgradeNeedsOpenCodeStop: onlyOpenCode)
    }

    static func installedEntries(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> [String: RuntimeUpgradeAgent.Kind] {
        let directories = ["\(home)/.opencode/bin", "\(home)/.amp/bin", "\(home)/.local/bin",
                           "\(home)/.npm-global/bin", "\(home)/.bun/bin", "/opt/homebrew/bin", "/usr/local/bin"]
            + path.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var entries: [String: RuntimeUpgradeAgent.Kind] = [:]
        for directory in Set(directories) {
            for (name, kind) in [("opencode", RuntimeUpgradeAgent.Kind.openCode), ("amp", .amp)] {
                let launcher = URL(fileURLWithPath: directory).appendingPathComponent(name)
                guard FileManager.default.isExecutableFile(atPath: launcher.path) else { continue }
                guard let canonical = canonicalExecutable(launcher.path) else { continue }
                entries[canonical] = kind
            }
        }
        return entries
    }

    // Foundation can abbreviate /private/var back to /var; libproc reports the
    // kernel path. Use realpath on both sides so the same inode has one spelling.
    private static func canonicalExecutable(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func match(_ processes: [ProcessIdentity], entries: [String: RuntimeUpgradeAgent.Kind], uid: uid_t) -> [RuntimeUpgradeAgent] {
        processes.compactMap { process in
            guard process.uid == uid, process.pid > 0, let kind = entries[process.executable] else { return nil }
            return RuntimeUpgradeAgent(kind: kind, pid: process.pid, executable: process.executable)
        }.sorted { $0.pid < $1.pid }
    }

    static func running(
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
        path: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) throws -> [RuntimeUpgradeAgent] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { throw CocoaError(.fileReadUnknown) }
        // Allow processes created between the size query and the actual listing.
        var pids = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.stride + 1024)
        let capacity = pids.count * MemoryLayout<pid_t>.stride
        let bytes = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_ALL_PIDS), 0, $0.baseAddress, Int32(capacity)) }
        guard bytes > 0, bytes < capacity else { throw CocoaError(.fileReadUnknown) }
        let uid = getuid()
        var processes: [ProcessIdentity] = []
        for pid in pids.prefix(Int(bytes) / MemoryLayout<pid_t>.stride) where pid > 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == uid else { continue }
            var path = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            guard let canonical = canonicalExecutable(String(cString: path)) else { continue }
            processes.append(ProcessIdentity(pid: pid, uid: info.pbi_uid, executable: canonical))
        }
        return match(processes, entries: installedEntries(home: home, path: path), uid: uid)
    }

    static func isV2(_ output: String) -> Bool {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^(?:opencode\s+)?v?2\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func failureSummary(_ output: String) -> String? {
        if output.contains("Runtime upgrade paused before installation:") {
            return output.split(separator: "\n").first { $0.contains("Runtime upgrade paused before installation:") }.map(String.init)
        }
        // The release installer emits ✗, not the dependency resolver's ×.
        // Preserve the installer guard for wrappers this native preflight cannot identify.
        return output.split(separator: "\n").first {
            $0.contains("✗") || $0.contains("×") || $0.localizedCaseInsensitiveContains("error:")
        }.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
