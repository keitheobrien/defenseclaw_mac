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
    static let sky = Color(nsColor: .systemCyan)

    // System status colors preserve the Cisco semantics while adapting to
    // appearance and Increase Contrast preferences.
    static let green = Color(nsColor: .systemGreen)
    static let red = Color(nsColor: .systemRed)
    static let orange = Color(nsColor: .systemOrange)
    static let yellow = Color(nsColor: .systemYellow)
    static let magenta = Color(nsColor: .systemPurple)
    /// Fill behind white text (critical badge, sidebar count). The system red
    /// is too light for white 10-point text; this one clears 4.5:1.
    static let criticalFill = Color.adaptive(light: 0xC9000F, dark: 0xD70015)

    // Surfaces. Content cards use translucent system fills so they sit on
    // whatever is behind them (window, sheet, popover, Liquid Glass sidebar
    // edge) and follow appearance, Increase Contrast and Reduce Transparency.
    // Raised tiles stack on panels, so the stronger fill reads as one step up.
    static let surfacePanel = Color(nsColor: .quaternarySystemFill)
    static let surfaceRaised = Color(nsColor: .tertiarySystemFill)
    /// Opaque surface for floating chrome on systems without Liquid Glass.
    static let surfaceOpaque = Color.adaptive(light: 0xFFFFFF, dark: 0x16233A)

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

extension Font {
    /// Primary text in table cells and detail-pane values (12 pt). Text
    /// styles, never fixed sizes, so system text-size settings apply.
    static let dcCell = Font.callout
    /// Secondary table text, identifiers and detail-pane labels (11 pt).
    static let dcCellSecondary = Font.subheadline
}

enum DCMetrics {
    static let floatingCornerRadius: CGFloat = 12
}

extension View {
    /// Floating chrome (banners, callouts that sit above content): Liquid
    /// Glass on macOS 26 and later, the previous opaque fill before that.
    /// Content cards deliberately do not use glass — it is reserved for the
    /// control and navigation layer.
    @ViewBuilder
    func dcFloatingSurface(tint: Color? = nil, fallback: Color, fallbackForeground: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            // Tinted glass changes with appearance and what is behind it, so
            // text uses the adaptive primary color instead of fixed white.
            foregroundStyle(.primary).glassEffect(
                tint.map { Glass.regular.tint($0) } ?? Glass.regular,
                in: .rect(cornerRadius: DCMetrics.floatingCornerRadius)
            )
        } else {
            foregroundStyle(fallbackForeground ?? Color.primary)
                .background(fallback, in: RoundedRectangle(cornerRadius: DCMetrics.floatingCornerRadius))
        }
    }
}
