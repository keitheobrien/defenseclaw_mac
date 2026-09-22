// Copyright 2026 Cisco Systems, Inc. and its affiliates
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum GatewayAutoStartPreference {
    static let key = "startGatewayAutomatically"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}

struct GatewayAutoStartSnapshot: Equatable {
    var generation: Int
    var commandGeneration: Int
    var enabled: Bool
    var permitsMutation: Bool
    var configurationReady: Bool
    var operationInProgress: Bool

    var isEligible: Bool {
        enabled && permitsMutation && configurationReady && !operationInProgress
    }
}

/// Share one launch decision across startup, setup completion, and installation
/// changes. A resolved generation is never retried by background refreshes.
@MainActor
final class GatewayAutoStartCoordinator {
    enum Reachability { case running, offline, unavailable }
    enum Outcome { case skipped, alreadyRunning, started, failed, cancelled }

    private var attempted: Set<Int> = []
    private var isChecking = false

    func ensureStarted(
        snapshot: GatewayAutoStartSnapshot,
        currentSnapshot: () -> GatewayAutoStartSnapshot,
        probe: () async -> Reachability,
        start: () async -> Outcome
    ) async -> Outcome {
        guard snapshot.isEligible, !isChecking, !attempted.contains(snapshot.generation) else {
            return .skipped
        }
        isChecking = true
        defer { isChecking = false }

        let reachability = await probe()
        let current = currentSnapshot()
        guard current == snapshot, current.isEligible else { return .skipped }
        guard !Task.isCancelled else {
            attempted.insert(snapshot.generation)
            return .cancelled
        }

        // Record before the next suspension so simultaneous callers, failures,
        // and cancelled authorization cannot trigger another automatic start.
        attempted.insert(snapshot.generation)
        switch reachability {
        case .running:
            return .alreadyRunning
        case .unavailable:
            return .skipped
        case .offline:
            return await start()
        }
    }
}
