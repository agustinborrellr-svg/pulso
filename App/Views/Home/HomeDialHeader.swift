import SwiftUI
import PulsoStore
import PulsoAnalytics

/// Inicio's header: the top bar over the three big dials, which shrink into a row of small dials pinned at the top as
/// the page scrolls. `progress` goes from 0 (page at the top) to 1 (collapsed) with the scroll itself, so the dials
/// follow the finger both ways.
struct HomeDialHeader: View {
    @EnvironmentObject var model: AppModel
    let progress: CGFloat
    @State private var open: Pillar?
    @State private var labelWidths: [Pillar: CGFloat] = [:]

    enum Pillar: CaseIterable, Hashable { case sleep, recovery, strain }

    static let barHeight: CGFloat = 52
    static let bigRow: CGFloat = 120
    static let smallRow: CGFloat = 46
    static let gap: CGFloat = 10
    static var expandedHeight: CGFloat { barHeight + bigRow + gap }
    /// Scroll distance over which the header collapses: what it loses in height, so the content never slides under
    /// it until it is fully collapsed.
    static var collapseDistance: CGFloat { expandedHeight - smallRow }

    private static let bigDial: CGFloat = 76
    private static let smallDial: CGFloat = 22
    private static let labelSize: CGFloat = 11

    var body: some View {
        let p = min(max(progress, 0), 1)
        let day = model.selected
        VStack(spacing: 0) {
            HomeTopBar()
                .frame(height: Self.barHeight, alignment: .top)
                .frame(height: Self.barHeight * (1 - p), alignment: .bottom)
                .clipped()
                .opacity(Double(max(0, 1 - p * 1.8)))
            GeometryReader { g in
                ZStack {
                    ForEach(Pillar.allCases, id: \.self) { pillar in
                        dial(pillar, day: day, p: p, width: g.size.width, height: g.size.height)
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .frame(height: Self.bigRow + (Self.smallRow - Self.bigRow) * p)
            .background(Theme.card.opacity(Double(1 - p)), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .padding(.bottom, Self.gap * (1 - p))
        }
        .padding(.horizontal, 16)
        .background(alignment: .top) {
            PulsoBackground().opacity(Double(p)).ignoresSafeArea(edges: .top)
        }
        .background(alignment: .top) {
            // Widths of the labels in the small row, measured once, to place each dial and its name side by side.
            HStack {
                ForEach(Pillar.allCases, id: \.self) { pillar in
                    Caps(title(pillar), size: Self.labelSize)
                        .fixedSize()
                        .background(GeometryReader { g in Color.clear.preference(key: LabelWidths.self, value: [pillar: g.size.width]) })
                }
            }
            .hidden()
        }
        .onPreferenceChange(LabelWidths.self) { labelWidths = $0 }
        .navigationDestination(item: $open) { pillar in
            switch pillar {
            case .sleep: SleepDetailView()
            case .recovery: RecoveryDetailView()
            case .strain: StrainDetailView()
            }
        }
    }

    // MARK: - One dial

    private func dial(_ pillar: Pillar, day: DaySummary?, p: CGFloat, width w: CGFloat, height h: CGFloat) -> some View {
        let i = CGFloat(Pillar.allCases.firstIndex(of: pillar) ?? 0)
        let d = Self.bigDial + (Self.smallDial - Self.bigDial) * p
        let line = 8 + (3 - 8) * p
        // Big: three equal columns, the name under the dial.
        let bigX = w * (2 * i + 1) / 6
        let bigRingY = 10 + Self.bigDial / 2
        let bigLabelY = 10 + Self.bigDial + 17
        // Small: [dial name] [dial name] [dial name] spread across the row, the name beside the dial.
        let small = smallPositions(width: w)[Int(i)]
        let ringX = bigX + (small.ring - bigX) * p
        let ringY = bigRingY + (h / 2 - bigRingY) * p
        let labelX = bigX + (small.label - bigX) * p
        let labelY = bigLabelY + (h / 2 - bigLabelY) * p
        let v = values(pillar, day: day)
        return ZStack {
            ZStack {
                Dial(progress: v.progress, color: v.color, lineWidth: line)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(v.value).scaledFont(22, weight: .bold, relativeTo: .title1).monospacedDigit()
                    if !v.unit.isEmpty { Text(v.unit).scaledFont(10, weight: .bold, relativeTo: .caption1) }
                }
                .foregroundStyle(.white)
                .scaleEffect(d / Self.bigDial)
                .opacity(Double(max(0, 1 - p * 2.2)))
            }
            .frame(width: d, height: d)
            .contentShape(Circle())
            .onTapGesture { open = pillar }
            .position(x: ringX, y: ringY)
            ZStack {
                Caps(title(pillar), size: Self.labelSize, color: v.color).opacity(Double(1 - p))
                Caps(title(pillar), size: Self.labelSize).opacity(Double(p))
            }
            .fixedSize()
            .padding(6)
            .contentShape(Rectangle())
            .onTapGesture { open = pillar }
            .position(x: labelX, y: labelY)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open = pillar }
    }

    /// Centres of each small dial and its name: the three groups spread edge to edge with equal space between.
    private func smallPositions(width w: CGFloat) -> [(ring: CGFloat, label: CGFloat)] {
        let space: CGFloat = 7
        let widths = Pillar.allCases.map { labelWidths[$0] ?? 90 }
        let groups = widths.map { Self.smallDial + space + $0 }
        let between = max(0, (w - 8 - groups.reduce(0, +)) / 2)
        var x: CGFloat = 4
        return zip(groups, widths).map { group, label in
            defer { x += group + between }
            return (x + Self.smallDial / 2, x + Self.smallDial + space + label / 2)
        }
    }

    private func title(_ pillar: Pillar) -> String {
        switch pillar {
        case .sleep: return "Sueño"
        case .recovery: return "Recuperación"
        case .strain: return "Esfuerzo"
        }
    }

    private func values(_ pillar: Pillar, day: DaySummary?) -> (progress: Double, color: Color, value: String, unit: String) {
        switch pillar {
        case .sleep:
            return (day?.sleepPerformance ?? 0, Theme.sleep, day?.sleepPerformance.map { "\(Int(($0 * 100).rounded()))" } ?? "–", "%")
        case .recovery:
            return ((day?.recovery ?? 0) / 100, Theme.recoveryColor(day?.recovery),
                    day?.recovery.map { "\(Int($0))" } ?? (day?.calibrating == true ? "…" : "–"), day?.recovery == nil ? "" : "%")
        case .strain:
            return ((day?.strain ?? 0) / 21, Theme.strain, Fmt.dec(day?.strain), "")
        }
    }
}

private struct LabelWidths: PreferenceKey {
    static var defaultValue: [HomeDialHeader.Pillar: CGFloat] = [:]
    static func reduce(value: inout [HomeDialHeader.Pillar: CGFloat], nextValue: () -> [HomeDialHeader.Pillar: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Where the top of Inicio's content is, to drive the header.
struct HomeScrollOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    // Only one view reports it; the others add their 0 instead of overwriting it.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}
