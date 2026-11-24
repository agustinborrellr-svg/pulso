import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

// Shared pieces of the Sueño tab (studio APP/B-sueno): levels of the sleep factors, the night-metric spec builder
// (tu normal, ayer, 7 d / 30 d / 6 m), the B hero, the metric screen and small night drawings.

// MARK: - Levels

/// The four-step levels of the sleep factors (studio B notas, pregunta 3): Horas ≥95 Excelente, 85–95 Buena;
/// Regularidad ≥80; Eficiencia ≥90; Reparador ≥50, 35–50 Buena.
enum SuenoLevel {
    static func hoursVsNeed(_ v: Double) -> DSLevel { v >= 95 ? .excelente : (v >= 85 ? .buena : (v >= 70 ? .justa : .baja)) }
    static func regularity(_ v: Double) -> DSLevel { v >= 80 ? .excelente : (v >= 60 ? .buena : (v >= 40 ? .justa : .baja)) }
    static func efficiency(_ v: Double) -> DSLevel { v >= 90 ? .excelente : (v >= 85 ? .buena : (v >= 75 ? .justa : .baja)) }
    static func restorative(_ pct: Double) -> DSLevel { pct >= 50 ? .excelente : (pct >= 35 ? .buena : (pct >= 25 ? .justa : .baja)) }

    /// Level of a `SleepFactors` factor by its key.
    static func factor(_ f: SleepFactors.Factor) -> DSLevel {
        switch f.key {
        case "hoursVsNeed": return hoursVsNeed(f.value)
        case "regularity": return regularity(f.value)
        case "efficiency": return efficiency(f.value)
        default: return restorative(f.value)
        }
    }
}

// MARK: - Formatting

enum SFmt {
    static func dur(_ m: Double?) -> String { DSFmt.duration(m) }

    static func clock(_ ts: Int?) -> String {
        guard let ts else { return "–" }
        return DSFmt.clock(Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// "lun 16 nov".
    static func day(_ key: String) -> String { DSFmt.shortDate(key).lowercased() }

    /// "L", "M", "X"… of a day key.
    static func weekdayLetter(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return "" }
        return ["D", "L", "M", "X", "J", "V", "S"][Calendar.current.component(.weekday, from: d) - 1]
    }

    /// "Dom 15 → lun 16 nov" for the night that ends on `key`.
    static func nightRange(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE d"
        let prev = f.string(from: d.addingTimeInterval(-86_400)).replacingOccurrences(of: ".", with: "")
        return prev.prefix(1).uppercased() + prev.dropFirst() + " → " + SFmt.day(key)
    }

    /// Signed points: "+2", "−1", "0".
    static func points(_ v: Int) -> String { v > 0 ? "+\(v)" : (v < 0 ? "−\(abs(v))" : "0") }
}

// MARK: - Night metric spec

/// Values of a night metric by day (only nights that have it).
typealias NightPairs = [(day: String, v: Double)]

enum SuenoSpec {
    @MainActor
    static func pairs(_ model: AppModel, _ value: (DaySummary) -> Double?) -> NightPairs {
        model.days.compactMap { d in value(d).map { (day: d.day, v: $0) } }
    }

