import SwiftUI
import Charts

// The metric-detail template of the redesign (studio A-hoy 01/05, B-sueno 03-09, C 50-54, D 22-23, E 05):
//   1. DS nav bar «‹ Parent · Title · subtitle»
//   2. hero: big value + unit, level word (dot, 4-step meter for scores), delta, side table «Tu normal / Ayer»,
//      optional message and optional range bar («Tus límites…»)
//   3. `extra`: the metric's own card(s), if any
//   4. chart card: 7 d / 30 d / 6 m, «tu normal» band, mean line, tooltip pill while scrubbing, stat strip
//   5. optional «Qué lo mueve» rows (divergent bars)
//   6. «Qué es»
// It only draws what it is given: nil / empty parts are left out (never sample numbers).

/// A period of the chart selector. The standard three are `.week`, `.month`, `.halfYear`; a metric can use others
/// (battery: 24 h / 7 d / 30 d).
struct DSPeriod: Hashable, Identifiable {
    let id: String
    let label: String
    /// Days covered (1 for 24 h).
    let days: Int

    static let day = DSPeriod(id: "1d", label: "24 h", days: 1)
    static let week = DSPeriod(id: "7d", label: "7 d", days: 7)
    static let month = DSPeriod(id: "30d", label: "30 d", days: 30)
    static let halfYear = DSPeriod(id: "6m", label: "6 m", days: 182)
    static let standard: [DSPeriod] = [.week, .month, .halfYear]
}

struct DSPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// One «Qué lo mueve» row: what moves the metric in you and how much (effect −1…1: left lowers it, right raises it).
struct DSFactor: Identifiable {
    let icon: String
    var iconColor: Color = DS.t2
    let title: String
    var subtitle: String?
    let effect: Double
    /// "Moderada", "+1,2", "−0,4 años"…
    let word: String
    var id: String { title }
}

/// Everything the template draws. Build it from real data; leave out what doesn't exist.
struct DSMetricSpec {
    var title: String
    var subtitle: String?
    var back: String?
    /// Identity colour of the line, band and dots.
    var color: Color = DS.recarga

    // Hero.
    var value: String
    var unit: String = ""
    var level: DSLevel?
    var levelText: String?
    var meter = false
    var delta: String?
    var deltaUp: Bool?
    var side: [(String, String)] = []
    var message: String?
    var rangeTitle: String?
    var rangeBar: DSRangeBar?

    // Chart.
    var periods: [DSPeriod] = DSPeriod.standard
    var initialPeriod: DSPeriod = .month
    var series: [DSPeriod: [DSPoint]] = [:]
    var normal: ClosedRange<Double>?
    var mean: Double?
    var yDomain: ClosedRange<Double>?
    /// Axis and tooltip format.
    var format: (Double) -> String = { DSFmt.thousands($0) }
    /// Unit next to the stat-strip values.
    var statUnit: String = ""
    /// "días" / "noches".
    var unitWord = "días"
    /// Label of the last point ("Hoy", "Anoche").
    var endLabel = "Hoy"
    /// Word for out-of-normal points in the legend ("Fuera", "Baja").
    var outWord = "Fuera"

    // Below.
    var factorsTitle = "Qué lo mueve en ti"
    var factorsNote: String?
    var factorsAxis: (String, String) = ("La baja", "La sube")
    var factors: [DSFactor] = []
    var whatIs: String?
    var footnote: String? = "No es un dispositivo médico."
}

struct DSMetricDetail<Extra: View>: View {
    let spec: DSMetricSpec
    @ViewBuilder var extra: Extra

    init(spec: DSMetricSpec, @ViewBuilder extra: () -> Extra) {
        self.spec = spec
        self.extra = extra()
    }

    var body: some View {
        DSScreen(spec.title, subtitle: spec.subtitle, back: spec.back) {
            DSMetricHero(spec: spec)
            extra
            if spec.series.values.contains(where: { !$0.isEmpty }) {
                DSMetricChartCard(spec: spec)
            }
            if !spec.factors.isEmpty {
                DSSectionHeader(spec.factorsTitle, note: spec.factorsNote)
                DSFactorList(factors: spec.factors, axis: spec.factorsAxis)
            }
            if let text = spec.whatIs {
                DSSectionHeader("Qué es")
                DSWhatIs(text: text, footnote: spec.footnote)
            }
        }
    }
}

