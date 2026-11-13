// Copyright 2026 Cisco Systems, Inc. and its affiliates
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security
import Darwin

/// The privileged boundary is deliberately limited to gateway lifecycle
/// operations. No executable, arguments, environment or password crosses XPC.
@objc protocol GatewayAdminProtocol {
    func perform(
        action: String,
        homePath: String,
        configPath: String,
        authorization: Data,
        withReply reply: @escaping (Int32, String) -> Void
    )
}

enum GatewayAdminAction: String, Sendable, CaseIterable {
    case start
    case stop
    case restart
}

/// The installer snapshots runtime data, not its environments, old installs,
/// or executables. Ownership recovery covers that data and two fixed legacy
/// connector registration files under the authenticated account's home.
/// All traversal and ownership changes use pinned, no-follow descriptors.
enum RuntimeUpgradeStateAccess {
    private static let machinery: Set<String> = [
        ".venv", ".uv", "previous", "previous.new", ".repair", ".rollback-hold",
        ".rollback-hold.done", ".staging", "installer", "logs", ".install.lock", "backups",
    ]

    struct Failure: LocalizedError {
        let detail: String
        var errorDescription: String? {
            "Runtime upgrade error: cannot back up runtime data: \(detail). Stop the gateway as administrator to repair root-owned runtime state, then retry. No runtime replacement was attempted."
        }
    }

    static func check(home: String, uid: uid_t) -> String? {
        do {
            // Read-only checks may resolve the operator's selected home alias;
            // privileged recovery below still rejects every symlink ancestor.
            _ = try walk(home: URL(fileURLWithPath: home).resolvingSymlinksInPath().path, uid: uid)
            return nil
        } catch { return error.localizedDescription }
    }

    /// Called only after a successful, authorized gateway Stop. The account
    /// comes from XPC credentials. Never relax modes or follow links, and never
    /// take ownership of hard-linked files, other accounts' data or mountpoints.
    static func restoreOwnership(home: String, uid: uid_t, gid: gid_t,
                                 rootOwner: uid_t = 0) throws -> Int {
        try walk(home: home, uid: uid, repair: (rootOwner, gid))
    }

    /// Older administrator gateways also replaced these two user-owned
    /// registration files as root. Never accept a connector path over XPC or
    /// traverse the rest of an agent's configuration directory.
    static func restoreLegacyConnectorOwnership(accountHome: String, uid: uid_t, gid: gid_t,
                                               rootOwner: uid_t = 0) throws -> Int {
        guard GatewayAdminPolicy.isCanonicalAbsolutePath(accountHome), accountHome != "/" else {
            throw Failure(detail: "invalid account directory")
        }
        var home = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard home >= 0 else { throw Failure(detail: "cannot open account directory") }
        defer { close(home) }
        for component in accountHome.split(separator: "/") {
            let next = openat(home, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw Failure(detail: "account directory is unreadable or uses a symlink") }
            close(home)
            home = next
        }
        var homeStatus = stat()
        guard fstat(home, &homeStatus) == 0, homeStatus.st_uid == uid,
              homeStatus.st_mode & 0o022 == 0 else {
            throw Failure(detail: "account directory must be owned by your account and not shared writable")
        }
        var changed = 0
        for relative in [".config/opencode/plugins/defenseclaw.js", ".claude/settings.json"] {
            let components = relative.split(separator: "/").map(String.init)
            var parent = fcntl(home, F_DUPFD_CLOEXEC, 0)
            guard parent >= 0 else { throw Failure(detail: "cannot inspect legacy connector directory") }
            defer { close(parent) }
            var missing = false
            for component in components.dropLast() {
                let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0, errno == ENOENT { missing = true; break }
                guard next >= 0 else { throw Failure(detail: "unsafe connector directory at \(relative.debugDescription)") }
                close(parent)
                parent = next
                var metadata = stat()
                guard fstat(parent, &metadata) == 0, metadata.st_uid == uid,
                      metadata.st_dev == homeStatus.st_dev, metadata.st_mode & 0o022 == 0 else {
                    throw Failure(detail: "unsafe connector directory at \(relative.debugDescription)")
                }
            }
            if missing { continue }
            let name = components[components.count - 1]
            var original = stat()
            if fstatat(parent, name, &original, AT_SYMLINK_NOFOLLOW) != 0 {
                if errno == ENOENT { continue }
                throw Failure(detail: "cannot inspect \(relative.debugDescription)")
            }
            guard original.st_mode & S_IFMT == S_IFREG, original.st_nlink == 1,
                  original.st_dev == homeStatus.st_dev,
                  original.st_uid == uid || original.st_uid == rootOwner else {
                throw Failure(detail: "unsafe connector file at \(relative.debugDescription)")
            }
            if original.st_uid != rootOwner { continue }
            guard original.st_mode & 0o6022 == 0 else {
                throw Failure(detail: "unsafe connector permissions at \(relative.debugDescription)")
            }
            let file = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard file >= 0 else { throw Failure(detail: "cannot open \(relative.debugDescription)") }
            defer { close(file) }
            var pinned = stat()
            guard fstat(file, &pinned) == 0, pinned.st_ino == original.st_ino,
                  pinned.st_dev == original.st_dev, pinned.st_uid == original.st_uid,
                  pinned.st_mode == original.st_mode, pinned.st_nlink == 1,
                  fchown(file, uid, gid) == 0 else {
                throw Failure(detail: "connector file changed or ownership could not be restored at \(relative.debugDescription)")
            }
            changed += 1
        }
        return changed
    }