    /// Builds the template spec of a night metric from real values: the shown night (the selected day or the last
    /// before it), tu normal = mean ± 1 SD of the 30 nights before (≥ 7), the night before, and the 7 d / 30 d /
    /// 6 m series (6 m in weekly means). `level` gives a four-step level (with the meter); without it the level
    /// says where the night sits against tu normal.
    @MainActor
    static func make(model: AppModel, pairs: NightPairs, title: String, subtitle: String? = nil, back: String? = "Sueño",
                     format: @escaping (Double) -> String, unit: String = "", statUnit: String? = nil,
                     higherIsBetter: Bool? = true, level: ((Double) -> DSLevel)? = nil, initial: DSPeriod = .month,
                     periods: [DSPeriod] = DSPeriod.standard, yDomain: ClosedRange<Double>? = nil, whatIs: String?) -> DSMetricSpec {
        let key = model.selectedDay
        let current = pairs.last { $0.day <= key }
        var spec = DSMetricSpec(title: title, value: current.map { format($0.v) } ?? "–", unit: current == nil ? "" : unit)
        spec.subtitle = subtitle ?? current.map { "Sueño · " + SFmt.day($0.day) }
        spec.back = back
        spec.color = DS.sueno
        spec.format = format
        spec.statUnit = statUnit ?? unit
        spec.unitWord = "noches"
        spec.endLabel = "Anoche"
        spec.whatIs = whatIs
        spec.footnote = nil
        spec.initialPeriod = initial
        spec.periods = periods
        spec.yDomain = yDomain
        guard let current else { return spec }

        let from = DayKey.shift(current.day, days: -30)
        let base = pairs.filter { $0.day < current.day && $0.day >= from }.map(\.v)
        var sd = 0.0
        if base.count >= 7 {
            let mean = base.reduce(0, +) / Double(base.count)
            sd = sqrt(base.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(base.count - 1))
            let half = max(sd, abs(mean) * 0.01, 0.01)
            spec.normal = (mean - half)...(mean + half)
            spec.mean = mean
            sd = half
        }
        let v = current.v
        if let level {
            spec.level = level(v)
            spec.meter = true
        } else if let n = spec.normal {
            if n.contains(v) {
                spec.level = .buena
                spec.levelText = "En tu normal"
            } else {
                let above = v > n.upperBound
                let good = higherIsBetter.map { $0 == above }
                let far = above ? v > n.upperBound + sd : v < n.lowerBound - sd
                spec.level = good == true ? .buena : (far ? .baja : .justa)
                spec.levelText = above ? "Por encima de tu normal" : "Por debajo de tu normal"
            }
        }
        var side: [(String, String)] = []
        if let n = spec.normal { side.append(("Tu normal", "\(format(n.lowerBound))–\(format(n.upperBound))")) }
        if let prev = pairs.last(where: { $0.day < current.day }) {
            side.append((prev.day == DayKey.shift(current.day, days: -1) ? "Ayer" : DSFmt.dayMonth(prev.day), format(prev.v)))
        }
        spec.side = side

        func points(days: Int) -> [DSPoint] {
            let start = DayKey.shift(current.day, days: -(days - 1))
            return pairs.filter { $0.day >= start && $0.day <= current.day }
                .compactMap { p in DayKey.date(p.day).map { DSPoint(date: $0, value: p.v) } }
        }
        var series: [DSPeriod: [DSPoint]] = [.week: points(days: 7), .month: points(days: 30)]
        if periods.contains(.halfYear) {
            let half = points(days: 182)
            if let first = half.first?.date {
                var weeks: [Int: [Double]] = [:]
                for p in half { weeks[Int(p.date.timeIntervalSince(first) / (7 * 86_400)), default: []].append(p.value) }
                series[.halfYear] = weeks.keys.sorted().map { w in
                    let vals = weeks[w] ?? []
                    return DSPoint(date: first.addingTimeInterval(Double(w * 7 + 3) * 86_400),
                                   value: vals.reduce(0, +) / Double(max(vals.count, 1)))
                }
            }
        }
        spec.series = series
        return spec
    }

    /// Mean ± 1 SD of the 30 nights before `day` (nil with fewer than 7).
    @MainActor
    static func normal(_ model: AppModel, before day: String, _ value: (DaySummary) -> Double?) -> ClosedRange<Double>? {
        let from = DayKey.shift(day, days: -30)
        let base = model.days.filter { $0.day < day && $0.day >= from }.compactMap(value)
        guard base.count >= 7 else { return nil }
        let mean = base.reduce(0, +) / Double(base.count)
        let sd = sqrt(base.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(base.count - 1))
        let half = max(sd, abs(mean) * 0.01, 0.01)
        return (mean - half)...(mean + half)
    }
}

// MARK: - Hero (B template)

/// The B hero: big value + unit, level word (dot, meter) with an optional "· 21 % de la noche", then a hairline and
/// «Tu normal | Ayer» side by side.
struct SuenoHero: View {
    let spec: DSMetricSpec
    var suffix: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(spec.value).dsFont(56, .semibold, relativeTo: .largeTitle, maxScale: 1.15)
                    .foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.5)
                if !spec.unit.isEmpty {
                    Text(spec.unit).dsFont(20, .medium).foregroundStyle(DS.t2).lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                if let level = spec.level {
                    DSLevelWord(level: level, text: spec.levelText, meter: spec.meter)
                }
                if let suffix {
                    Text((spec.level == nil ? "" : "· ") + suffix).dsFont(15).foregroundStyle(DS.t2).lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.top, 4)
            if !spec.side.isEmpty {
                DSDivider().padding(.top, 14)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(spec.side.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(spec.side[i].0).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2).lineLimit(1)
                            Text(spec.side[i].1).dsFont(19, .semibold).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.leading, i == 0 ? 0 : 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(DS.sep).frame(width: 0.5) } }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 11)
            }
        }
        .dsCard(padding: 16)
    }
}

