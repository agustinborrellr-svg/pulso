import SwiftUI

/// One segment of a segment monitor: a short bar in the level colour with its icon underneath and, when it is out
/// of range, its value under the icon.
struct DSMonitorSegment: Identifiable {
    let id: String
    let icon: String
    /// Bar colour (a level mark, or `DS.fill2` while calibrating).
    let color: Color
    var iconColor: Color = DS.t3
    /// Shown under the icon (out of range) or beside it (`inline`).
    var value: String?
    var valueColor: Color = DS.t2
    var accessibilityLabel: String
    var accessibilityValue: String = ""
}

/// Segment monitor (Hoy «Monitor de salud», 03-monitor «Constantes»): a header with icon, title, status word and
/// chevron, then equal segments and, after a hairline, an optional extra segment with its value inline (stress), and
/// one optional line of explanation.
struct DSSegmentMonitor: View {
    var icon: String = "heart.fill"
    var iconColor: Color = DS.cor
    let title: String
    var status: String?
    var statusColor: Color = DS.t3
    var chevron = true
    let segments: [DSMonitorSegment]
    var extra: DSMonitorSegment?
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(iconColor)
                Text(title).dsFont(16, .medium, relativeTo: .subheadline).foregroundStyle(DS.t2)
                Spacer(minLength: 6)
                if let status {
                    Text(status).dsFont(15, .semibold).foregroundStyle(statusColor).lineLimit(1).minimumScaleFactor(0.8)
                }
                if chevron { DSChevron() }
            }
            if !segments.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(segments) { segment($0) }
                    if let extra {
                        Rectangle().fill(DS.sep).frame(width: 1, height: 30).padding(.horizontal, 2)
                        inline(extra)
                    }
                }
                if let note {
                    Text(note).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func segment(_ s: DSMonitorSegment) -> some View {
        VStack(spacing: 7) {
            Capsule().fill(s.color).frame(height: 6)
            Image(systemName: s.icon).font(.system(size: 12)).foregroundStyle(s.iconColor).frame(height: 14)
            if let v = s.value {
                Text(v).dsFont(12, .semibold, relativeTo: .caption1).foregroundStyle(s.valueColor)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, -3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.accessibilityLabel)
        .accessibilityValue(s.accessibilityValue)
    }

    private func inline(_ s: DSMonitorSegment) -> some View {
        VStack(spacing: 7) {
            Capsule().fill(s.color).frame(height: 6)
            HStack(spacing: 4) {
                Image(systemName: s.icon).font(.system(size: 12)).foregroundStyle(s.iconColor)
                if let v = s.value {
                    Text(v).dsFont(12.5, .semibold, relativeTo: .caption1).foregroundStyle(s.valueColor).fixedSize()
                }
            }
            .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.accessibilityLabel)
        .accessibilityValue(s.accessibilityValue)
    }
}