extension DSMetricDetail where Extra == EmptyView {
    init(spec: DSMetricSpec) {
        self.init(spec: spec) { EmptyView() }
    }
}

// MARK: - Hero

struct DSMetricHero: View {
    let spec: DSMetricSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(spec.value).dsFont(52, .semibold, relativeTo: .largeTitle, maxScale: 1.15)
                            .foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.5)
                        if !spec.unit.isEmpty {
                            Text(spec.unit).dsFont(18, .medium).foregroundStyle(DS.t2).lineLimit(1)
                        }
                    }
                    if let level = spec.level {
                        DSLevelWord(level: level, text: spec.levelText, meter: spec.meter)
                    } else if let text = spec.levelText {
                        Text(text).dsFont(15, .semibold).foregroundStyle(DS.t2)
                    }
                    if let delta = spec.delta {
                        DSDelta(text: delta, up: spec.deltaUp, color: spec.level?.ink ?? DS.t2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if !spec.side.isEmpty {
                    DSSideTable(rows: spec.side).padding(.top, 8)
                }
            }
            if let message = spec.message {
                DSDivider().padding(.top, 12)
                Text(message).dsFont(15).foregroundStyle(DS.t1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 11)
            }
            if let bar = spec.rangeBar {
                DSDivider().padding(.top, 14)
                if let t = spec.rangeTitle {
                    Text(t).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2).padding(.top, 12)
                }
                bar.padding(.top, 10)
            }
        }
        .dsCard(padding: 14)
    }
}

// MARK: - Chart card

struct DSMetricChartCard: View {
    let spec: DSMetricSpec
    @State private var period: DSPeriod
    @State private var selection: Date?

    init(spec: DSMetricSpec) {
        self.spec = spec
        _period = State(initialValue: spec.periods.contains(spec.initialPeriod) ? spec.initialPeriod : (spec.periods.first ?? .month))
    }

    private var points: [DSPoint] { spec.series[period] ?? [] }

    var body: some View {
        let pts = points
        VStack(alignment: .leading, spacing: 10) {
            if spec.periods.count > 1 {
                DSSegmented(options: spec.periods.map { ($0, $0.label) }, selection: $period)
                    .frame(width: CGFloat(56 * spec.periods.count))
                    .onChange(of: period) { _, _ in selection = nil }
            }
            legend
            if pts.isEmpty {
                Text("Sin datos en este periodo").dsFont(13).foregroundStyle(DS.t3)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                DSLineChart(points: pts, color: spec.color, normal: spec.normal, mean: spec.mean, domain: spec.yDomain,
                            format: spec.format, selection: $selection)
                    .frame(height: 190)
                xLabels(pts)
                DSDivider().padding(.top, 2)
                DSStatStrip(stats: stats(pts)).padding(.top, 2)
            }
        }
        .dsCard(padding: 14)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            if spec.normal != nil {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(spec.color.opacity(0.30))
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(spec.color.opacity(DS.edgeOpacity), lineWidth: 0.5))
                        .frame(width: 14, height: 9)
                    Text("Tu normal")
                }
            }
            if spec.mean != nil {
                HStack(spacing: 6) {
                    Text("---").tracking(-1).foregroundStyle(DS.t2)
                    Text("Media")
                }
            }
            if spec.normal != nil {
                HStack(spacing: 6) {
                    Circle().strokeBorder(DS.justa, lineWidth: 1.5).frame(width: 9, height: 9)
                    Text(spec.outWord)
                }
            }
        }
        .dsFont(13, relativeTo: .footnote)
        .foregroundStyle(DS.t2)
        .accessibilityHidden(true)
    }

    private func xLabels(_ pts: [DSPoint]) -> some View {
        let n = period.days
        let left: String, mid: String
        if period.days >= 90 {
            left = DSFmt.monthName(pts.first?.date)
            mid = DSFmt.monthName(pts[pts.count / 2].date)
        } else if period.days == 1 {
            left = pts.first.map { DSFmt.clock($0.date) } ?? ""
            mid = DSFmt.clock(pts[pts.count / 2].date)
        } else {
            left = "Hace \(n) \(spec.unitWord)"
            mid = "Hace \(n / 2) \(spec.unitWord)"
        }
        return HStack {
            Text(left)
            Spacer()
            Text(mid)
            Spacer()
            Text(spec.endLabel).foregroundStyle(DS.t1).fontWeight(.bold)
        }
        .dsFont(13, relativeTo: .footnote)
        .foregroundStyle(DS.t2)
        .padding(.trailing, 34)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private func stats(_ pts: [DSPoint]) -> [DSStat] {
        let values = pts.map(\.value)
        var out: [DSStat] = []
        if let hi = values.max() { out.append(DSStat(label: "Más alta", value: spec.format(hi), unit: spec.statUnit)) }
        if let lo = values.min() { out.append(DSStat(label: "Más baja", value: spec.format(lo), unit: spec.statUnit)) }
        if let band = spec.normal {
            let inside = values.filter { band.contains($0) }.count
            out.append(DSStat(label: "En tu normal", value: "\(inside)", unit: "de \(values.count) \(spec.unitWord)"))
        }
        return out
    }
}