/// A Sueño metric screen: DS bar, B hero, the metric's own cards, the chart card, then «Qué es».
struct SuenoMetricScreen<Top: View, Extra: View, Below: View>: View {
    let spec: DSMetricSpec
    var suffix: String?
    var chart = true
    @ViewBuilder var top: Top
    @ViewBuilder var extra: Extra
    @ViewBuilder var below: Below

    init(spec: DSMetricSpec, suffix: String? = nil, chart: Bool = true, @ViewBuilder top: () -> Top,
         @ViewBuilder extra: () -> Extra, @ViewBuilder below: () -> Below) {
        self.spec = spec
        self.suffix = suffix
        self.chart = chart
        self.top = top()
        self.extra = extra()
        self.below = below()
    }

    var body: some View {
        DSScreen(spec.title, subtitle: spec.subtitle, back: spec.back) {
            top
            SuenoHero(spec: spec, suffix: suffix)
            extra
            if chart, spec.series.values.contains(where: { !$0.isEmpty }) {
                DSMetricChartCard(spec: spec)
            }
            below
            if let text = spec.whatIs {
                DSSectionHeader("Qué es")
                DSWhatIs(text: text, footnote: spec.footnote)
            }
        }
    }
}

extension SuenoMetricScreen where Top == EmptyView, Below == EmptyView {
    init(spec: DSMetricSpec, suffix: String? = nil, chart: Bool = true, @ViewBuilder extra: () -> Extra) {
        self.spec = spec
        self.suffix = suffix
        self.chart = chart
        self.top = EmptyView()
        self.extra = extra()
        self.below = EmptyView()
    }
}

// MARK: - Small pieces

/// Card title inside a card ("Horas de sueño", "Anoche, cuándo") with an optional grey note on the right.
struct SuenoCardTitle: View {
    let title: String
    var note: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).dsFont(17, .semibold, relativeTo: .headline).foregroundStyle(DS.t2)
            Spacer(minLength: 8)
            if let note { Text(note).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t3).lineLimit(1) }
        }
    }
}

/// Times under a night strip: bold start and end, grey even hours in between.
struct NightAxis: View {
    let start: Int
    let end: Int

