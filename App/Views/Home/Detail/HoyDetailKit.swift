import SwiftUI
import PulsoStore
import PulsoAnalytics

// Pieces shared by the Hoy drill-downs (studio A-hoy): hero card, heart-rate zones, bars by day, points list and the
// grouped rows of the sheets. Everything draws only what it is given.

/// Hero card: big value + unit, whatever goes under it, a side table and an optional footer (separated by a hairline).
struct HoyHero<Below: View, Footer: View>: View {
    let value: String
    var unit: String = ""
    var side: [(String, String)] = []
    @ViewBuilder var below: Below
    @ViewBuilder var footer: Footer

    init(value: String, unit: String = "", side: [(String, String)] = [], @ViewBuilder below: () -> Below,
         @ViewBuilder footer: () -> Footer) {
        self.value = value
        self.unit = unit
        self.side = side
        self.below = below()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(value).dsFont(52, .semibold, relativeTo: .largeTitle, maxScale: 1.15)
                            .foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.5)
                        if !unit.isEmpty {
                            Text(unit).dsFont(18, .medium).foregroundStyle(DS.t2).lineLimit(1)
                        }
                    }
                    below
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if !side.isEmpty {
                    DSSideTable(rows: side).padding(.top, 8)
                }
            }
            footer
        }
        .dsCard(padding: 14)
    }
}

extension HoyHero where Footer == EmptyView {
    init(value: String, unit: String = "", side: [(String, String)] = [], @ViewBuilder below: () -> Below) {
        self.init(value: value, unit: unit, side: side, below: below) { EmptyView() }
    }
}

// MARK: - Zonas de pulso

/// «Zonas de pulso»: the five zones as one stacked bar (share of the time) and a row per zone with its band of your
/// heart-rate reserve and the time spent in it.
struct HoyZonesCard: View {
    let minutes: [Double]

    static let names = ["Muy suave", "Suave", "Moderada", "Intensa", "Máxima"]
    static let bands = ["40–59 %", "60–69 %", "70–79 %", "80–89 %", "90–100 %"]

    var body: some View {
        let z = (0..<5).map { $0 < minutes.count ? minutes[$0] : 0 }
        let total = max(z.reduce(0, +), 0.0001)
        VStack(alignment: .leading, spacing: 0) {
            Text("% de tu reserva de pulso").dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2)
            GeometryReader { g in
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { i in
                        if z[i] > 0 {
                            Capsule().fill(DS.zone(i + 1))
                                .frame(width: max(5, (g.size.width - 12) * CGFloat(z[i] / total)))
                        }
                    }
                }
            }
            .frame(height: 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
            ForEach(0..<5, id: \.self) { i in
                if i > 0 { DSDivider() }
                HStack(spacing: 10) {
                    Circle().fill(DS.zone(i + 1)).frame(width: 8, height: 8)
                    Text(Self.names[i]).dsFont(16, .medium).foregroundStyle(DS.t1)
                    Spacer(minLength: 6)
                    Text(Self.bands[i]).dsFont(13).foregroundStyle(DS.t3)
                    Text(DSFmt.duration(z[i])).dsFont(16, .semibold).foregroundStyle(DS.t1)
                        .frame(minWidth: 62, alignment: .trailing)
                }
                .frame(minHeight: 40)
                .accessibilityElement(children: .combine)
            }
        }
        .dsCard(padding: 14)
    }
}

// MARK: - Bars by day

/// One bar of `HoyBars`.
struct HoyBar: Identifiable {
    let id: Int
    let label: String
    let value: Double?
}

/// Bars bottom-aligned on a shared scale, the last one highlighted; optional band (a target) with its label and a
/// right-hand axis.
struct HoyBars: View {
    let bars: [HoyBar]
    var color: Color = DS.act
    var lastColor: Color?
    var maxValue: Double?
    var band: ClosedRange<Double>?
    var bandLabel: String?
    var axis: [Double] = []
    var format: (Double) -> String = { Fmt.dec($0) }
    var height: CGFloat = 120

