import Foundation

enum AIDiscoveryPrimaryAction: Equatable, Sendable {
    case enable
    case scan

    static func resolve(enabled: Bool) -> Self {
        enabled ? .scan : .enable
    }

    var title: String {
        switch self {
        case .enable: "Enable AI Discovery"
        case .scan: "Scan AI Discovery"
        }
    }

    var label: String {
        switch self {
        case .enable: "Enable AI Discovery"
        case .scan: "Scan Now"
        }
    }

    var systemImage: String {
        switch self {
        case .enable: "power"
        case .scan: "wand.and.rays"
        }
    }

    var arguments: [String] {
        switch self {
        case .enable: ["agent", "discovery", "enable", "--yes"]
        case .scan: ["agent", "discovery", "scan"]
        }
    }

    var category: String {
        switch self {
        case .enable: "setup"
        case .scan: "scan"
        }
    }

    var successEffects: [String] {
        switch self {
        case .enable: ["AI Discovery enabled", "Initial AI usage scan completed"]
        case .scan: ["AI Discovery snapshot refreshed"]
        }
    }
}

enum AIDiscoveryScanRequestStep: Equatable, Sendable {
    case loadStatus
    case showDisabled
    case scan

    static func resolve(statusLoaded: Bool, enabled: Bool) -> Self {
        guard statusLoaded else { return .loadStatus }
        return enabled ? .scan : .showDisabled
    }
}
