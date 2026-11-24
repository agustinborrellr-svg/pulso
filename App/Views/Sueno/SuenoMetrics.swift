import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

// The sleep metric screens (studio B-sueno 03–09), all with the B template: hero, own card(s), chart, «Qué es».
// «Qué lo mueve» is left out: the app doesn't compute what moves these metrics (only for recovery).

private func intText(_ v: Double) -> String { "\(Int(v.rounded()))" }

// MARK: - 03 Fase

struct SuenoPhaseDetail: View {
    @EnvironmentObject var model: AppModel
    @State var stage: SleepStage

    private static func minutes(_ d: DaySummary, _ st: SleepStage) -> Double? {
        switch st {
        case .deep: return d.deepMinutes
        case .rem: return d.remMinutes
        case .light: return d.lightMinutes
        case .awake: return d.awakeMinutes
        }
    }

    private static func whatIs(_ st: SleepStage) -> String {
        switch st {
        case .deep: return "La fase más reparadora: el pulso baja al mínimo y la respiración se vuelve lenta y regular. La pulsera la deduce del pulso, la VFC y el movimiento."
        case .rem: return "La fase de los sueños: el cerebro está muy activo y el pulso se vuelve irregular. Abunda en la segunda mitad de la noche."
        case .light: return "La mayor parte de la noche: el paso entre estar despierto y las fases profundas. El cuerpo se relaja y el pulso baja."
        case .awake: return "Ratos despierto dentro del bloque de sueño, aunque no los recuerdes. Unos pocos minutos son normales."
        }
    }

    var body: some View {
        let st = stage
        let pairs = SuenoSpec.pairs(model) { Self.minutes($0, st) }
        let spec = SuenoSpec.make(model: model, pairs: pairs, title: Theme.stageName(st), subtitle: "Fases · anoche",
                                  format: { DSFmt.duration($0) }, higherIsBetter: st == .awake ? false : (st == .light ? nil : true),
                                  whatIs: Self.whatIs(st))
        let day = model.selected
        let session = day.flatMap { model.sleep(for: $0) }
        let total = day.map { [$0.deepMinutes, $0.remMinutes, $0.lightMinutes, $0.awakeMinutes].compactMap { $0 }.reduce(0, +) } ?? 0
        let mine = day.flatMap { Self.minutes($0, st) }
        let suffix = (mine != nil && total > 0) ? "\(Int((mine! / total * 100).rounded())) % de la noche" : nil
        SuenoMetricScreen(spec: spec, suffix: suffix) {
            DSSegmented(options: [(SleepStage.deep, "Profundo"), (.rem, "REM"), (.light, "Ligero"), (.awake, "Despierto")],
                        selection: $stage, height: 34)
        } extra: {
            if let s = session, !s.stages.isEmpty, s.stages.contains(st) {
                VStack(alignment: .leading, spacing: 10) {
                    SuenoCardTitle(title: "Anoche, cuándo", note: halfNote(s, st))
                    SuenoStageStrip(session: s, filled: { $0 == st }, color: st == .awake ? DS.t1 : DS.stage(st), height: 18)
                    NightAxis(start: s.start, end: s.end)
                }
                .dsCard(padding: 16)
            }
        } below: {
            EmptyView()
        }
    }

    private func halfNote(_ s: SleepSession, _ st: SleepStage) -> String? {
        let half = s.stages.count / 2
        let a = s.stages[..<half].filter { $0 == st }.count, b = s.stages[half...].filter { $0 == st }.count
        guard a + b >= 10 else { return nil }
        if Double(a) > Double(b) * 1.3 { return "más en la primera mitad" }
        if Double(b) > Double(a) * 1.3 { return "más en la segunda mitad" }
        return "repartido en la noche"
    }
}

// MARK: - 04 Calificación

struct SuenoScoreDetail: View {
    @EnvironmentObject var model: AppModel

    struct Influence: Identifiable {
        let icon: String
        let title: String
        let subtitle: String
        let points: Double
        let kind: MetricKind
        var id: String { title }
    }

