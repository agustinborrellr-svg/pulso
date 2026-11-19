import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoFeatures

// MARK: - Anoche

/// Last night: the stage curve, the time in each stage, bed and wake times against your usual window, regularity.
struct HoyAnocheBlock: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { SleepDetailView() } label: { HoySectionTitle("Anoche", chevron: true) }.buttonStyle(.plain)
            if let s = model.sleep(for: day), !s.stages.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        StageCurve(session: s).frame(height: 128)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach([SleepStage.awake, .rem, .light, .deep], id: \.self) { st in
                                HStack(spacing: 5) {
                                    HoyDot(color: st == .awake ? Hoy.t3 : Hoy.stage(st))
                                    Text(Theme.stageName(st)).hoyFont(11, .medium, relativeTo: .caption2).foregroundStyle(Hoy.t2)
                                }
                                .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(height: 104)
                        .padding(.top, 2)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    totals(s)
                    Rectangle().fill(Hoy.sep).frame(height: 1)
                    VStack(spacing: 14) {
                        if let w = window(\.sleepStart, before: day) , let a = day.sleepStart {
                            TimingRow(title: "Te acostaste", actual: clock(a, evening: true), window: w)
                        }
                        if let w = window(\.sleepEnd, before: day), let b = day.sleepEnd {
                            TimingRow(title: "Te levantaste", actual: clock(b, evening: false), window: w)
                        }
                        if let reg = day.sleepConsistency {
                            let lv = HoyLevel(score: reg)
                            HStack(spacing: 12) {
                                Text("Regularidad").hoyFont(15, .medium).foregroundStyle(Hoy.t1)
                                Spacer(minLength: 6)
                                HStack(spacing: 3) {
                                    ForEach(1...4, id: \.self) { i in
                                        Capsule().fill(i <= lv.rawValue ? lv.mark : Hoy.fill).frame(width: 22, height: 4)
                                    }
                                }
                                .accessibilityHidden(true)
                                Text("\(Int(reg.rounded())) %").hoyFont(15, .semibold).foregroundStyle(Hoy.t1)
                                    .frame(minWidth: 44, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .hoyCard(padding: 16)
            }
        }
    }

    private func totals(_ s: SleepSession) -> some View {
        let parts: [(SleepStage, Double)] = [(.deep, day.deepMinutes ?? s.minutesDeep), (.rem, day.remMinutes ?? s.minutesREM),
                                             (.light, day.lightMinutes ?? s.minutesLight), (.awake, day.awakeMinutes ?? s.minutesAwake)]
        let total = max(parts.reduce(0) { $0 + $1.1 }, 1)
        return HStack(alignment: .top, spacing: 8) {
            ForEach(parts, id: \.0) { st, m in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        HoyDot(color: st == .awake ? Hoy.t3 : Hoy.stage(st))
                        Text(Theme.stageName(st)).hoyFont(13, relativeTo: .footnote).foregroundStyle(Hoy.t2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    let p = HoyFmt.durationParts(m)
                    HoyValue(value: p.0, unit: p.1, size: 19)
                    Text("\(Int((m / total * 100).rounded())) %").hoyFont(13, relativeTo: .footnote).foregroundStyle(Hoy.t3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Minutes on a clock that keeps a night together: bedtimes count from 12:00 (so 23:30 < 00:30), wake times from 00:00.
    private func clock(_ ts: Int, evening: Bool) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        if evening && m < 12 * 60 { m += 24 * 60 }
        return m
    }

    /// Your usual window (middle half of the last 14 nights before this one); nil with fewer than 4 nights.
    private func window(_ key: KeyPath<DaySummary, Int?>, before d: DaySummary) -> ClosedRange<Double>? {
        let evening = key == \DaySummary.sleepStart
        let from = DayKey.shift(d.day, days: -14)
        let v = model.days.filter { $0.day < d.day && $0.day >= from }.compactMap { $0[keyPath: key] }.map { clock($0, evening: evening) }.sorted()
        guard v.count >= 4 else { return nil }
        let q = { (p: Double) in v[min(v.count - 1, max(0, Int((Double(v.count - 1) * p).rounded())))] }
        return q(0.25)...max(q(0.75), q(0.25) + 10)
    }
}

/// "Te acostaste ▭•  14 min tarde": where tonight fell against your usual window.
private struct TimingRow: View {
    let title: String
    let actual: Double
    let window: ClosedRange<Double>

    private var verdict: (text: String, color: Color) {
        let late = actual - window.upperBound, early = window.lowerBound - actual
        if late > 0 { return ("\(HoyFmt.duration(late)) tarde", HoyLevel.justa.ink) }
        if early > 0 { return ("\(HoyFmt.duration(early)) antes", Hoy.t2) }
        return ("en tu hora", HoyLevel.buena.ink)
    }

    var body: some View {
        let text = verdict.text, color = verdict.color
        HStack(spacing: 12) {
            Text(title).hoyFont(15, .medium).foregroundStyle(Hoy.t1).frame(width: 118, alignment: .leading)
            GeometryReader { g in
                let lo = min(window.lowerBound - 60, actual - 15), hi = max(window.upperBound + 60, actual + 15)
                let x = { (v: Double) in g.size.width * CGFloat((v - lo) / (hi - lo)) }
                ZStack(alignment: .leading) {
                    Capsule().fill(Hoy.fill).frame(height: 3)
                    RoundedRectangle(cornerRadius: 3).fill(Hoy.sueno.opacity(0.28))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Hoy.sueno.opacity(Hoy.edgeOpacity), lineWidth: 0.6))
                        .frame(width: max(4, x(window.upperBound) - x(window.lowerBound)), height: 12)
                        .offset(x: x(window.lowerBound))
                    Circle().fill(Hoy.sueno).overlay(Circle().stroke(Hoy.card, lineWidth: 1.5))
                        .frame(width: 9, height: 9).offset(x: x(actual) - 4.5)
                }
                .frame(height: g.size.height)
            }
            .frame(height: 14)
            Text(text).hoyFont(15, .semibold).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
                .frame(minWidth: 86, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(text)
    }
}

/// The night as one smooth curve of depth (awake at the top, deep at the bottom) over a soft violet fill.
struct StageCurve: View {
    let session: SleepSession

    private struct P: Identifiable {
        let t: Date
        let v: Double
        var id: Date { t }
    }

    /// 5-minute means of the depth, so the curve reads as a wave and not as steps.
    private var points: [P] {
        let depth: (SleepStage) -> Double = { s in
            switch s {
            case .awake: return 3
            case .rem: return 2
            case .light: return 1
            case .deep: return 0
            }
        }
        let step = 5
        return stride(from: 0, to: session.stages.count, by: step).map { i in
            let chunk = session.stages[i..<min(i + step, session.stages.count)]
            let v = chunk.map(depth).reduce(0, +) / Double(chunk.count)
            return P(t: Date(timeIntervalSince1970: TimeInterval(session.start + (i + step / 2) * 60)), v: v)
        }
    }

    var body: some View {
        let pts = points
        Chart {
            ForEach(pts) { p in
                AreaMark(x: .value("Hora", p.t), yStart: .value("Base", -0.3), yEnd: .value("Fase", p.v))
                    .foregroundStyle(LinearGradient(colors: [Hoy.sueno.opacity(0.30), Hoy.sueno.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Hora", p.t), y: .value("Fase", p.v))
                    .foregroundStyle(Hoy.sueno)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: -0.3...3.2)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { v in
                AxisValueLabel {
                    if let d = v.as(Date.self) {
                        Text(HoyFmt.hour(Int(d.timeIntervalSince1970))).hoyFont(12, .medium, relativeTo: .caption1).foregroundStyle(Hoy.t3)
                    }
                }
            }
        }
        .accessibilityLabel("Fases de la noche")
    }
}

// MARK: - Estrés del día

extension AppModel {
    /// The calendar day of a cycle (00:00 to 24:00 of its date).
    func hoyStressWindow(for day: DaySummary) -> (start: Int, end: Int) {
        let start = DayKey.date(day.day).map { Int(Calendar.current.startOfDay(for: $0).timeIntervalSince1970) } ?? 0
        return (start, start + 86_400)
    }

    func hoyStressPoints(for day: DaySummary) -> [(ts: Int, v: Double)] {
        let w = hoyStressWindow(for: day)
        return stressReadings(from: w.start, to: w.end)
    }
}

/// The day's stress as one curve coloured by zone, with the time spent in each.
struct HoyStressBlock: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary
    @State private var selected: Int?

    private struct P: Identifiable {
        let x: Int
        let v: Double
        var id: Int { x }
    }

    var body: some View {
        let w = model.hoyStressWindow(for: day)
        let raw = model.hoyStressPoints(for: day)
        let pts = bucketed(raw, start: w.start)
        let minutes = zoneMinutes(raw)
        let now = Int(Date().timeIntervalSince1970)
        let nowX = now > w.start && now < w.end ? (now - w.start) / 60 : nil
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { StressMonitorView() } label: { HoySectionTitle("Estrés del día", chevron: true) }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 14) {
                chart(pts, w: w, nowX: nowX).frame(height: 150)
                Rectangle().fill(Hoy.sep).frame(height: 1)
                HStack(alignment: .top, spacing: 8) {
                    zone("Calma", minutes.0, HoyLevel.buena)
                    zone("Medio", minutes.1, HoyLevel.justa)
                    zone("Alto", minutes.2, HoyLevel.baja)
                }
            }
            .hoyCard(padding: 16)
        }
    }

    private func zone(_ name: String, _ m: Double, _ lv: HoyLevel) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                HoyDot(color: lv.mark)
                Text(name).hoyFont(13, relativeTo: .footnote).foregroundStyle(Hoy.t2)
            }
            let p = HoyFmt.durationParts(m)
            HoyValue(value: p.0, unit: p.1, size: 19)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 5-minute means (minutes since midnight).
    private func bucketed(_ raw: [(ts: Int, v: Double)], start: Int) -> [P] {
        var sums: [Int: (Double, Int)] = [:]
        for p in raw {
            let b = (p.ts - start) / 300
            let s = sums[b] ?? (0, 0)
            sums[b] = (s.0 + p.v, s.1 + 1)
        }
        return sums.keys.sorted().map { P(x: $0 * 5 + 2, v: sums[$0]!.0 / Double(sums[$0]!.1)) }
    }

    /// Minutes in calm (< 1), medium (1–2) and high (≥ 2); each reading lasts until the next one (at most a minute,
    /// or an hour on days kept as hourly means).
    private func zoneMinutes(_ raw: [(ts: Int, v: Double)]) -> (Double, Double, Double) {
        guard raw.count > 0 else { return (0, 0, 0) }
        let gaps = zip(raw.dropFirst(), raw).map { $0.ts - $1.ts }.sorted()
        let typical = gaps.isEmpty ? 60 : gaps[gaps.count / 2]
        let cap = typical > 90 ? 3600 : 60
        var out = (0.0, 0.0, 0.0)
        for (i, p) in raw.enumerated() {
            let next = i + 1 < raw.count ? raw[i + 1].ts : p.ts + min(typical, cap)
            let m = Double(min(max(next - p.ts, 0), cap)) / 60
            if p.v < 1 { out.0 += m } else if p.v < 2 { out.1 += m } else { out.2 += m }
        }
        return out
    }

    private static func stops(_ lo: Double, _ hi: Double, opacity: Double = 1) -> [Gradient.Stop] {
        let span = max(hi - lo, 0.001)
        func loc(_ v: Double) -> CGFloat { CGFloat(min(max((v - lo) / span, 0), 1)) }
        func color(_ v: Double) -> Color { HoyLevel(stress: v).mark.opacity(opacity) }
        var out: [Gradient.Stop] = [.init(color: color(lo), location: 0)]
        for t in [1.0, 2.0] where t > lo && t < hi {
            out.append(.init(color: color(t - 0.01), location: loc(t)))
            out.append(.init(color: color(t), location: loc(t)))
        }
        out.append(.init(color: color(hi), location: 1))
        return out
    }

    private func chart(_ pts: [P], w: (start: Int, end: Int), nowX: Int?) -> some View {
        let lo = pts.map(\.v).min() ?? 0, hi = pts.map(\.v).max() ?? 0
        let line = LinearGradient(stops: Self.stops(lo, hi), startPoint: .bottom, endPoint: .top)
        let fill = LinearGradient(stops: Self.stops(0, max(hi, 0.01), opacity: 0.16), startPoint: .bottom, endPoint: .top)
        let sleep: (Int, Int)? = {
            guard let a = day.sleepStart, let b = day.sleepEnd else { return nil }
            let s = max(0, (a - w.start) / 60), e = min(1440, (b - w.start) / 60)
            return e > s ? (s, e) : nil
        }()
        let peak = pts.max(by: { $0.v < $1.v }).flatMap { $0.v >= 1.5 ? $0 : nil }
        let workouts = model.workouts(for: day) + (model.day(DayKey.shift(day.day, days: -1)).map { model.workouts(for: $0) } ?? [])
        let shown = selected.flatMap { k in pts.min(by: { abs($0.x - k) < abs($1.x - k) }) } ?? peak
        let xLabels = [0, 360, 720, 1440].filter { v in nowX.map { abs($0 - v) > 150 } ?? true } + (nowX.map { [$0] } ?? [])
        return Chart {
            if let sleep {
                RectangleMark(xStart: .value("Inicio", sleep.0), xEnd: .value("Fin", sleep.1), yStart: .value("a", 0.0), yEnd: .value("b", 3.0))
                    .foregroundStyle(Color.white.opacity(0.04))
                    .annotation(position: .overlay, alignment: .topLeading) {
                        Text("Sueño").hoyFont(11, .semibold, relativeTo: .caption2).foregroundStyle(Hoy.sueno).padding(4)
                    }
            }
            ForEach(pts) { p in
                AreaMark(x: .value("Minuto", p.x), yStart: .value("Base", 0), yEnd: .value("Estrés", p.v))
                    .foregroundStyle(fill)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Minuto", p.x), y: .value("Estrés", p.v))
                    .foregroundStyle(line)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            if let p = shown {
                RuleMark(x: .value("Minuto", p.x), yStart: .value("a", p.v), yEnd: .value("b", 3.0))
                    .foregroundStyle(Hoy.t3.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoyPill(text: label(p, start: w.start, workouts: workouts))
                    }
                PointMark(x: .value("Minuto", p.x), y: .value("Estrés", p.v))
                    .symbol { Circle().stroke(HoyLevel(stress: p.v).mark, lineWidth: 2).background(Circle().fill(Hoy.card)).frame(width: 10, height: 10) }
            }
            if nowX != nil, let last = pts.last {
                PointMark(x: .value("Minuto", last.x), y: .value("Estrés", last.v))
                    .symbol { Circle().fill(HoyLevel(stress: last.v).mark).overlay(Circle().stroke(Hoy.card, lineWidth: 2)).frame(width: 9, height: 9) }
            }
        }
        .chartScrub($selected)
        .chartXScale(domain: 0...1440)
        .chartYScale(domain: 0...3.4)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0.5, 1.5, 2.5]) { v in
                AxisValueLabel {
                    Text(["Calma", "Medio", "Alto"][min(2, Int(v.as(Double.self) ?? 0))])
                        .hoyFont(11, .medium, relativeTo: .caption2).foregroundStyle(Hoy.t3)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xLabels) { v in
                AxisValueLabel {
                    let x = v.as(Int.self) ?? 0
                    if x == nowX {
                        Text("Ahora").hoyFont(12, .bold, relativeTo: .caption1).foregroundStyle(Hoy.t1)
                    } else {
                        Text(String(format: "%02d", x / 60)).hoyFont(12, .medium, relativeTo: .caption1).foregroundStyle(Hoy.t3)
                    }
                }
            }
        }
    }

    private func label(_ p: P, start: Int, workouts: [Workout]) -> String {
        let ts = start + p.x * 60
        let time = Fmt.time(ts)
        if let w = workouts.first(where: { ts >= $0.start - 600 && ts <= $0.end + 1800 }) { return "\(time) · \(w.sport)" }
        if selected != nil { return "\(time) · \(Fmt.dec(p.v))" }
        return time
    }
}

/// Small rounded label over a chart ("08:10 · Carrera").
struct HoyPill: View {
    let text: String

    var body: some View {
        Text(text).hoyFont(12, .semibold, relativeTo: .caption1).foregroundStyle(Hoy.bg)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Hoy.t1, in: Capsule())
            .fixedSize()
    }
}

// MARK: - Tendencias de tu cuerpo

/// One vital at a time over 30 nights, against your normal band.
struct HoyTrendsBlock: View {
    @EnvironmentObject var model: AppModel
    @State private var metric = "hrv"
    @State private var selected: Date?

    static let tabs: [(id: String, label: String)] = [("hrv", "VFC"), ("rhr", "FC rep."), ("resp", "Resp."), ("spo2", "SpO₂"), ("temp", "Temp.")]

    var body: some View {
        let all = model.vitalReadings()
        let tabs = Self.tabs.filter { t in all.contains { $0.id == t.id } }
        VStack(alignment: .leading, spacing: 10) {
            HoySectionTitle("Tendencias de tu cuerpo")
            if let r = all.first(where: { $0.id == metric }) ?? all.first(where: { $0.id == tabs.first?.id }) {
                VStack(alignment: .leading, spacing: 14) {
                    segmented(tabs, current: r.id)
                    content(r)
                }
                .hoyCard(padding: 14)
            }
        }
    }

    private func segmented(_ tabs: [(id: String, label: String)], current: String) -> some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.id) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { metric = t.id }
                } label: {
                    Text(t.label).hoyFont(14, t.id == current ? .semibold : .medium, relativeTo: .subheadline)
                        .foregroundStyle(t.id == current ? Hoy.t1 : Hoy.t2)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(t.id == current ? Hoy.segOn : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(t.id == current ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Hoy.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func color(_ r: VitalReading) -> Color { ["hrv", "rhr"].contains(r.id) ? Hoy.cor : Hoy.cons }

    @ViewBuilder
    private func content(_ r: VitalReading) -> some View {
        let values = r.history.map(\.value)
        let mean = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let unit = r.unit == "%" ? "%" : r.unit
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HoyValue(value: r.value, unit: unit, size: 28)
                if let mean { deltaLine(r, mean: mean) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 4) {
                if let range = r.range {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(color(r).opacity(Hoy.bandOpacity))
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(color(r).opacity(Hoy.edgeOpacity), lineWidth: 0.6))
                            .frame(width: 14, height: 9)
                        Text("Tu normal \(r.format(range.lowerBound))–\(r.format(range.upperBound))")
                            .hoyFont(12, relativeTo: .caption1).foregroundStyle(Hoy.t2)
                    }
                }
                if let mean {
                    HStack(spacing: 6) {
                        Rectangle().fill(Hoy.t3).frame(width: 14, height: 1).mask(HStack(spacing: 2) { ForEach(0..<4, id: \.self) { _ in Rectangle() } })
                        Text("Media \(r.format(mean))").hoyFont(12, relativeTo: .caption1).foregroundStyle(Hoy.t2)
                    }
                }
            }
        }
        if r.history.count >= 2 {
            chart(r, mean: mean).frame(height: 132)
            HStack {
                Text("Hace 30 días")
                Spacer()
                Text("Hace 15 días")
                Spacer()
                Text("Hoy").fontWeight(.semibold).foregroundStyle(Hoy.t1)
            }
            .hoyFont(12, .medium, relativeTo: .caption1).foregroundStyle(Hoy.t3)
            .padding(.trailing, 28)
            Rectangle().fill(Hoy.sep).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                stat("Más alta", r.format(values.max() ?? 0), unit)
                Rectangle().fill(Hoy.sep).frame(width: 1, height: 34).padding(.horizontal, 10)
                stat("Más baja", r.format(values.min() ?? 0), unit)
                if let range = r.range {
                    Rectangle().fill(Hoy.sep).frame(width: 1, height: 34).padding(.horizontal, 10)
                    stat("En tu normal", "\(values.filter { range.contains($0) }.count)", "de \(values.count) días")
                }
            }
        }
    }

    private func deltaLine(_ r: VitalReading, mean: Double) -> some View {
        let d = r.raw - mean
        let tolerance = max(abs(mean) * 0.01, 0.05)
        let up = d > 0
        let good: Bool? = r.bad == 0 ? nil : (r.bad < 0 ? up : !up)
        let color = abs(d) < tolerance ? Hoy.t2 : (good.map { $0 ? HoyLevel.buena.ink : HoyLevel.justa.ink } ?? Hoy.t2)
        let unit = r.unit == "%" ? " %" : " \(r.unit)"
        return HStack(spacing: 5) {
            if abs(d) >= tolerance {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
            }
            Text(abs(d) < tolerance ? "En tu media" : "\(r.format(abs(d)))\(unit) \(up ? "sobre" : "bajo") tu media")
                .hoyFont(13, .semibold, relativeTo: .footnote)
        }
        .foregroundStyle(color)
    }

    private func stat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).hoyFont(13, relativeTo: .footnote).foregroundStyle(Hoy.t2)
            HoyValue(value: value, unit: unit, size: 17)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func chart(_ r: VitalReading, mean: Double?) -> some View {
        let pts = r.history.compactMap { h in DayKey.date(h.day).map { (date: $0, value: h.value) } }
        let values = pts.map(\.value) + (r.range.map { [$0.lowerBound, $0.upperBound] } ?? [])
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.18, 0.5)
        let first = pts.first?.date ?? Date(), last = pts.last?.date ?? Date()
        let shown = selected.flatMap { s in pts.min(by: { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) }) }
        let c = color(r)
        return Chart {
            if let range = r.range {
                RectangleMark(xStart: .value("a", first), xEnd: .value("b", last),
                              yStart: .value("lo", range.lowerBound), yEnd: .value("hi", range.upperBound))
                    .foregroundStyle(c.opacity(Hoy.bandOpacity))
                RuleMark(y: .value("hi", range.upperBound)).foregroundStyle(c.opacity(Hoy.edgeOpacity)).lineStyle(StrokeStyle(lineWidth: 0.6))
                    .annotation(position: .top, alignment: .trailing, spacing: 1) {
                        Text("tu normal").hoyFont(10, .semibold, relativeTo: .caption2).foregroundStyle(c)
                    }
                RuleMark(y: .value("lo", range.lowerBound)).foregroundStyle(c.opacity(Hoy.edgeOpacity)).lineStyle(StrokeStyle(lineWidth: 0.6))
            }
            if let mean {
                RuleMark(y: .value("Media", mean)).foregroundStyle(Hoy.t3.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(pts, id: \.date) { p in
                LineMark(x: .value("Día", p.date), y: .value("Valor", p.value))
                    .foregroundStyle(c)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let p = shown {
                RuleMark(x: .value("Día", p.date)).foregroundStyle(Hoy.t3.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        HoyPill(text: "\(HoyFmt.dayMonth(DayKey.string(p.date))) · \(r.format(p.value)) \(r.unit)")
                    }
                PointMark(x: .value("Día", p.date), y: .value("Valor", p.value))
                    .symbol { Circle().stroke(c, lineWidth: 2).background(Circle().fill(Hoy.card)).frame(width: 10, height: 10) }
            } else if let p = pts.last {
                PointMark(x: .value("Día", p.date), y: .value("Valor", p.value))
                    .symbol { Circle().fill(c).overlay(Circle().stroke(Hoy.card, lineWidth: 2)).frame(width: 9, height: 9) }
            }
        }
        .chartScrub($selected)
        .chartXScale(domain: first...last)
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel {
                    Text(r.format(v.as(Double.self) ?? 0)).hoyFont(11, .medium, relativeTo: .caption2).foregroundStyle(Hoy.t3)
                }
            }
        }
    }
}

