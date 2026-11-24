import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// 10 Estrés: the latest reading on the 0–3 scale, the day's mean and peak, the curve of the day with sleep and
/// workouts shaded, time per level against a usual day, where the high stress came from, the week and guided breathing.
struct HoyEstresView: View {
    @EnvironmentObject var model: AppModel
    @State private var period: DSPeriod = .week
    @State private var selected: Int?

    var body: some View {
        let day = model.selected
        DSScreen("Estrés", subtitle: DSFmt.shortDate(model.selectedDay), back: "Hoy") {
            if let d = day, let raw = Optional(model.hoyStressPoints(for: d)), !raw.isEmpty {
                hero(d, raw)
                DSSectionHeader(model.isOpenCycle(d) ? "Últimas 24 h" : "El día")
                HoyStressDayChart(day: d, raw: raw)
                levels(d)
                split(d)
                week(d)
            } else {
                DSEmptyState(icon: "wind", title: "Sin estrés", message: "Se calcula minuto a minuto con la pulsera puesta.")
            }
            RouteLink(.actividad(.respiraDetalle(.coherence))) {
                HoyLinkCard(icon: "wind", iconColor: DS.recarga, title: "Respiración guiada", subtitle: "Coherencia, 4-7-8, suspiro")
            }
            DSSectionHeader("Qué es")
            DSWhatIs(text: "De 0 a 3, minuto a minuto: el pulso que tu movimiento no explica, frente a tu calma de las dos últimas semanas. Ni bueno ni malo: lo que importa es que haya momentos de calma.",
                     footnote: nil)
        }
    }

    private func hero(_ d: DaySummary, _ raw: [(ts: Int, v: Double)]) -> some View {
        let v = raw.last?.v ?? 0
        let daily = model.stressDaily(for: d)
        var side: [(String, String)] = []
        if let avg = daily?.avg ?? d.stressAvg { side.append(("Media de hoy", Fmt.dec(avg))) }
        if let mx = raw.map(\.v).max() { side.append(("Máximo", Fmt.dec(mx))) }
        let now = model.isOpenCycle(d)
        return HoyHero(value: Fmt.dec(v), side: side) {
            HStack(spacing: 6) {
                Circle().fill(HoyStress.mark(v)).frame(width: 8, height: 8)
                Text(HoyStress.word(v)).dsFont(17, .semibold).foregroundStyle(HoyStress.color(v))
            }
            Text(now ? "ahora" : "a las \(Fmt.time(raw.last?.ts))").dsFont(15).foregroundStyle(DS.t2)
        } footer: {
            HoyStressScale(value: v).padding(.top, 16)
        }
    }