    var body: some View {
        let spec = SuenoSpec.make(model: model, pairs: SuenoSpec.pairs(model) { $0.sleepPerformance.map { $0 * 100 } },
                                  title: "Calificación", format: intText, unit: "/100", statUnit: "",
                                  level: { DSLevel(score: $0) }, yDomain: 0...100,
                                  whatIs: "Resume tres cosas de la noche: cuánto dormiste frente a lo que necesitabas, lo parecido que fue tu horario a los días anteriores y lo poco que estuviste despierto.")
        SuenoMetricScreen(spec: spec) {
            EmptyView()
        } extra: {
            EmptyView()
        } below: {
            if let list = influences(), !list.isEmpty {
                DSSectionHeader("Qué ha influido", note: "puntos vs. tu media")
                influenceCard(list)
            }
        }
    }

    /// Points each part adds or takes against your mean of the 30 nights before, with the score's own weights
    /// (`SleepCoach.performance`: 0,864 suficiencia + 0,357 constancia + 0,197 eficiencia).
    private func influences() -> [Influence]? {
        guard let d = model.selected, let c = d.sleepConsistency, let slept = d.sleepMinutes, let need = d.sleepNeedMinutes, need > 0
        else { return nil }
        let from = DayKey.shift(d.day, days: -30)
        let base = model.days.filter { $0.day < d.day && $0.day >= from }.compactMap { x -> (Double, Double, Double)? in
            guard let c = x.sleepConsistency, let s = x.sleepMinutes, let n = x.sleepNeedMinutes, n > 0 else { return nil }
            return (min(1, s / n), c, x.sleepEfficiency ?? 0.9)
        }
        guard base.count >= 7 else { return nil }
        let n = Double(base.count)
        let ms = base.map(\.0).reduce(0, +) / n, mc = base.map(\.1).reduce(0, +) / n, me = base.map(\.2).reduce(0, +) / n
        let suff = min(1, slept / need), eff = d.sleepEfficiency ?? 0.9
        let ps = 86.4 * (suff - ms), pc = 0.357 * (c - mc), pe = 19.7 * (eff - me)
        func word(_ p: Double, _ up: String, _ down: String) -> String { p >= 0.5 ? up : (p <= -0.5 ? down : "en tu normal") }
        var out = [Influence(icon: "moon.fill", title: "Horas vs. lo necesario", subtitle: "dormiste el \(Int((slept / need * 100).rounded())) %",
                             points: ps, kind: .necesidadSueno),
                   Influence(icon: "clock", title: "Regularidad", subtitle: "\(Int(c.rounded())) %, \(word(pc, "más constante", "menos constante"))",
                             points: pc, kind: .regularidad)]
        if let e = d.sleepEfficiency {
            out.append(Influence(icon: "bed.double", title: "Eficiencia", subtitle: "\(Int((e * 100).rounded())) %, \(word(pe, "mejor que tu media", "peor que tu media"))",
                                 points: pe, kind: .eficiencia))
        }
        return out
    }