// MARK: - Edad Pulso

struct HoyAgeBlock: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let r = model.pulsoAge, let age = r.pulsoAge {
            VStack(alignment: .leading, spacing: 10) {
                NavigationLink { PulsoAgeDetailView() } label: { HoySectionTitle("Edad Pulso", chevron: true) }.buttonStyle(.plain)
                NavigationLink { PulsoAgeDetailView() } label: {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HoyValue(value: Fmt.dec(age), unit: "años", size: 28)
                            if let d = r.difference {
                                HStack(spacing: 5) {
                                    if abs(d) >= 0.05 {
                                        Image(systemName: d < 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill").font(.system(size: 8))
                                    }
                                    Text(abs(d) < 0.05 ? "Como tu edad real" : "\(Fmt.dec(abs(d))) años \(d < 0 ? "más joven" : "mayor")")
                                        .hoyFont(14, .semibold, relativeTo: .footnote)
                                }
                                .foregroundStyle(abs(d) < 0.05 ? Hoy.t2 : (d < 0 ? HoyLevel.excelente.ink : HoyLevel.justa.ink))
                            }
                        }
                        .fixedSize()
                        if model.ageTrend.count >= 2 { trend(realNow: r.age).frame(maxWidth: .infinity) }
                    }
                    .hoyCard(padding: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Your Edad Pulso by week against your real age over the same weeks.
    private func trend(realNow: Double) -> some View {
        let pts = model.ageTrend.compactMap { p in DayKey.date(p.day).map { (date: $0, age: p.age) } }
        let today = Date()
        let real = pts.map { (date: $0.date, age: realNow - today.timeIntervalSince($0.date) / (365.25 * 86_400)) }
        let all = pts.map(\.age) + real.map(\.age)
        let lo = (all.min() ?? 0) - 0.4, hi = (all.max() ?? 1) + 0.4
        return VStack(spacing: 4) {
            Chart {
                ForEach(real, id: \.date) { p in
                    LineMark(x: .value("Semana", p.date), y: .value("Edad", p.age), series: .value("s", "Real"))
                        .foregroundStyle(Hoy.t3)
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                }
                ForEach(pts, id: \.date) { p in
                    LineMark(x: .value("Semana", p.date), y: .value("Edad", p.age), series: .value("s", "Pulso"))
                        .foregroundStyle(Hoy.bien)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                if let p = pts.last {
                    PointMark(x: .value("Semana", p.date), y: .value("Edad", p.age))
                        .symbol { Circle().fill(Hoy.bien).frame(width: 7, height: 7) }
                        .annotation(position: p.age < (real.last?.age ?? p.age) ? .bottom : .top, alignment: .trailing, spacing: 2) {
                            Text("Pulso").hoyFont(11, .medium, relativeTo: .caption2).foregroundStyle(Hoy.t2)
                        }
                }
                if let p = real.last {
                    PointMark(x: .value("Semana", p.date), y: .value("Edad", p.age)).symbolSize(0)
                        .annotation(position: p.age >= (pts.last?.age ?? p.age) ? .top : .bottom, alignment: .trailing, spacing: 2) {
                            Text("Real").hoyFont(11, .medium, relativeTo: .caption2).foregroundStyle(Hoy.t3)
                        }
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 54)
            HStack {
                Text(HoyFmt.month(model.ageTrend.first?.day ?? ""))
                Spacer()
                Text(HoyFmt.month(model.ageTrend.last?.day ?? "")).fontWeight(.semibold).foregroundStyle(Hoy.t1)
            }
            .hoyFont(11, .medium, relativeTo: .caption2).foregroundStyle(Hoy.t3)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Esta noche

struct HoyTonightBlock: View {
    @EnvironmentObject var model: AppModel
    @State private var open = false

    var body: some View {
        let plan = model.tonightPlan
        let alarm = model.nextAlarm
        if plan != nil || alarm != nil {
            VStack(alignment: .leading, spacing: 10) {
                Button { open = true } label: { HoySectionTitle("Esta noche", chevron: true) }.buttonStyle(.plain)
                Button { open = true } label: {
                    HStack(spacing: 0) {
                        if let plan {
                            half(icon: "bed.double.fill", title: "Acuéstate", value: Fmt.clock(plan.bedtime))
                        }
                        if plan != nil, alarm != nil {
                            Rectangle().fill(Hoy.sep).frame(width: 1, height: 44).padding(.horizontal, 14)
                        }
                        if let a = alarm {
                            half(icon: "alarm.fill", title: "Despertador",
                                 value: a.isSmart ? "\(Fmt.clock(a.earliest)) – \(Fmt.clock(a.latest))" : Fmt.clock(a.latest))
                        }
                    }
                    .hoyCard(padding: 16)
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $open) { BedtimeView().environmentObject(model) }
        }
    }

    private func half(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Hoy.sueno)
                Text(title).hoyFont(14, relativeTo: .footnote).foregroundStyle(Hoy.t2)
            }
            Text(value).hoyFont(24, .semibold, relativeTo: .title2).foregroundStyle(Hoy.t1).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