    private static func walk(home: String, uid: uid_t,
                             repair: (owner: uid_t, gid: gid_t)? = nil) throws -> Int {
        guard GatewayAdminPolicy.isCanonicalAbsolutePath(home), home != "/" else {
            throw Failure(detail: "invalid runtime directory")
        }
        var root = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw Failure(detail: "cannot open runtime directory") }
        defer { close(root) }
        for component in home.split(separator: "/") {
            let next = openat(root, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw Failure(detail: "runtime directory is unreadable or uses a symlink") }
            close(root)
            root = next
        }
        var rootStatus = stat()
        guard fstat(root, &rootStatus) == 0, rootStatus.st_uid == uid,
              rootStatus.st_mode & 0o022 == 0 else {
            throw Failure(detail: "runtime directory must be private and owned by your account")
        }
        var visited = 0
        var changed = 0
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        func visit(_ directory: Int32, relative: String, depth: Int) throws {
            guard depth <= 64 else { throw Failure(detail: "runtime data exceeds the traversal depth limit") }
            let copy = fcntl(directory, F_DUPFD_CLOEXEC, 0)
            guard copy >= 0 else { throw Failure(detail: "cannot inspect runtime directory") }
            guard let stream = fdopendir(copy) else {
                close(copy)
                throw Failure(detail: "cannot list runtime directory")
            }
            defer { closedir(stream) }
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    guard errno == 0 else { throw Failure(detail: "cannot finish listing runtime data") }
                    break
                }
                var bytes = entry.pointee.d_name
                let capacity = MemoryLayout.size(ofValue: bytes)
                let name = withUnsafePointer(to: &bytes) {
                    $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                if depth == 0, machinery.contains(name) || name.hasPrefix(".failed-") { continue }
                visited += 1
                guard visited <= 100_000, ContinuousClock.now < deadline else {
                    throw Failure(detail: "runtime data exceeds the inspection limit after \(visited) entries")
                }
                let path = relative.isEmpty ? name : relative + "/" + name
                var status = stat()
                guard fstatat(directory, name, &status, AT_SYMLINK_NOFOLLOW) == 0 else {
                    throw Failure(detail: "cannot inspect \(path.debugDescription)")
                }
                let kind = status.st_mode & S_IFMT
                if kind == S_IFLNK || kind == S_IFSOCK || kind == S_IFIFO { continue }
                guard kind == S_IFDIR || kind == S_IFREG,
                      status.st_dev == rootStatus.st_dev,
                      status.st_uid == uid || status.st_uid == 0 || status.st_uid == repair?.owner else {
                    throw Failure(detail: "unexpected owner, filesystem or file type at \(path.debugDescription)")
                }
                if kind == S_IFREG {
                    if repair == nil {
                        // Checking access does not read file contents or trigger
                        // content scanners for every quarantined source file.
                        // Directory traversal and every mutation stay pinned
                        // to no-follow descriptors below.
                        guard faccessat(directory, name, R_OK, 0) == 0 else {
                            throw Failure(detail: "permission denied reading \(path.debugDescription)")
                        }
                        continue
                    }
                    // Ownership recovery has no work on account-owned files.
                    // Only a file that will actually be changed needs opening.
                    if status.st_uid != repair?.owner { continue }
                }
                let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (kind == S_IFDIR ? O_DIRECTORY : 0))
                guard descriptor >= 0 else {
                    throw Failure(detail: "permission denied reading \(path.debugDescription)")
                }
                defer { close(descriptor) }
                var pinned = stat()
                guard fstat(descriptor, &pinned) == 0, pinned.st_dev == status.st_dev,
                      pinned.st_ino == status.st_ino, pinned.st_uid == status.st_uid,
                      pinned.st_mode == status.st_mode else {
                    throw Failure(detail: "runtime data changed during inspection")
                }
                if let repair, pinned.st_uid == repair.owner {
                    guard (kind == S_IFDIR || pinned.st_nlink == 1),
                          pinned.st_mode & 0o6022 == 0 else {
                        throw Failure(detail: "unsafe ownership repair at \(path.debugDescription)")
                    }
                    guard fchown(descriptor, uid, repair.gid) == 0 else {
                        throw Failure(detail: "could not restore ownership of \(path.debugDescription)")
                    }
                    changed += 1
                }
                if kind == S_IFDIR { try visit(descriptor, relative: path, depth: depth + 1) }
            }
        }
        try visit(root, relative: "", depth: 0)
        return changed
    }
}