    private func influenceCard(_ list: [Influence]) -> some View {
        let scale = max(list.map { abs($0.points) }.max() ?? 1, 4)
        let total = list.map { Int($0.points.rounded()) }.reduce(0, +)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "arrowtriangle.left.fill").font(.system(size: 7)).foregroundStyle(DS.baja)
                    Text("Resta")
                }
                HStack(spacing: 3) {
                    Text("Suma")
                    Image(systemName: "arrowtriangle.right.fill").font(.system(size: 7)).foregroundStyle(DS.buena)
                }
                Spacer().frame(width: 76)
            }
            .dsFont(12, .medium).foregroundStyle(DS.t2)
            .padding(.top, 12).padding(.bottom, 4)
            ForEach(list) { f in
                RouteLink(.metric(f.kind)) {
                    HStack(spacing: 10) {
                        Image(systemName: f.icon).font(.system(size: 15)).foregroundStyle(DS.sueno).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.title).dsFont(15, .medium).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                            Text(f.subtitle).dsFont(13).foregroundStyle(DS.t2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        DSDivergentBar(effect: f.points / scale).frame(width: 70, height: 14)
                        let p = Int(f.points.rounded())
                        Text(SFmt.points(p)).dsFont(15, .semibold)
                            .foregroundStyle(p > 0 ? DSLevel.buena.ink : (p < 0 ? DSLevel.baja.ink : DS.t3))
                            .frame(width: 32, alignment: .trailing)
                        DSChevron()
                    }
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                DSDivider(inset: 32)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Total").dsFont(16, .semibold).foregroundStyle(DS.t1)
                Text("sobre tu media").dsFont(14).foregroundStyle(DS.t2)
                Spacer()
                Text(SFmt.points(total)).dsFont(17, .semibold)
                    .foregroundStyle(total > 0 ? DSLevel.buena.ink : (total < 0 ? DSLevel.baja.ink : DS.t3))
            }
            .frame(minHeight: 50)
        }
        .padding(.horizontal, 14)
        .dsCard(padding: 0)
    }
}

// MARK: - 05 Necesidad y deuda

struct SuenoNeedDetail: View {
    @EnvironmentObject var model: AppModel
    @State private var period: DSPeriod = .week
    @State private var debtSel: Date?

