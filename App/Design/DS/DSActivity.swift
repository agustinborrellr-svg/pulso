import SwiftUI

// Activities in the design system: the coloured chip, the activity row and the 24-hour day strip.

/// Coloured chip with an icon and a figure ("☾ 7:12", "🔥 5,8"): the identity colour at 20 % behind.
struct DSActivityChip: View {
    let icon: String
    let color: Color
    let text: String
    var small = false
    var width: CGFloat? = 76

    var body: some View {
        HStack(spacing: small ? 5 : 7) {
            Image(systemName: icon).font(.system(size: small ? 11 : 13, weight: .semibold)).foregroundStyle(color)
            Text(text).dsFont(small ? 14.5 : 17, .semibold).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, width == nil ? 10 : 0)
        .frame(width: width, height: small ? 28 : 34)
        .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: small ? 8 : 10, style: .continuous))
    }
}

/// Activity row: chip, name and subtitle, start and end times on the right, optional chevron.
struct DSActivityRow: View {
    let icon: String
    let color: Color
    let duration: String
    let title: String
    var subtitle: String?
    var start: String?
    var end: String?
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            DSActivityChip(icon: icon, color: color, text: duration)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).dsFont(17, .semibold).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle).dsFont(15).foregroundStyle(DS.t2).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 6)
            if start != nil || end != nil {
                VStack(alignment: .trailing, spacing: 1) {
                    if let start { Text(start) }
                    if let end { Text(end) }
                }
                .dsFont(15).foregroundStyle(DS.t2)
            }
            if chevron { DSChevron() }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The 24 hours on one strip: coloured stretches (sleep by stage, activities thinner), the hours still to come darker,
/// a marker at now and hour labels underneath. Times are Unix seconds.
struct DSDayStrip: View {
    struct Segment: Identifiable {
        let id: String
        let start: Int
        let end: Int
        let color: Color
        var thin = false
    }

    let start: Int
    let end: Int
    let segments: [Segment]
    /// Draws the "now" marker when it falls inside the window.
    var now: Int? = Int(Date().timeIntervalSince1970)
    /// Hours after `start` that get a label.
    var labelHours: [Int] = [0, 6, 12, 24]

    var body: some View {
        let span = max(end - start, 1)
        let showNow = now.map { $0 > start && $0 < end } ?? false
        let nowT = now ?? 0
        VStack(spacing: 6) {
            GeometryReader { g in
                let x = { (t: Int) -> CGFloat in g.size.width * CGFloat(t - start) / CGFloat(span) }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(DS.fill)
                    if showNow {
                        Rectangle().fill(Color.black.opacity(0.45))
                            .frame(width: max(0, g.size.width - x(nowT))).offset(x: x(nowT))
                    }
                    ForEach(segments.filter { $0.end > start && $0.start < end }) { s in
                        RoundedRectangle(cornerRadius: s.thin ? 3 : 1.5, style: .continuous).fill(s.color)
                            .frame(width: max(s.thin ? 6 : 1.5, x(min(s.end, end)) - x(max(s.start, start))), height: s.thin ? 14 : 18)
                            .offset(x: x(max(s.start, start)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .leading) {
                    if showNow {
                        Capsule().fill(DS.t1).frame(width: 2, height: 28).offset(x: x(nowT) - 1)
                    }
                }
            }
            .frame(height: 22)
            GeometryReader { g in
                let x = { (t: Int) -> CGFloat in g.size.width * CGFloat(t - start) / CGFloat(span) }
                ZStack(alignment: .leading) {
                    ForEach(labelHours, id: \.self) { h in
                        let t = start + h * 3600
                        if !(showNow && abs(t - nowT) < 2 * 3600) {
                            Text(DSFmt.hour(t)).dsFont(12, .medium, relativeTo: .caption1).foregroundStyle(DS.t3)
                                .fixedSize()
                                .position(x: min(max(x(t), 8), g.size.width - 8), y: 7)
                        }
                    }
                    if showNow {
                        Text(Fmt.time(nowT)).dsFont(12, .bold, relativeTo: .caption1).foregroundStyle(DS.t1)
                            .fixedSize()
                            .position(x: min(max(x(nowT), 16), g.size.width - 16), y: 7)
                    }
                }
            }
            .frame(height: 14)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Franja de las últimas 24 horas")
    }
}