    var body: some View {
        GeometryReader { g in
            let span = Double(max(end - start, 1))
            ZStack(alignment: .topLeading) {
                ForEach(marks, id: \.self) { t in
                    let x = g.size.width * CGFloat(Double(t - start) / span)
                    Text(DSFmt.hour(t)).dsFont(12, .medium, relativeTo: .caption1).foregroundStyle(DS.t3)
                        .fixedSize().position(x: x, y: 8)
                }
                Text(SFmt.clock(start)).dsFont(12, .bold, relativeTo: .caption1).foregroundStyle(DS.t1)
                    .fixedSize().position(x: 18, y: 8)
                Text(SFmt.clock(end)).dsFont(12, .bold, relativeTo: .caption1).foregroundStyle(DS.t1)
                    .fixedSize().position(x: g.size.width - 18, y: 8)
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    /// Every other hour, away from the edges.
    private var marks: [Int] {
        let cal = Calendar.current
        guard var t = cal.nextDate(after: Date(timeIntervalSince1970: TimeInterval(start + 45 * 60)), matching: DateComponents(minute: 0),
                                   matchingPolicy: .nextTime) else { return [] }
        var out: [Int] = []
        while Int(t.timeIntervalSince1970) < end - 45 * 60 {
            if cal.component(.hour, from: t) % 2 == 1 { out.append(Int(t.timeIntervalSince1970)) }
            t = t.addingTimeInterval(3600)
        }
        return out
    }
}

/// Minutes of one stage (or asleep / awake) across the night: filled runs on a hatched track.
struct SuenoStageStrip: View {
    let session: SleepSession
    /// Which minutes are filled.
    let filled: (SleepStage) -> Bool
    var color: Color = DS.sueno
    var height: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let n = max(1, session.stages.count)
            let w = geo.size.width / CGFloat(n)
            ZStack(alignment: .leading) {
                Hatch().fill(Color.white.opacity(0.10))
                ForEach(StageRuns.runs(session).filter { filled($0.stage) }) { r in
                    Rectangle().fill(color)
                        .frame(width: max(1.5, CGFloat(r.minutes) * w))
                        .offset(x: CGFloat(r.index) * w)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Where a value sits against tu normal: a short track, the band and a dot (Constantes de la noche).
struct SuenoMiniRange: View {
    let value: Double
    let normal: ClosedRange<Double>
    var color: Color = DS.sueno

    var body: some View {
        GeometryReader { g in
            let w = normal.upperBound - normal.lowerBound
            let lo = min(normal.lowerBound - w, value), hi = max(normal.upperBound + w, value)
            let x = { (v: Double) in g.size.width * CGFloat((v - lo) / max(hi - lo, 0.0001)) }
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fill).frame(height: 3)
                RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(DS.edgeOpacity), lineWidth: 0.6))
                    .frame(width: max(4, x(normal.upperBound) - x(normal.lowerBound)), height: 12)
                    .offset(x: x(normal.lowerBound))
                Circle().fill(color).overlay(Circle().stroke(DS.card, lineWidth: 1.5))
                    .frame(width: 9, height: 9).offset(x: x(value) - 4.5)
            }
            .frame(height: g.size.height)
        }
        .frame(width: 74, height: 14)
        .accessibilityHidden(true)
    }
}

/// Solid identity capsule (the one primary action of a sheet: «Me voy a dormir»).
struct SuenoSolidButtonStyle: ButtonStyle {
    var tint: Color = DS.sueno

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsFont(19, .semibold)
            .foregroundStyle(DS.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(tint, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// «– | +» stepper of the DS lists.
struct SuenoStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack(spacing: 0) {
            Button { value = max(range.lowerBound, value - step) } label: {
                Image(systemName: "minus").frame(width: 46, height: 32).contentShape(Rectangle())
            }
            .disabled(value <= range.lowerBound)
            Rectangle().fill(DS.sep).frame(width: 0.5, height: 18)
            Button { value = min(range.upperBound, value + step) } label: {
                Image(systemName: "plus").frame(width: 46, height: 32).contentShape(Rectangle())
            }
            .disabled(value >= range.upperBound)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(DS.t1)
        .buttonStyle(.plain)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Lays children left to right and wraps (journal chips).
struct SuenoFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 340
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Seven (or thirty) nights of hours as bars over the «tu normal» band, the shown night in violet.
struct SuenoNightBars: View {
    struct Bar: Identifiable {
        let day: String
        let minutes: Double?
        var mark: Double?
        var id: String { day }
    }

    let bars: [Bar]
    var normal: ClosedRange<Double>?
    var highlight: String?
    /// White tick per bar (need).
    var showMarks = false
    var height: CGFloat = 150

    var body: some View {
        let vals = bars.compactMap(\.minutes) + bars.compactMap(\.mark) + [normal?.lowerBound, normal?.upperBound].compactMap { $0 }
        let lo = max(0, ((vals.min() ?? 360) - 90) / 60).rounded(.down) * 60
        let hi = (((vals.max() ?? 480) + 30) / 60).rounded(.up) * 60
        Chart {
            if let n = normal {
                RectangleMark(yStart: .value("Bajo", n.lowerBound), yEnd: .value("Alto", n.upperBound))
                    .foregroundStyle(DS.sueno.opacity(DS.bandOpacity + 0.05))
                    .annotation(position: .overlay, alignment: .topTrailing, spacing: 0) {
                        Text("tu normal").dsFont(11, .semibold, relativeTo: .caption2).foregroundStyle(DS.sueno)
                            .padding(.trailing, 4).padding(.top, -15)
                    }
            }
            ForEach(bars) { b in
                if let m = b.minutes {
                    BarMark(x: .value("Noche", b.day), yStart: .value("Base", lo), yEnd: .value("Horas", m), width: .ratio(bars.count > 10 ? 0.6 : 0.5))
                        .foregroundStyle(b.day == highlight ? DS.sueno : DS.fill2)
                        .cornerRadius(bars.count > 10 ? 2 : 5)
                }
                if showMarks, let k = b.mark {
                    PointMark(x: .value("Noche", b.day), y: .value("Necesitabas", k))
                        .symbol { Capsule().fill(DS.t1).frame(width: bars.count > 10 ? 6 : 22, height: 2.5) }
                }
            }
        }
        .chartYScale(domain: lo...max(hi, lo + 60))
        .chartXScale(domain: bars.map(\.day))
        .chartYAxis {
            AxisMarks(position: .trailing, values: Array(stride(from: lo, through: hi, by: 60))) { v in
                AxisGridLine().foregroundStyle(DS.sep)
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text("\(Int(d / 60)) h").dsFont(11, .medium).foregroundStyle(DS.t3) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: bars.count > 10 ? [] : bars.map(\.day)) { v in
                AxisValueLabel {
                    if let k = v.as(String.self) {
                        Text(SFmt.weekdayLetter(k)).dsFont(12, k == highlight ? .bold : .medium)
                            .foregroundStyle(k == highlight ? DS.t1 : DS.t3)
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Horas de cada noche")
    }
}

/// Clock minutes of a timestamp that keep a night together: bedtimes count from 12:00 (23:30 < 00:30).
enum SuenoClock {
    static func minutes(_ ts: Int, evening: Bool) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        if evening && m < 12 * 60 { m += 24 * 60 }
        return m
    }

    static func text(_ m: Double) -> String {
        let v = (Int(m.rounded()) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", v / 60, v % 60)
    }

    /// Your usual window (middle half of the 14 nights before `day`); nil with fewer than 4.
    @MainActor
    static func window(_ model: AppModel, evening: Bool, before day: String) -> ClosedRange<Double>? {
        let from = DayKey.shift(day, days: -14)
        let v = model.days.filter { $0.day < day && $0.day >= from }
            .compactMap { evening ? $0.sleepStart : $0.sleepEnd }.map { minutes($0, evening: evening) }.sorted()
        guard v.count >= 4 else { return nil }
        let q = { (p: Double) in v[min(v.count - 1, max(0, Int((Double(v.count - 1) * p).rounded())))] }
        return q(0.25)...max(q(0.75), q(0.25) + 10)
    }
}

/// "Te acostaste ▭•  14 min tarde": where the night fell against your usual window.
struct SuenoTimingRow: View {
    let title: String
    let actual: Double
    let window: ClosedRange<Double>

    private var verdict: (text: String, color: Color) {
        let late = actual - window.upperBound, early = window.lowerBound - actual
        if late > 0 { return ("\(DSFmt.duration(late)) tarde", DSLevel.justa.ink) }
        if early > 0 { return ("\(DSFmt.duration(early)) antes", DS.t2) }
        return ("en tu hora", DSLevel.buena.ink)
    }

    var body: some View {
        let v = verdict
        HStack(spacing: 12) {
            Text(title).dsFont(15, .medium).foregroundStyle(DS.t1).frame(width: 108, alignment: .leading)
            GeometryReader { g in
                let lo = min(window.lowerBound - 60, actual - 15), hi = max(window.upperBound + 60, actual + 15)
                let x = { (m: Double) in g.size.width * CGFloat((m - lo) / (hi - lo)) }
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill).frame(height: 3)
                    RoundedRectangle(cornerRadius: 3).fill(DS.sueno.opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(DS.sueno.opacity(DS.edgeOpacity), lineWidth: 0.6))
                        .frame(width: max(4, x(window.upperBound) - x(window.lowerBound)), height: 12)
                        .offset(x: x(window.lowerBound))
                    Circle().fill(DS.sueno).overlay(Circle().stroke(DS.card, lineWidth: 1.5))
                        .frame(width: 9, height: 9).offset(x: x(actual) - 4.5)
                }
                .frame(height: g.size.height)
            }
            .frame(height: 14)
            Text(v.text).dsFont(15, .semibold).foregroundStyle(v.color).lineLimit(1).minimumScaleFactor(0.8)
                .frame(minWidth: 86, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(v.text)
    }
}

/// A violet pill with a nap's duration ("☾ 0:22").
struct SuenoNapPill: View {
    let minutes: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "moon.fill").font(.system(size: 13))
            Text(String(format: "%d:%02d", Int(minutes.rounded()) / 60, Int(minutes.rounded()) % 60)).dsFont(17, .semibold)
        }
        .foregroundStyle(DS.t1)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(DS.sueno.opacity(DS.tintOpacity), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// A daytime sleep row: pill, kind, «Auto» while unconfirmed, start and end on the right.
struct SuenoNapRow: View {
    let nap: SleepSession

    var body: some View {
        HStack(spacing: 12) {
            SuenoNapPill(minutes: nap.asleepMinutes)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(nap.isNap ? "Siesta" : "Sueño").dsFont(16, .semibold).foregroundStyle(DS.t1)
                    if !nap.kindConfirmed {
                        Text("Auto").dsFont(12, .semibold).foregroundStyle(DS.t2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(DS.fill, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
                Text(nap.isNap ? "baja tu necesidad de esta noche" : "cuenta en tus horas")
                    .dsFont(13).foregroundStyle(DS.t2).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(SFmt.clock(nap.start))
                Text(SFmt.clock(nap.end))
            }
            .dsFont(14).foregroundStyle(DS.t2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