    var body: some View {
        var spec = SuenoSpec.make(model: model, pairs: SuenoSpec.pairs(model) { $0.sleepNeedMinutes }, title: "Necesidad y deuda",
                                  subtitle: "Anoche", format: { DSFmt.duration($0) }, higherIsBetter: nil,
                                  whatIs: "Lo que tu cuerpo pide dormir: tu base, más lo que añade el esfuerzo del día y la deuda que arrastras. Las siestas la reducen.")
        let d = model.selected
        var suffix: String?
        if let d, let need = d.sleepNeedMinutes, need > 0, let slept = d.sleepMinutes {
            let pct = slept / need * 100
            spec.level = SuenoLevel.hoursVsNeed(pct)
            spec.levelText = nil
            spec.meter = true
            suffix = "dormiste el \(Int(pct.rounded())) %"
            let short = need - slept
            spec.side = [("Dormido", DSFmt.duration(slept)),
                         (short >= 0 ? "Te faltaron" : "Te sobraron", DSFmt.duration(abs(short)))]
        }
        spec.footnote = "La deuda guarda parte de lo que te faltó cada noche y se va borrando si duermes más."
        return SuenoMetricScreen(spec: spec, suffix: suffix, chart: false) {
            EmptyView()
        } extra: {
            if let d { formation(d) }
            if let d { nights(d) }
            if let d { debt(d) }
            if let plan = model.tonightPlan {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: "moon.fill").font(.system(size: 14)).foregroundStyle(DS.sueno)
                        Text("Esta noche necesitas").dsFont(17, .medium).foregroundStyle(DS.t1)
                        Spacer()
                        Text(DSFmt.duration(plan.needMinutes)).dsFont(18, .semibold).foregroundStyle(DS.t1)
                    }
                    Text("según el esfuerzo de hoy, tu deuda y las siestas").dsFont(13).foregroundStyle(DS.t2)
                }
                .dsCard(padding: 16)
            }
        } below: {
            EmptyView()
        }
    }

    /// Base + yesterday's effort + debt − naps, only when it adds up to the stored need (the profile base may have
    /// changed since).
    @ViewBuilder
    private func formation(_ d: DaySummary) -> some View {
        let prev = model.days.last { $0.day < d.day }
        let base = model.profile.sleepNeedHours * 60
        let strain = SleepCoach.strainMinutes(prev?.strain)
        let debt = max(0, d.sleepDebtMinutes ?? 0)
        let nap = prev?.napMinutes ?? 0
        let raw = base + strain + debt - nap
        if let need = d.sleepNeedMinutes, raw > base * 0.8, abs(raw - need) <= 3 {
            DSSectionHeader("Cómo se formó")
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { g in
                    let total = max(base + strain + debt, 1)
                    let w = { (m: Double) in max(0, g.size.width * CGFloat(m / total) - 3) }
                    HStack(spacing: 3) {
                        Capsule().fill(DS.fill2).frame(width: w(base))
                        if strain >= 1 { Capsule().fill(DS.act).frame(width: w(strain)) }
                        if debt >= 1 { Capsule().fill(DS.sueno).frame(width: w(debt)) }
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("desde \(DSFmt.duration(base))")
                    Spacer()
                    Text("necesitabas")
                }
                .dsFont(12).foregroundStyle(DS.t3).padding(.top, 6).padding(.bottom, 4)
                row(DS.fill2, "Tu base", DSFmt.duration(base))
                DSDivider()
                row(DS.act, "Esfuerzo de ayer", "+\(DSFmt.duration(strain))")
                DSDivider()
                row(DS.sueno, "Deuda que traías", debt >= 1 ? "+\(DSFmt.duration(debt))" : "ninguna", dim: debt < 1)
                DSDivider()
                row(nil, "Siestas", nap >= 1 ? "−\(DSFmt.duration(nap))" : "ninguna", dim: nap < 1)
            }
            .dsCard(padding: 16)
        }
    }

    private func row(_ color: Color?, _ label: String, _ value: String, dim: Bool = false) -> some View {
        HStack(spacing: 10) {
            if let color {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            } else {
                RoundedRectangle(cornerRadius: 2).strokeBorder(DS.t2, lineWidth: 1).frame(width: 10, height: 10)
            }
            Text(label).dsFont(16).foregroundStyle(DS.t1)
            Spacer()
            Text(value).dsFont(16, .semibold).foregroundStyle(dim ? DS.t3 : DS.t1)
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func nights(_ d: DaySummary) -> some View {
        let n = period == .week ? 7 : 30
        let bars = (0..<n).map { i -> SuenoNightBars.Bar in
            let k = DayKey.shift(d.day, days: i - (n - 1))
            let x = model.day(k)
            return SuenoNightBars.Bar(day: k, minutes: x?.sleepMinutes, mark: x?.sleepNeedMinutes)
        }
        let both = bars.compactMap { b -> Double? in
            guard let m = b.minutes, let k = b.mark else { return nil }
            return k - m
        }
        if !both.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(n == 7 ? "Últimas 7 noches" : "Últimas 30 noches").dsFont(17, .semibold).foregroundStyle(DS.t2)
                    Spacer()
                    DSSegmented(options: [(DSPeriod.week, "7 d"), (.month, "30 d")], selection: $period).frame(width: 120)
                }
                HStack(spacing: 16) {
                    HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(DS.sueno).frame(width: 10, height: 10); Text("Dormido") }
                    HStack(spacing: 6) { Capsule().fill(DS.t1).frame(width: 14, height: 2.5); Text("Necesitabas") }
                }
                .dsFont(13).foregroundStyle(DS.t2)
                SuenoNightBars(bars: bars, highlight: d.day, showMarks: true, height: 140)
                DSDivider()
                DSStatStrip(stats: [
                    DSStat(label: "Mayor falta", value: (both.max() ?? 0) > 0 ? DSFmt.duration(both.max()) : "–"),
                    DSStat(label: "Mayor sobra", value: (both.min() ?? 0) < 0 ? DSFmt.duration(-(both.min() ?? 0)) : "–"),
                    DSStat(label: "Cubiertas", value: "\(both.filter { $0 <= 0 }.count)", unit: "de \(both.count) noches"),
                ])
            }
            .dsCard(padding: 16)
        }
    }

    @ViewBuilder
    private func debt(_ d: DaySummary) -> some View {
        let start = DayKey.shift(d.day, days: -29)
        let pts = model.days.filter { $0.day >= start && $0.day <= d.day }
            .compactMap { x in x.sleepDebtMinutes.flatMap { v in DayKey.date(x.day).map { DSPoint(date: $0, value: v) } } }
        if let now = d.sleepDebtMinutes, pts.count >= 3 {
            let week = model.day(DayKey.shift(d.day, days: -7))?.sleepDebtMinutes
            DSSectionHeader("Deuda de sueño")
            VStack(alignment: .leading, spacing: 8) {
                let p = DSFmt.durationParts(now)
                HoyValue(value: p.0, unit: p.1, size: 30)
                if let week, abs(now - week) >= 1 {
                    DSDelta(text: "\(DSFmt.duration(abs(now - week))) \(now < week ? "menos" : "más") que hace una semana", up: now > week,
                            color: now < week ? DSLevel.buena.ink : DSLevel.justa.ink)
                }
                DSLineChart(points: pts, color: DS.sueno, domain: 0...max(60, (pts.map(\.value).max() ?? 60) * 1.15),
                            format: { DSFmt.duration($0) }, selection: $debtSel)
                    .frame(height: 140)
                HStack {
                    Text("Hace 30 días")
                    Spacer()
                    Text("Anoche").foregroundStyle(DS.t1).fontWeight(.bold)
                }
                .dsFont(13).foregroundStyle(DS.t2).padding(.trailing, 34)
            }
            .dsCard(padding: 16)
        }
    }
}

