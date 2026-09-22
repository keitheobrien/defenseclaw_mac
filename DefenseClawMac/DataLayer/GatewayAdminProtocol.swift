// Copyright 2026 Cisco Systems, Inc. and its affiliates
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security

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