enum GatewayAdminPolicy {
    static let serviceName = "com.keitheobrien.DefenseClawMac.GatewayAdmin"
    static let helperIdentifier = serviceName
    static let appIdentifier = "com.keitheobrien.DefenseClawMac"
    static let teamIdentifier = "9R236BB67S"
    static let authorizationRight = "com.keitheobrien.DefenseClawMac.gateway.manage"
    static let helperRelativePath = "Contents/Library/LaunchServices/DefenseClawGatewayHelper"
    static let maximumOutputBytes = 1_048_576

    /// Explicit per-operation administrator authentication. Both ends verify
    /// this definition so a preexisting same-name `allow` rule is never trusted.
    static let authorizationDefinition: [String: Any] = [
        "class": "user",
        "group": "admin",
        "authenticate-user": true,
        "session-owner": false,
        "shared": false,
        "allow-root": false,
        "timeout": 0,
    ]

    static func authorizationDefinitionIsSafe(_ definition: CFDictionary?) -> Bool {
        guard let values = definition as? [String: Any] else { return false }
        return values["class"] as? String == "user"
            && values["group"] as? String == "admin"
            && values["authenticate-user"] as? Bool == true
            && values["session-owner"] as? Bool == false
            && values["shared"] as? Bool == false
            && values["allow-root"] as? Bool == false
            && (values["timeout"] as? NSNumber)?.doubleValue == 0
    }

    static let appRequirement = requirement(identifier: appIdentifier)
    static let helperRequirement = requirement(identifier: helperIdentifier)
    static let gatewayRequirement = requirement(identifier: "com.cisco.defenseclaw.gateway")

    private static func requirement(identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" "
            + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\" "
            + "and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
            + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    }

    /// Lexical validation only; the helper additionally checks filesystem
    /// ownership, symlinks, and the account database for the authenticated UID.
    static func isCanonicalAbsolutePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count < 4_096, path.hasPrefix("/"),
              !path.utf8.contains(0), !path.contains("\n"), !path.contains("\r") else {
            return false
        }
        return (path as NSString).standardizingPath == path
            && !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }

    static func isStrictDescendant(_ path: String, of directory: String) -> Bool {
        isCanonicalAbsolutePath(path) && isCanonicalAbsolutePath(directory)
            && directory != "/" && path.hasPrefix(directory + "/")
    }
}