/// Line chart with the «tu normal» band, a dotted mean, open dots for points out of the band, a filled dot on the
/// last point, and a tooltip pill + rule while scrubbing (`ChartScrub`). Y axis on the right.
struct DSLineChart: View {
    let points: [DSPoint]
    var color: Color = DS.recarga
    var normal: ClosedRange<Double>?
    var mean: Double?
    var domain: ClosedRange<Double>?
    var format: (Double) -> String = { DSFmt.thousands($0) }
    @Binding var selection: Date?

    private var yDomain: ClosedRange<Double> {
        if let domain { return domain }
        var vals = points.map(\.value)
        if let n = normal { vals += [n.lowerBound, n.upperBound] }
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let pad = max((hi - lo) * 0.18, abs(hi) * 0.02, 0.5)
        return (lo - pad)...(hi + pad)
    }

    private var selected: DSPoint? {
        guard let selection else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }

    var body: some View {
        let dom = yDomain
        let first = points.first?.date ?? Date(), last = points.last?.date ?? Date()
        Chart {
            if let n = normal {
                RectangleMark(xStart: .value("Desde", first), xEnd: .value("Hasta", last),
                              yStart: .value("Bajo", max(n.lowerBound, dom.lowerBound)),
                              yEnd: .value("Alto", min(n.upperBound, dom.upperBound)))
                    .foregroundStyle(color.opacity(DS.bandOpacity + 0.05))
            }
            if let mean {
                RuleMark(y: .value("Media", mean))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(DS.t2.opacity(0.7))
            }
            ForEach(points) { p in
                AreaMark(x: .value("Día", p.date), yStart: .value("Base", dom.lowerBound), yEnd: .value("Valor", p.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [color.opacity(DS.areaOpacity), color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Día", p.date), y: .value("Valor", p.value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(color)
            }
            if let n = normal, points.count <= 60 {
                ForEach(points.filter { !n.contains($0.value) }) { p in
                    PointMark(x: .value("Día", p.date), y: .value("Valor", p.value))
                        .symbol {
                            Circle().strokeBorder(p.value < n.lowerBound && p.value < (n.lowerBound - (n.upperBound - n.lowerBound) * 0.5)
                                                  ? DS.baja : DS.justa, lineWidth: 2)
                                .background(Circle().fill(DS.card))
                                .frame(width: 11, height: 11)
                        }
                }
            }
            if let p = points.last {
                PointMark(x: .value("Día", p.date), y: .value("Valor", p.value))
                    .symbol { Circle().fill(color).overlay(Circle().stroke(DS.card, lineWidth: 2)).frame(width: 10, height: 10) }
            }
            if let s = selected {
                RuleMark(x: .value("Día", s.date))
                    .foregroundStyle(DS.t2.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(DSFmt.dayMonth(s.date)) · \(format(s.value))")
                            .dsFont(15, .semibold)
                            .foregroundStyle(DS.bg)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(DS.t1, in: Capsule())
                    }
                PointMark(x: .value("Día", s.date), y: .value("Valor", s.value))
                    .symbol { Circle().strokeBorder(color, lineWidth: 2.5).background(Circle().fill(DS.card)).frame(width: 14, height: 14) }
            }
        }
        .chartYScale(domain: dom)
        .chartXScale(domain: first...max(last, first.addingTimeInterval(1)))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(DS.sep)
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(format(d)).dsFont(11, .medium).foregroundStyle(DS.t3) }
                }
            }
        }
        .chartScrub($selection)
        .padding(.top, 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gráfica")
        .accessibilityValue(points.last.map { "Último valor \(format($0.value))" } ?? "")
    }
}

