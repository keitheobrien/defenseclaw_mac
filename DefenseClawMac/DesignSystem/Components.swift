// Shared UI components (spec §6.2): badges, pills, cards, chips, diff view.
// Color is never the only signal — every colored element carries a label.

import SwiftUI

struct SeverityBadge: View {
    let severity: Severity
    var body: some View {
        Text(severity.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Cisco.severityColor(severity).opacity(severity == .medium ? 0.85 : 0.18))
            .foregroundStyle(severity == .medium ? Color.black : Cisco.severityColor(severity))
            .clipShape(Capsule())
    }
}

struct StatePill: View {
    let raw: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Cisco.stateColor(raw: raw)).frame(width: 7, height: 7)
            Text(raw.lowercased())
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Cisco.stateColor(raw: raw).opacity(0.12))
        .clipShape(Capsule())
    }
}

struct StaleBadge: View {
    let date: Date
    var body: some View {
        if date.isStale {
            Label("stale · \(DCDates.relative(date))", systemImage: "clock.badge.exclamationmark")
                .font(.caption2)
                .foregroundStyle(Cisco.orange)
        }
    }
}

struct StatCard<Content: View>: View {
    let title: String
    let value: String
    var tint: Color = Cisco.blue
    @ViewBuilder var detail: Content

    init(title: String, value: String, tint: Color = Cisco.blue, @ViewBuilder detail: () -> Content = { EmptyView() }) {
        self.title = title
        self.value = value
        self.tint = tint
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            detail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Cisco.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DCCard<Content: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var content: Content

    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(Cisco.blue)
                }
                Text(title).font(.headline)
                Spacer()
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Cisco.surfacePanel, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Single-select chip row — native port of the TUI's cycling filter chips.
struct FilterChipRow<T: Hashable>: View {
    let options: [(label: String, value: T)]
    @Binding var selection: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    let isOn = option.value == selection
                    Button {
                        selection = option.value
                    } label: {
                        Text(option.label)
                            .font(.caption.weight(isOn ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isOn ? Cisco.blue : Color.secondary.opacity(0.12))
                            .foregroundStyle(isOn ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Red/green before-after JSON diff (Activity detail, Setup review).
struct DiffView: View {
    let before: String
    let after: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            diffColumn("Before", text: before, tint: Cisco.red, prefix: "−")
            diffColumn("After", text: after, tint: Cisco.green, prefix: "+")
        }
    }

    private func diffColumn(_ title: String, text: String, tint: Color, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
            ScrollView {
                Text(text.isEmpty ? "(empty)" : text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity)
    }
}

struct KeyValueGrid: View {
    let pairs: [(String, String)]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                GridRow {
                    Text(pair.0).font(.caption).foregroundStyle(.secondary)
                    Text(pair.1).font(.caption).textSelection(.enabled)
                }
            }
        }
    }
}

struct DCEmptyState: View {
    let title: String
    let message: String
    var systemImage: String = "tray"

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

struct ConfidenceGauge: View {
    let value: Double // 0...1
    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: max(0, min(1, value)))
                .progressViewStyle(.linear)
                .tint(value > 0.8 ? Cisco.green : value > 0.5 ? Cisco.orange : Cisco.red)
                .frame(width: 70)
            Text("\(Int(value * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