// MARK: - 06 Regularidad

struct SuenoRegularityDetail: View {
    @EnvironmentObject var model: AppModel
    @State private var period: DSPeriod = .week

    var body: some View {
        let spec = SuenoSpec.make(model: model, pairs: SuenoSpec.pairs(model) { $0.sleepConsistency }, title: "Regularidad",
                                  format: intText, unit: "%", level: SuenoLevel.regularity,
                                  whatIs: "Lo parecido que es tu horario de sueño al de los días anteriores: si te duermes y te levantas a la misma hora, sube.")
        SuenoMetricScreen(spec: spec, chart: false) {
            EmptyView()
        } extra: {
            if let d = model.selected { dots(d) }
            if spec.series.values.contains(where: { $0.count > 1 }) { DSMetricChartCard(spec: spec) }
        } below: {
            EmptyView()
        }
    }

    @ViewBuilder
    private func dots(_ d: DaySummary) -> some View {
        let n = period == .week ? 7 : 30
        let nights = (0..<n).compactMap { i -> (String, Double, Double)? in
            let k = DayKey.shift(d.day, days: i - (n - 1))
            guard let x = model.day(k), let a = x.sleepStart, let b = x.sleepEnd else { return nil }
            return (k, SuenoClock.minutes(a, evening: true), SuenoClock.minutes(b, evening: false))
        }
        if nights.count >= 2 {
            let beds = nights.map(\.1), wakes = nights.map(\.2)
            let mb = beds.reduce(0, +) / Double(beds.count), mw = wakes.reduce(0, +) / Double(wakes.count)
            let sd = sqrt(beds.map { ($0 - mb) * ($0 - mb) }.reduce(0, +) / Double(max(beds.count - 1, 1)))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(n == 7 ? "Últimas 7 noches" : "Últimas 30 noches").dsFont(17, .semibold).foregroundStyle(DS.t2)
                    Spacer()
                    DSSegmented(options: [(DSPeriod.week, "7 d"), (.month, "30 d")], selection: $period).frame(width: 120)
                }
                HStack(spacing: 14) {
                    HStack(spacing: 6) { HoyDot(color: DS.t2, size: 8); Text("Cada noche") }
                    HStack(spacing: 6) { HoyDot(color: DS.sueno, size: 8); Text("Anoche") }
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(DS.sueno.opacity(0.30))
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(DS.sueno.opacity(DS.edgeOpacity), lineWidth: 0.5))
                            .frame(width: 14, height: 9)
                        Text("Tu franja")
                    }
                }
                .dsFont(13).foregroundStyle(DS.t2)
                rail("Te acuestas", nights.map { ($0.0, $0.1) }, last: d.day, band: SuenoClock.window(model, evening: true, before: d.day), habitual: mb)
                rail("Te levantas", nights.map { ($0.0, $0.2) }, last: d.day, band: SuenoClock.window(model, evening: false, before: d.day), habitual: mw)
                DSDivider()
                DSStatStrip(stats: [DSStat(label: "Te acuestas", value: SuenoClock.text(mb)),
                                    DSStat(label: "Te levantas", value: SuenoClock.text(mw)),
                                    DSStat(label: "Variación", value: "± \(Int(sd.rounded()))", unit: "min")])
            }
            .dsCard(padding: 16)
        }
    }

    private func rail(_ title: String, _ pts: [(String, Double)], last: String, band: ClosedRange<Double>?, habitual: Double) -> some View {
        let vals = pts.map(\.1) + [band?.lowerBound, band?.upperBound].compactMap { $0 }
        let lo = ((vals.min() ?? habitual) - 20), hi = ((vals.max() ?? habitual) + 20)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).dsFont(15, .semibold).foregroundStyle(DS.t2)
            GeometryReader { g in
                let x = { (m: Double) in g.size.width * CGFloat((m - lo) / max(hi - lo, 1)) }
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill).frame(height: 8)
                    if let band {
                        RoundedRectangle(cornerRadius: 3).fill(DS.sueno.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(DS.sueno.opacity(DS.edgeOpacity), lineWidth: 0.6))
                            .frame(width: max(4, x(band.upperBound) - x(band.lowerBound)), height: 22)
                            .offset(x: x(band.lowerBound))
                    }
                    Rectangle().fill(DS.t2).frame(width: 1.5, height: 18).offset(x: x(habitual) - 0.75)
                    ForEach(pts, id: \.0) { p in
                        let isLast = p.0 == last
                        Circle().fill(isLast ? DS.sueno : DS.t3)
                            .overlay(Circle().stroke(DS.card, lineWidth: 2))
                            .frame(width: isLast ? 15 : 10, height: isLast ? 15 : 10)
                            .offset(x: x(p.1) - (isLast ? 7.5 : 5))
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 24)
            HStack {
                Text(SuenoClock.text(lo))
                Spacer()
                Text("habitual").foregroundStyle(DS.sueno).fontWeight(.semibold)
                Spacer()
                Text(SuenoClock.text(hi))
            }
            .dsFont(12).foregroundStyle(DS.t3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

// MARK: - 07 Eficiencia

struct SuenoEfficiencyDetail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let spec = SuenoSpec.make(model: model, pairs: SuenoSpec.pairs(model) { $0.sleepEfficiency.map { $0 * 100 } }, title: "Eficiencia",
                                  subtitle: "Estimada · anoche", format: intText, unit: "%", level: SuenoLevel.efficiency,
                                  whatIs: "Tiempo dormido dentro del bloque detectado. La pulsera no sabe cuándo te metes en la cama: el bloque empieza cuando te quedas quieto y tu pulso baja, así que el rato leyendo o con el móvil no cuenta.")
        SuenoMetricScreen(spec: spec) {
            if let d = model.selected, let s = model.sleep(for: d) {
                VStack(alignment: .leading, spacing: 10) {
                    SuenoCardTitle(title: "Anoche, minuto a minuto")
                    if !s.stages.isEmpty {
                        HStack(spacing: 10) {
                            Text("Dormido").dsFont(15).foregroundStyle(DS.t2).frame(width: 80, alignment: .leading)
                            AsleepStrip(session: s, awake: false)
                        }
                        HStack(spacing: 10) {
                            Text("Despierto").dsFont(15).foregroundStyle(DS.t2).frame(width: 80, alignment: .leading)
                            AsleepStrip(session: s, awake: true)
                        }
                        NightAxis(start: s.start, end: s.end).padding(.leading, 90)
                    }
                    DSDivider().padding(.top, 4)
                    line("Bloque detectado", DSFmt.duration(s.inBedMinutes))
                    DSDivider()
                    line("Tiempo despierto", DSFmt.duration(s.minutesAwake))
                    DSDivider()
                    line("Despertares", "\(d.disturbances ?? s.disturbances)")
                }
                .dsCard(padding: 16)
            }
        }
    }

    private func line(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).dsFont(16).foregroundStyle(DS.t1)
            Spacer()
            Text(v).dsFont(16, .semibold).foregroundStyle(DS.t1)
        }
        .frame(minHeight: 40)
    }
}