    @ViewBuilder
    private func levels(_ d: DaySummary) -> some View {
        if let daily = model.stressDaily(for: d), daily.counted > 0 {
            let now = daily.levelMinutes.map(Double.init)
            let usualDays = (1...4).compactMap { model.day(DayKey.shift(d.day, days: -7 * $0)) }.compactMap { model.stressDaily(for: $0) }
                .filter { $0.counted > 0 }
            let usual: [Double]? = usualDays.isEmpty ? nil
                : (0..<3).map { i in usualDays.map { Double($0.levelMinutes[i]) }.reduce(0, +) / Double(usualDays.count) }
            DSSectionHeader("Tiempo por nivel")
            VStack(alignment: .leading, spacing: 8) {
                Text("Despierto, sin entrenos ni la hora y media de después").dsFont(13).foregroundStyle(DS.t2)
                HoyLevelBar(parts: now, colors: [DS.buena, DS.bien, DS.justa], height: 10)
                if let usual {
                    HoyLevelBar(parts: usual, colors: [DS.buena, DS.bien, DS.justa].map { $0.opacity(0.5) }, height: 5)
                    HStack {
                        Text("Hoy")
                        Spacer()
                        Text("Un día habitual")
                    }
                    .dsFont(12, relativeTo: .caption1).foregroundStyle(DS.t3)
                }
                DSDivider().padding(.vertical, 4)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        levelStat(i, now[i], usual?[i])
                    }
                }
            }
            .dsCard(padding: 14)
        }
    }

    private func levelStat(_ i: Int, _ m: Double, _ usual: Double?) -> some View {
        let names = ["Calma", "Medio", "Alto"], colors = [DS.buena, DS.bien, DS.justa]
        let p = DSFmt.durationParts(m)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(colors[i]).frame(width: 7, height: 7)
                Text(names[i]).dsFont(13).foregroundStyle(DS.t2)
            }
            HoyValue(value: p.0, unit: p.1, size: 20)
            if let u = usual, u > 0 {
                let pct = Int((abs(m - u) / u * 100).rounded())
                let up = m > u
                // More calm is good; more medium or high is not.
                let good = i == 0 ? up : !up
                DSDelta(text: "\(pct) %", up: up, color: good ? DSLevel.buena.ink : DSLevel.justa.ink)
            }
        }
        .padding(.leading, i == 0 ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(DS.sep).frame(width: 0.5) } }
    }

    @ViewBuilder
    private func split(_ d: DaySummary) -> some View {
        if let s = model.stressSplit(for: d), s.total > 0 {
            let parts: [(String, Int, Color)] = [("Sin relación", s.other, DS.justa), ("Al despertar", s.waking, DS.sueno),
                                                 ("En el entreno", s.activity, DS.act), ("Dormido", s.asleep, DS.stDeep)]
                .filter { $0.1 > 0 }
            DSSectionHeader("De dónde vino el estrés alto")
            VStack(alignment: .leading, spacing: 12) {
                HoyLevelBar(parts: parts.map { Double($0.1) }, colors: parts.map(\.2), height: 8)
                DSDivider()
                DSStatStrip(stats: parts.map { p in
                    let v = DSFmt.durationParts(Double(p.1))
                    return DSStat(label: p.0, value: v.0, unit: v.1)
                })
            }
            .dsCard(padding: 14)
        }
    }

    @ViewBuilder
    private func week(_ d: DaySummary) -> some View {
        let bars = HoyBarSeries.bars(model.days, end: d.day, period: period) { $0.stressAvg }
        if bars.contains(where: { $0.value != nil }) {
            let range = model.days.filter { $0.day <= d.day && $0.day > DayKey.shift(d.day, days: -period.days) }
            let withAvg = range.filter { $0.stressAvg != nil }
            let hi = withAvg.max { ($0.stressAvg ?? 0) < ($1.stressAvg ?? 0) }
            let lo = withAvg.min { ($0.stressAvg ?? 0) < ($1.stressAvg ?? 0) }
            let high = range.compactMap(\.stressHighMinutes)
            DSSectionHeader("Tu semana")
            VStack(alignment: .leading, spacing: 14) {
                DSSegmented(options: DSPeriod.standard.map { ($0, $0.label) }, selection: $period).frame(width: 168)
                HoyBars(bars: bars, color: DS.bien, lastColor: (bars.last?.value).map(HoyStress.mark), maxValue: 2,
                        axis: [1, 2], format: { "\(Int($0))" }, height: 110)
                DSDivider()
                DSStatStrip(stats: weekStats(hi, lo, high))
            }
            .dsCard(padding: 14)
        }
    }

    private func weekStats(_ hi: DaySummary?, _ lo: DaySummary?, _ high: [Double]) -> [DSStat] {
        var out: [DSStat] = []
        if let hi { out.append(DSStat(label: "Más alto, \(weekday(hi.day))", value: Fmt.dec(hi.stressAvg))) }
        if let lo { out.append(DSStat(label: "Más bajo, \(weekday(lo.day))", value: Fmt.dec(lo.stressAvg))) }
        if !high.isEmpty {
            let p = DSFmt.durationParts(high.reduce(0, +) / Double(high.count))
            out.append(DSStat(label: "Alto al día", value: p.0, unit: p.1))
        }
        return out
    }

    private func weekday(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }
}