    var body: some View {
        let top = max(maxValue ?? 0, bars.compactMap(\.value).max() ?? 0, band?.upperBound ?? 0, 0.001) * 1.08
        let many = bars.count > 10
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                GeometryReader { g in
                    let h = g.size.height
                    ZStack(alignment: .bottomLeading) {
                        ForEach(axis, id: \.self) { a in
                            Rectangle().fill(DS.sep).frame(height: 0.5).offset(y: -h * CGFloat(a / top))
                        }
                        if let band {
                            Rectangle().fill(color.opacity(0.16))
                                .overlay(Rectangle().fill(color.opacity(0.45)).frame(height: 1), alignment: .top)
                                .frame(height: h * CGFloat((min(band.upperBound, top) - band.lowerBound) / top))
                                .offset(y: -h * CGFloat(band.lowerBound / top))
                            if let bandLabel {
                                Text(bandLabel).dsFont(11, .semibold, relativeTo: .caption2).foregroundStyle(color)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .offset(y: -h * CGFloat(min(band.upperBound, top) / top) - 4)
                            }
                        }
                        HStack(alignment: .bottom, spacing: many ? 2 : 10) {
                            ForEach(bars) { b in
                                let last = b.id == bars.last?.id
                                RoundedRectangle(cornerRadius: many ? 2 : 6, style: .continuous)
                                    .fill(last ? (lastColor ?? color) : color.opacity(0.55))
                                    .frame(height: max(b.value.map { h * CGFloat($0 / top) } ?? 0, b.value == nil ? 0 : 3))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .frame(height: height)
                if !axis.isEmpty {
                    GeometryReader { g in
                        ForEach(axis, id: \.self) { a in
                            Text(format(a)).dsFont(11, .medium, relativeTo: .caption2).foregroundStyle(DS.t3)
                                .position(x: 10, y: g.size.height * CGFloat(1 - a / top))
                        }
                    }
                    .frame(width: 22, height: height)
                }
            }
            if !many {
                HStack(spacing: 10) {
                    ForEach(bars) { b in
                        Text(b.label).dsFont(12, b.id == bars.last?.id ? .bold : .medium, relativeTo: .caption1)
                            .foregroundStyle(b.id == bars.last?.id ? DS.t1 : DS.t3)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.trailing, axis.isEmpty ? 0 : 30)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Barras por día")
    }
}

enum HoyBarSeries {
    /// Weekday letter (L M X J V S D) of a day key.
    static func weekday(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return "" }
        let w = Calendar(identifier: .gregorian).component(.weekday, from: d)
        return ["D", "L", "M", "X", "J", "V", "S"][(w - 1) % 7]
    }

    /// The days of a period ending on `end` (7 or 30 bars, one per day), or 26 weekly means for 6 months.
    static func bars(_ days: [DaySummary], end: String, period: DSPeriod, value: (DaySummary) -> Double?) -> [HoyBar] {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        if period.days <= 31 {
            return (0..<period.days).map { i in
                let key = DayKey.shift(end, days: i - period.days + 1)
                return HoyBar(id: i, label: weekday(key), value: byDay[key].flatMap(value))
            }
        }
        return (0..<26).map { w in
            let vals = (0..<7).compactMap { d in byDay[DayKey.shift(end, days: -(25 - w) * 7 - (6 - d))].flatMap(value) }
            return HoyBar(id: w, label: "", value: vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count))
        }
    }
}

// MARK: - Points list («Qué ha influido», «Qué te quita y te suma años»)

/// One row of `HoyPointsList`.
struct HoyPointRow: Identifiable {
    let id: String
    let icon: String
    var iconColor: Color = DS.t2
    let title: String
    var subtitle: String?
    /// −1…1: left or right of the centre tick.
    let effect: Double
    /// Whether the effect is good for you (green) or not (red).
    let good: Bool
    let word: String
    var route: Route?
}

/// Rows with a divergent bar around a centre tick, the signed points and a chevron when the row opens something.
struct HoyPointsList<Footer: View>: View {
    let rows: [HoyPointRow]
    var axis: (String, String)
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "arrowtriangle.left.fill").font(.system(size: 7)).foregroundStyle(DS.baja)
                    Text(axis.0)
                }
                HStack(spacing: 3) {
                    Text(axis.1)
                    Image(systemName: "arrowtriangle.right.fill").font(.system(size: 7)).foregroundStyle(DS.buena)
                }
                Spacer().frame(width: 74)
            }
            .dsFont(12, .medium, relativeTo: .caption1)
            .foregroundStyle(DS.t2)
            .padding(.top, 10)
            ForEach(rows.indices, id: \.self) { i in
                if i > 0 { DSDivider(inset: 32) }
                if let r = rows[i].route {
                    RouteLink(r) { row(rows[i], chevron: true) }
                } else {
                    row(rows[i], chevron: false)
                }
            }
            footer
        }
        .padding(.horizontal, 14)
        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }

    private func row(_ r: HoyPointRow, chevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.icon).font(.system(size: 15)).foregroundStyle(r.iconColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title).dsFont(16, .medium).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                if let s = r.subtitle { Text(s).dsFont(13).foregroundStyle(DS.t2).lineLimit(1).minimumScaleFactor(0.8) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HoyPointBar(effect: r.effect, good: r.good).frame(width: 78, height: 14)
            Text(r.word).dsFont(16, .semibold).foregroundStyle(r.good ? DSLevel.buena.ink : DSLevel.baja.ink)
                .frame(width: 40, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.7)
            DSChevron().opacity(chevron ? 1 : 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension HoyPointsList where Footer == EmptyView {
    init(rows: [HoyPointRow], axis: (String, String)) {
        self.init(rows: rows, axis: axis) { EmptyView() }
    }
}

/// Bar from a centre tick: right or left by the effect, green when good for you, red when not.
struct HoyPointBar: View {
    let effect: Double
    let good: Bool

    var body: some View {
        GeometryReader { g in
            let half = g.size.width / 2
            let w = max(half * CGFloat(min(abs(effect), 1)), 3)
            ZStack(alignment: .leading) {
                Rectangle().fill(DS.sep).frame(height: 1).frame(maxHeight: .infinity)
                RoundedRectangle(cornerRadius: 2).fill(good ? DS.buena : DS.baja)
                    .frame(width: w, height: 8)
                    .offset(x: effect < 0 ? half - w : half)
                Rectangle().fill(DS.t2).frame(width: 1.5, height: 14).offset(x: half - 0.75)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Sheets

/// Label over a group inside a sheet ("Actividad", "Tiempo").
struct HoySheetLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).dsFont(15, .semibold, relativeTo: .subheadline).foregroundStyle(DS.t2)
            .padding(.leading, 4).padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rows on the sheet surface: a lighter rounded block with hairlines between rows.
struct HoySheetGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DS.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }
}

/// A plain row card on a detail page with an icon, two lines and a chevron («Hábitos que te afectan»).
struct HoyLinkCard: View {
    let icon: String
    var iconColor: Color = DS.t2
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(iconColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dsFont(17, .semibold).foregroundStyle(DS.t1)
                if let subtitle { Text(subtitle).dsFont(14).foregroundStyle(DS.t2) }
            }
            Spacer(minLength: 6)
            DSChevron()
        }
        .padding(.vertical, 6)
        .dsCard(padding: 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension DayActivity {
    /// The screen a row of the day opens: the night, a workout, or the guided-breathing summary.
    var route: Route {
        switch kind {
        case .sleep, .nap: return .sueno(.noche(day: nil))
        case .workout(let w): return isBreathing ? .actividad(.respiraResumen) : .hoy(.workout(start: w.start))
        }
    }
}