// MARK: - 08 Reparador

struct SuenoRestorativeDetail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        var spec = SuenoSpec.make(model: model, pairs: SuenoSpec.pairs(model) { TrendMetric.restorativeHours.value($0) }, title: "Sueño reparador",
                                  format: { DSFmt.duration($0) }, initial: .halfYear,
                                  whatIs: "Profundo y REM juntos: las dos fases en las que el cuerpo y la mente se recuperan de verdad.")
        let d = model.selected
        let rest = d.flatMap { TrendMetric.restorativeHours.value($0) }
        var suffix: String?
        if let rest, let slept = d?.sleepMinutes, slept > 0 {
            let pct = rest / slept * 100
            spec.level = SuenoLevel.restorative(pct)
            spec.levelText = nil
            spec.meter = true
            suffix = "\(Int(pct.rounded())) % de la noche"
        }
        return SuenoMetricScreen(spec: spec, suffix: suffix) {
            if let d, let deep = d.deepMinutes, let rem = d.remMinutes, deep + rem > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    SuenoCardTitle(title: "Cómo se reparte")
                    GeometryReader { g in
                        HStack(spacing: 3) {
                            Capsule().fill(DS.stDeep).frame(width: max(4, g.size.width * CGFloat(deep / (deep + rem)) - 1.5))
                            Capsule().fill(DS.stREM)
                        }
                    }
                    .frame(height: 10)
                    HStack {
                        part(DS.stDeep, "Profundo", deep)
                        Spacer()
                        part(DS.stREM, "REM", rem)
                    }
                }
                .dsCard(padding: 16)
            }
        }
    }

    private func part(_ c: Color, _ name: String, _ m: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) { HoyDot(color: c); Text(name).dsFont(13).foregroundStyle(DS.t2) }
            Text(DSFmt.duration(m)).dsFont(19, .semibold).foregroundStyle(DS.t1)
        }
    }
}