/// Parts of a whole as one row of capsules.
struct HoyLevelBar: View {
    let parts: [Double]
    let colors: [Color]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { g in
            let total = max(parts.reduce(0, +), 0.0001)
            let n = CGFloat(parts.filter { $0 > 0 }.count)
            HStack(spacing: 3) {
                ForEach(parts.indices, id: \.self) { i in
                    if parts[i] > 0 {
                        Capsule().fill(colors[i]).frame(width: max(4, (g.size.width - 3 * max(n - 1, 0)) * CGFloat(parts[i] / total)))
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// The 0–3 scale: Calma / Medio / Alto with the reading as a dot.
struct HoyStressScale: View {
    let value: Double

    var body: some View {
        VStack(spacing: 6) {
            DSRangeBar(stretches: [.init(to: 1 / 3, color: DS.buena), .init(to: 2 / 3, color: DS.bien), .init(to: 1, color: DS.justa)],
                       marker: min(max(value / 3, 0), 1), markerColor: HoyStress.mark(value))
            HStack(spacing: 0) {
                ForEach(["Calma", "Medio", "Alto"], id: \.self) { Text($0).frame(maxWidth: .infinity) }
            }
            .dsFont(12, .medium, relativeTo: .caption1).foregroundStyle(DS.t3)
        }
    }
}

/// The day's stress curve (5-minute means) with the night and the workouts shaded and a pill while scrubbing.
struct HoyStressDayChart: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary
    let raw: [(ts: Int, v: Double)]
    @State private var selection: Int?

    private struct P: Identifiable {
        let x: Int
        let v: Double
        var id: Int { x }
    }

    var body: some View {
        let w = model.hoyStressWindow(for: day)
        let pts = bucketed(w.start)
        let now = Int(Date().timeIntervalSince1970)
        let nowX = now > w.start && now < w.end ? (now - w.start) / 60 : nil
        let sleep: (Int, Int)? = {
            guard let a = day.sleepStart, let b = day.sleepEnd else { return nil }
            let s = max(0, (a - w.start) / 60), e = min(1440, (b - w.start) / 60)
            return e > s ? (s, e) : nil
        }()
        let workouts = model.workouts(for: day).map { (max(0, ($0.start - w.start) / 60), min(1440, ($0.end - w.start) / 60), $0.sport) }
            .filter { $0.1 > $0.0 }
        let sel = selection.flatMap { s in pts.min { abs($0.x - s) < abs($1.x - s) } }
        VStack(spacing: 6) {
            Chart {
                if let sleep {
                    RectangleMark(xStart: .value("a", sleep.0), xEnd: .value("b", sleep.1), yStart: .value("lo", 0), yEnd: .value("hi", 3))
                        .foregroundStyle(DS.sueno.opacity(0.12))
                        .annotation(position: .overlay, alignment: .topLeading) {
                            Text("Sueño").dsFont(11, .semibold, relativeTo: .caption2).foregroundStyle(DS.sueno).padding(4)
                        }
                }
                ForEach(workouts.indices, id: \.self) { i in
                    RectangleMark(xStart: .value("a", workouts[i].0), xEnd: .value("b", workouts[i].1), yStart: .value("lo", 0), yEnd: .value("hi", 3))
                        .foregroundStyle(DS.act.opacity(0.16))
                }
                ForEach([1.0, 2.0], id: \.self) { y in
                    RuleMark(y: .value("n", y)).lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(DS.sep)
                }
                ForEach(pts) { p in
                    LineMark(x: .value("m", p.x), y: .value("v", p.v))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(HoyStress.mark(p.v))
                }
                if let last = pts.last {
                    PointMark(x: .value("m", last.x), y: .value("v", last.v))
                        .symbol { Circle().fill(HoyStress.mark(last.v)).overlay(Circle().stroke(DS.card, lineWidth: 2)).frame(width: 10, height: 10) }
                }
                if let s = sel {
                    RuleMark(x: .value("m", s.x)).foregroundStyle(DS.t2.opacity(0.6))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(label(s.x, start: w.start, workouts: workouts))
                                .dsFont(14, .semibold).foregroundStyle(DS.bg)
                                .padding(.horizontal, 12).frame(height: 28).background(DS.t1, in: Capsule())
                        }
                }
            }
            .chartXScale(domain: 0...1440)
            .chartYScale(domain: 0...3)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0.5, 1.5, 2.5]) { v in
                    AxisValueLabel {
                        Text(["Calma", "Medio", "Alto"][min(2, Int(v.as(Double.self) ?? 0))]).dsFont(11, .medium).foregroundStyle(DS.t3)
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                if let frame = proxy.plotFrame {
                                    let x = v.location.x - g[frame].origin.x
                                    selection = proxy.value(atX: x, as: Int.self)
                                }
                            }
                            .onEnded { _ in selection = nil })
                }
            }
            .padding(.top, 26)
            .frame(height: 170)
            HStack {
                ForEach(["00", "06", "12"], id: \.self) { Text($0).frame(maxWidth: .infinity, alignment: .leading) }
                Text(nowX == nil ? "18" : "Ahora").fontWeight(nowX == nil ? .regular : .bold).foregroundStyle(nowX == nil ? DS.t3 : DS.t1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("24")
            }
            .dsFont(12, .medium, relativeTo: .caption1).foregroundStyle(DS.t3)
            .padding(.trailing, 44)
        }
        .dsCard(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estrés del día")
    }

    private func bucketed(_ start: Int) -> [P] {
        var sums: [Int: (Double, Int)] = [:]
        for p in raw {
            let b = (p.ts - start) / 300
            let s = sums[b] ?? (0, 0)
            sums[b] = (s.0 + p.v, s.1 + 1)
        }
        return sums.keys.sorted().map { P(x: $0 * 5 + 2, v: sums[$0]!.0 / Double(sums[$0]!.1)) }
    }

    private func label(_ x: Int, start: Int, workouts: [(Int, Int, String)]) -> String {
        let t = Fmt.time(start + x * 60)
        if let w = workouts.first(where: { x >= $0.0 && x <= $0.1 }) { return "\(t) · \(w.2)" }
        return t
    }
}