// MARK: - Qué lo mueve / Qué es

/// «Qué lo mueve en ti»: one row per factor with a divergent bar around a centre tick and the strength word.
struct DSFactorList: View {
    let factors: [DSFactor]
    var axis: (String, String) = ("La baja", "La sube")

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrowtriangle.left.fill").font(.system(size: 7))
                        Text(axis.0)
                    }
                    HStack(spacing: 3) {
                        Text(axis.1)
                        Image(systemName: "arrowtriangle.right.fill").font(.system(size: 7))
                    }
                }
                .lineLimit(1)
                .frame(width: 140)
                Spacer().frame(width: 48)
            }
            .dsFont(12, .medium, relativeTo: .caption1)
            .foregroundStyle(DS.t2)
            .padding(.top, 10)
            .padding(.bottom, 2)
            ForEach(factors.indices, id: \.self) { i in
                if i > 0 { DSDivider(inset: 32) }
                row(factors[i])
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity)
        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }

    private func row(_ f: DSFactor) -> some View {
        HStack(spacing: 10) {
            Image(systemName: f.icon).font(.system(size: 15)).foregroundStyle(f.iconColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(f.title).dsFont(15, .medium).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                if let s = f.subtitle { Text(s).dsFont(13).foregroundStyle(DS.t2).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DSDivergentBar(effect: f.effect).frame(width: 84, height: 14)
            Text(f.word).dsFont(13, .semibold).foregroundStyle(DS.t2).frame(width: 76, alignment: .trailing)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }
}

/// Bar growing left (lowers, red) or right (raises, green) from a centre tick. effect −1…1.
struct DSDivergentBar: View {
    let effect: Double

    var body: some View {
        GeometryReader { g in
            let half = g.size.width / 2
            let w = half * CGFloat(min(abs(effect), 1))
            ZStack(alignment: .leading) {
                Rectangle().fill(DS.sep).frame(height: 1).frame(maxHeight: .infinity)
                RoundedRectangle(cornerRadius: 2).fill(effect < 0 ? DS.baja : DS.buena)
                    .frame(width: max(w, 3), height: 8)
                    .offset(x: effect < 0 ? half - w : half)
                Rectangle().fill(DS.t2).frame(width: 1.5, height: 14).offset(x: half - 0.75)
            }
        }
        .accessibilityHidden(true)
    }
}

/// «Qué es»: two or three plain sentences and a grey footnote.
struct DSWhatIs: View {
    let text: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).dsFont(15).foregroundStyle(DS.t1).fixedSize(horizontal: false, vertical: true)
            if let footnote {
                Text(footnote).dsFont(12, relativeTo: .caption1).foregroundStyle(DS.t3)
            }
        }
        .dsCard(padding: 14)
    }
}

// Level mark colours as DS tokens (for charts and bars).
extension DS {
    static let baja = DSLevel.baja.mark
    static let justa = DSLevel.justa.mark
    static let buena = DSLevel.buena.mark
    static let excelente = DSLevel.excelente.mark
}

extension DSFmt {
    /// "8 nov".
    static func dayMonth(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    /// "jun".
    static func monthName(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    /// "07:24".
    static func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