// MARK: - 09 Latencia

struct SuenoLatencyDetail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // Latency lives in each night's session: read the last 40 nights.
        let pairs: NightPairs = model.days.suffix(40).compactMap { d in
            guard d.day <= model.selectedDay, let s = model.sleep(for: d) else { return nil }
            return (day: d.day, v: s.latencyMinutes)
        }
        let spec = SuenoSpec.make(model: model, pairs: pairs, title: "Latencia", format: intText, unit: "min",
                                  higherIsBetter: false, initial: .week, periods: [.week, .month],
                                  whatIs: "Minutos desde que te quedaste quieto hasta 10 minutos seguidos dormido. No incluye el rato en la cama antes de quedarte quieto.")
        SuenoMetricScreen(spec: spec, suffix: "estimada") {
            if let d = model.selected, let s = model.sleep(for: d) {
                HStack(spacing: 12) {
                    point("Quieto", s.start, DS.t2)
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.t3)
                    point("Dormido", s.start + Int(s.latencyMinutes * 60), DS.sueno)
                    Spacer()
                }
                .dsCard(padding: 16)
            }
        }
    }

    private func point(_ k: String, _ ts: Int, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) { HoyDot(color: c); Text(k).dsFont(13).foregroundStyle(DS.t2) }
            Text(SFmt.clock(ts)).dsFont(22, .semibold).foregroundStyle(DS.t1)
        }
    }
}
