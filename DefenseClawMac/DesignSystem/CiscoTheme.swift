// Cisco design system (spec §6): brand palette + severity/state mappings.
// Colors defined in code (light/dark aware) so no asset catalog is required.

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Light/dark adaptive color.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}

enum Cisco {
    // Brand
    static let blue = Color.adaptive(light: 0x049FD9, dark: 0x04AEED)
    static let midnight = Color(hex: 0x0D274D)
    static let sky = Color(hex: 0x64BBE3)

    // Status (Cisco UI Kit)
    static let green = Color(hex: 0x6ABF4B)
    static let red = Color(hex: 0xE2231A)
    static let orange = Color(hex: 0xFBAB18)
    static let yellow = Color(hex: 0xEED202)
    static let magenta = Color(hex: 0xBF4B8B)

    // Surfaces
    static let surfacePanel = Color.adaptive(light: 0xF5F7FA, dark: 0x111B2C)
    static let surfaceRaised = Color.adaptive(light: 0xFFFFFF, dark: 0x16233A)

    static func severityColor(_ s: Severity) -> Color {
        switch s {
        case .critical: red
        case .high: orange
        case .medium: yellow
        case .low: sky
        case .info: Color.secondary
        }
    }

    static func stateColor(_ s: EntityState) -> Color {
        switch s {
        case .active: green
        case .blocked: red
        case .warn: orange
        case .quarantined: magenta
        case .disabled: Color.secondary.opacity(0.6)
        }
    }

    static func stateColor(raw: String) -> Color {
        stateColor(EntityState.classify(raw))
    }
}
