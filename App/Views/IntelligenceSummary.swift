import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoIntelligence

// MARK: - «Inteligencia»: last night, tomorrow, what moves you, your patterns

/// The analysis as four plain blocks, each a chart and a sentence: last night against your normal, tomorrow and what
/// changes it, what your own data says moves your recovery, and your patterns. The technical metrics sit behind
/// «Todas las métricas».
struct IntelligenceContent: View {
    @EnvironmentObject var model: AppModel
    @State private var behaviors: Behaviors.Report?

    var body: some View {
        VStack(spacing: 14) {
            if let r = model.intelligence {
                IntelNightCard(report: r)
                IntelTomorrowCard(report: r)
                IntelDiscoveries(report: behaviors)
                SectionHeading(text: "Tus patrones")
                IntelLoadPatternCard(report: r)
                IntelSchedulePatternCard()
                IntelWeekdayPatternCard()
                IntelToolsRow(report: r)
                Text("Solo con tus datos y comparado solo contigo. Asociaciones, no causas; no es un diagnóstico.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                PCard {
                    HStack {
                        PulseLoader(phase: .running(progress: nil), style: .compact)
                        Text("Calculando tu análisis…").foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .task(id: model.intelligence?.generated) { behaviors = model.behaviorReport() }
    }
}

// MARK: Last night

/// How usual last night was for you, the signal that stands out, and each signal against its normal band.
struct IntelNightCard: View {
    let report: IntelligenceReport

    var body: some View {
        let night = report.lastNight
        let point = night?.point ?? report.deviation.last
        // Only "anoche" when it is: otherwise the latest night with every signal, and why last night isn't it.
        let isLastNight = night?.point != nil
        NavigationLink { IntelTodayView() } label: {
            PCard {
                CardHeader(title: isLastNight || point == nil ? "Anoche frente a tu normal" : "Tu última noche completa",
                           subtitle: point.map { "Noche del \(Deviation.shortDate($0.day)), comparada con tus \($0.baselineNights) noches anteriores" },
                           chevron: true)
                if !isLastNight, point != nil, let night {
                    Text(night.hasNight && !night.missing.isEmpty
                         ? "A la de anoche le falta: \(night.missing.map(Self.lowerFirst).joined(separator: ", "))."
                         : "De anoche aún no hay datos de la pulsera.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                if let p = point {
                    Text(Self.verdict(p.coherence))
                        .scaledFont(26, weight: .bold, design: .rounded, relativeTo: .title1)
                        .foregroundStyle(CoherenceCard.color(p.coherence))
                    Text(Self.standout(p)).font(.subheadline).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 14) {
                        ForEach(p.signals, id: \.key) { IntelSignalRow(signal: $0) }
                    }
                    .padding(.top, 4)
                    Text("Franja gris: tu normal (8 de cada 10 noches). Punto: anoche.")
                        .font(.caption2).foregroundStyle(Theme.tertiary)
                } else {
                    Text("Aún aprendiendo tu patrón").scaledFont(24, weight: .bold, design: .rounded, relativeTo: .title1).foregroundStyle(.white)
                    Text(report.metric("coherence")?.summary ?? "Con unas noches más Pulso sabrá qué es normal para ti.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// "Respiración" → "respiración", but "FC en reposo" and "VFC" keep their capitals.
    static func lowerFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        if s.dropFirst().first?.isUppercase == true { return s }
        return f.lowercased() + s.dropFirst()
    }

    static func verdict(_ coherence: Double) -> String {
        coherence >= 50 ? "Noche normal para ti" : (coherence >= 10 ? "Noche algo inusual" : "Noche muy inusual")
    }

    /// The signal furthest from your usual, in words.
    static func standout(_ p: Deviation.Point) -> String {
        guard let s = p.signals.filter({ abs($0.z) >= 1 }).max(by: { abs($0.z) < abs($1.z) }) else {
            return "Todas tus señales de anoche estaban dentro de lo habitual."
        }
        let dir = s.z > 0 ? "más alta" : "más baja"
        return "Lo que más se sale: \(lowerFirst(s.label)) \(dir) de lo habitual" + (s.adverse ? "." : ", y eso es buena señal.")
    }
}

/// One signal: last night's value, your normal, and where it falls against the band your nights usually land in.
struct IntelSignalRow: View {
    let signal: Deviation.Contributor

    var body: some View {
        // Coloured when the dot falls outside the grey band, so the colour and the drawing always agree.
        let off = !signal.band.contains(signal.z)
        let color = !off ? Color.white : (signal.adverse ? Theme.worse : Theme.better)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(signal.label).font(.subheadline).foregroundStyle(.white)
                Spacer()
                Text(SignalBar.format(signal.key, signal.value)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(color)
                Text("normal \(SignalBar.format(signal.key, signal.usual))").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            GeometryReader { g in
                let w = g.size.width
                let x = { (z: Double) in CGFloat((min(max(z, -3), 3) + 3) / 6) * w }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(height: 6)
                    Capsule().fill(Color.white.opacity(0.22))
                        .frame(width: max(4, x(signal.band.upperBound) - x(signal.band.lowerBound)), height: 6)
                        .offset(x: x(signal.band.lowerBound))
                    Circle().fill(color).frame(width: 10, height: 10).offset(x: x(signal.z) - 5)
                }
            }
            .frame(height: 10)
        }
    }
}

// MARK: Tomorrow

/// Tomorrow's forecast with its range, and the things you can still do tonight that the model says move it.
struct IntelTomorrowCard: View {
    let report: IntelligenceReport

    struct Lever {
        let icon: String
        let title: String
        let points: Int
    }

    var body: some View {
        if let o = report.outlook {
            let f = o.model.forecast(o.todayInputs)
            let levers = Self.levers(o)
            NavigationLink { WhatIfView() } label: {
                PCard {
                    CardHeader(title: "Mañana", subtitle: "Recuperación prevista si duermes tus \(Fmt.hm(o.usualSleepHours * 60)) habituales", chevron: true)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(Int(f.value.rounded())) %").scaledFont(32, weight: .bold, design: .rounded, relativeTo: .title1).monospacedDigit()
                            .foregroundStyle(Theme.recoveryColor(f.value))
                        Text("entre \(Int(f.interval.lowerBound)) y \(Int(f.interval.upperBound)) %").font(.caption).foregroundStyle(Theme.secondary)
                        Spacer()
                    }
                    IntervalBar(value: f.value, interval: f.interval)
                    Caps("Qué la cambia esta noche", size: 10, color: Theme.secondary, weight: .semibold).padding(.top, 6)
                    if levers.isEmpty {
                        Text("Ninguno de los cambios que puedes hacer esta noche mueve la previsión más de un punto.")
                            .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(levers, id: \.title) { l in
                            HStack(spacing: 10) {
                                Image(systemName: l.icon).font(.subheadline).foregroundStyle(Theme.secondary).frame(width: 22)
                                Text(l.title).font(.subheadline).foregroundStyle(.white)
                                Spacer()
                                Text(String(format: "%+d", l.points)).font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(l.points > 0 ? Theme.better : Theme.worse)
                            }
                        }
                    }
                    Text(Self.honesty(o)).font(.caption2).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(.plain)
        } else if let m = report.metric("forecast") {
            PCard {
                CardHeader(title: "Mañana", subtitle: "Recuperación prevista")
                Text(m.summary).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the model says one more hour of sleep, or each habit it has learnt, does to tomorrow (in points). Only
    /// what you can still change tonight: a habit already logged today has happened.
    static func levers(_ o: RecoveryModel.Outlook) -> [Lever] {
        let x = o.todayInputs
        let base = o.model.forecast(x).value
        let on = (0..<3).map { x[RecoveryModel.firstHabitFeature + $0] > 0 }
        func run(_ sleep: Double, _ h: [Bool]) -> Double {
            RecoveryModel.scenario(o, sleepHours: sleep, alcohol: h[0], caffeine: h[1], lateMeal: h[2]).value
        }
        var out: [Lever] = []
        let more = o.usualSleepHours + 1
        let sleep = Int((run(more, on) - base).rounded())
        if sleep >= 1 { out.append(Lever(icon: "bed.double", title: "Dormir 1 h más (\(Fmt.hm(more * 60)))", points: sleep)) }
        let habits = [("Si tomas alcohol", "wineglass"), ("Si tomas cafeína por la tarde", "cup.and.saucer"), ("Si cenas tarde", "fork.knife")]
        for i in 0..<3 where o.model.usesHabit(i) && !on[i] {
            var h = on
            h[i] = true
            let d = Int((run(o.usualSleepHours, h) - base).rounded())
            if d <= -1 { out.append(Lever(icon: habits[i].1, title: habits[i].0, points: d)) }
        }
        return out
    }

    static func honesty(_ o: RecoveryModel.Outlook) -> String {
        guard let ev = o.evaluation else { return "Aún sin validar con tus días: tómalo como orientación." }
        return ev.predictability > 0.05
            ? "Probado en \(ev.tested) días: acierta mejor que tu media de la última semana."
            : "Probado en \(ev.tested) días: aún no acierta mejor que tu media de la última semana. Tómalo como orientación."
    }
}

// MARK: Discoveries

/// What your days say moves your recovery: one card per behaviour with a clear effect, with and without.
struct IntelDiscoveries: View {
    let report: Behaviors.Report?

    var body: some View {
        if let report {
            let items = Self.findings(report)
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(text: "Descubrimientos")
                if items.isEmpty {
                    NavigationLink { BehaviorsView() } label: { waiting(report) }.buttonStyle(.plain)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(items) { it in
                                NavigationLink { BehaviorsView() } label: { DiscoveryCard(item: it) }
                                    .buttonStyle(.plain)
                                    .containerRelativeFrame(.horizontal) { w, _ in w * 0.82 }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .contentMargins(.horizontal, 16, for: .scrollContent)
                    .padding(.horizontal, -16)
                }
            }
        }
    }

    /// Unlocked behaviours with an effect (beyond ±2 %) whose raw means point the same way, strongest first.
    static func findings(_ r: Behaviors.Report) -> [Behaviors.Item] {
        let clear = r.impact.filter { it in
            guard it.helps != nil, let p = it.impactPct, let a = it.withMean, let b = it.withoutMean else { return false }
            return (a - b) * p > 0
        }
        return Array(clear.sorted { abs($0.impactPct ?? 0) > abs($1.impactPct ?? 0) }.prefix(6))
    }

    private func waiting(_ r: Behaviors.Report) -> some View {
        PCard {
            Text("Pulso compara tus días con y sin cada comportamiento. Cada uno aparece cuando hay al menos \(Behaviors.minEach) días de cada.")
                .font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(r.locked.prefix(3)) { it in
                HStack {
                    Image(systemName: "lock").font(.caption).foregroundStyle(Theme.tertiary)
                    Text(it.label).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Text("\(min(it.yes, Behaviors.minEach))/\(Behaviors.minEach) con · \(min(it.no, Behaviors.minEach))/\(Behaviors.minEach) sin")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}

struct DiscoveryCard: View {
    let item: Behaviors.Item
    /// Sleep behaviours act on that same day's recovery; the rest on the next day's.
    static let sameDay: Set<String> = ["auto.sleepScore", "auto.wakeConsistent", "auto.bedConsistent"]

    var body: some View {
        let p = item.impactPct ?? 0
        let tint = p >= 0 ? Theme.better : Theme.worse
        VStack(alignment: .leading, spacing: 10) {
            Caps(item.automatic ? "Detectado por Pulso" : "De tu diario", size: 9.5, color: Theme.secondary, weight: .semibold)
            Text(item.label).font(.headline).foregroundStyle(.white).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%+.0f %%", p)).scaledFont(26, weight: .bold, design: .rounded, relativeTo: .title2).monospacedDigit()
                    .foregroundStyle(tint)
                Text("de recuperación \(Self.sameDay.contains(item.key) ? "ese día" : "al día siguiente")")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                bar("Con", item.withMean ?? 0, tint)
                bar("Sin", item.withoutMean ?? 0, Color.white.opacity(0.35))
            }
            Text("Recuperación media · \(item.yes) días con, \(item.no) sin").font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
    }

    private func bar(_ k: String, _ v: Double, _ c: Color) -> some View {
        HStack(spacing: 8) {
            Text(k).font(.caption).foregroundStyle(Theme.secondary).frame(width: 26, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(c).frame(width: max(4, g.size.width * CGFloat(min(max(v, 0), 100) / 100)))
                }
            }
            .frame(height: 8)
            Text("\(Int(v.rounded())) %").font(.caption.monospacedDigit()).foregroundStyle(.white).frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: Patterns

/// After each demanding day, how many nights your signals took to come back to your normal.
struct IntelLoadPatternCard: View {
    let report: IntelligenceReport

    var body: some View {
        let m = report.metric("recoveryVelocity")
        let events = Array(report.events.filter { !$0.chained && $0.nightsAtLeast != nil }.suffix(10))
        NavigationLink { IntelSectionView(title: "Respuesta a la carga") } label: {
            PCard {
                CardHeader(title: "Tras un día exigente", subtitle: "Noches hasta que tus constantes vuelven a tu normal", chevron: true)
                if let m, m.isAvailable, let med = m.value, events.count >= 3 {
                    Text(IntelArea.headline(m)).scaledFont(26, weight: .bold, design: .rounded, relativeTo: .title2).foregroundStyle(.white)
                    Text(m.summary).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    Chart {
                        ForEach(events, id: \.day) { e in
                            BarMark(x: .value("Día", e.day), y: .value("Noches", max(0.1, e.nightsAtLeast ?? 0)), width: .ratio(0.5))
                                .foregroundStyle(Color(white: 0.45))
                                .cornerRadius(2)
                        }
                        RuleMark(y: .value("Lo habitual", max(0.1, med)))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.white.opacity(0.6))
                    }
                    .chartYScale(domain: 0...Double(LoadResponse.maxNights))
                    .chartXScale(domain: events.map(\.day))
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 1, 2, 3, 4, 5]) { v in
                            AxisGridLine().foregroundStyle(Theme.hairline)
                            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary) }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: Self.ticks(events.map(\.day), every: max(2, events.count / 4))) { v in
                            AxisValueLabel { Text(Deviation.shortDate(v.as(String.self) ?? "")).scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary) }
                        }
                    }
                    .frame(height: 130)
                    Caps("- - - Lo habitual en ti · cada barra, un día exigente", size: 9, color: Theme.secondary, weight: .semibold)
                } else {
                    Text(m?.summary ?? "Aparece tras unos días exigentes con las noches siguientes medidas.")
                        .font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Axis days counted back from the newest, leaving out the first bar (its label would be clipped at the edge).
    static func ticks(_ days: [String], every: Int) -> [String] {
        stride(from: days.count - 1, through: 1, by: -every).map { days[$0] }
    }
}

/// Bed and wake times of the last two weeks, with your usual ones.
struct IntelSchedulePatternCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let nights = model.days.suffix(14).compactMap { d -> (String, Double, Double)? in
            guard let a = d.sleepStart, let b = d.sleepEnd else { return nil }
            return (d.day, Self.hours(a), Self.hours(b))
        }
        if nights.count >= 5, let bed = Stats.median(nights.map(\.1)), let wake = Stats.median(nights.map(\.2)) {
            NavigationLink { IntelSectionView(title: "Sueño y ritmo") } label: {
                PCard {
                    CardHeader(title: "Tu horario de sueño", subtitle: "Últimas \(nights.count) noches", chevron: true)
                    Text("Sueles acostarte hacia las \(Self.clock(bed)) y levantarte hacia las \(Self.clock(wake)).")
                        .font(.subheadline).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    Chart {
                        ForEach(nights, id: \.0) { n in
                            BarMark(x: .value("Noche", n.0), yStart: .value("Dormir", n.1), yEnd: .value("Despertar", n.2), width: .ratio(0.4))
                                .foregroundStyle(Color(white: 0.45))
                                .cornerRadius(2)
                        }
                        RuleMark(y: .value("Hora habitual de acostarte", bed)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.white.opacity(0.6))
                        RuleMark(y: .value("Hora habitual de levantarte", wake)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.white.opacity(0.6))
                    }
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartXScale(domain: nights.map(\.0))
                    .chartYAxis {
                        AxisMarks(position: .leading) { v in
                            AxisGridLine().foregroundStyle(Theme.hairline)
                            AxisValueLabel { Text(Self.clock((v.as(Double.self) ?? 0).rounded())).scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary) }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: IntelLoadPatternCard.ticks(nights.map(\.0), every: max(2, nights.count / 4))) { v in
                            AxisValueLabel { Text(Deviation.shortDate(v.as(String.self) ?? "")).scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary) }
                        }
                    }
                    .frame(height: 160)
                    Caps("- - - Tu hora habitual de acostarte y levantarte", size: 9, color: Theme.secondary, weight: .semibold)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Hours since 18:00 the day before, so a night draws as one block.
    static func hours(_ ts: Int) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        var h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        if h < 18 { h += 24 }
        return h
    }

    static func clock(_ h: Double) -> String {
        let m = Int((h * 60).rounded()) % (24 * 60)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

/// Mean recovery by weekday over the last 90 days.
struct IntelWeekdayPatternCard: View {
    @EnvironmentObject var model: AppModel
    static let letters = ["L", "M", "X", "J", "V", "S", "D"]
    static let names = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábados", "domingos"]
    static let minEach = 3

    var body: some View {
        let means = Self.means(model.days)
        PCard {
            CardHeader(title: "Según el día de la semana", subtitle: "Tu recuperación media de los últimos 90 días")
            if let means {
                Text(Self.sentence(means)).font(.subheadline).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Chart {
                    ForEach(0..<7, id: \.self) { i in
                        BarMark(x: .value("Día", Self.letters[i]), y: .value("Recuperación", means[i]), width: .ratio(0.5))
                            .foregroundStyle(Theme.recoveryColor(means[i]))
                            .cornerRadius(2)
                            .annotation(position: .top, spacing: 4) {
                                Text("\(Int(means[i].rounded()))").font(.system(size: 11, weight: .bold)).monospacedDigit()
                                    .foregroundStyle(Theme.recoveryColor(means[i]))
                            }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: Self.letters)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel { Text(v.as(String.self) ?? "").scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary) }
                    }
                }
                .frame(height: 130)
            } else {
                Text("Aparece cuando tengas al menos \(Self.minEach) recuperaciones de cada día de la semana.")
                    .font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Monday first; nil until every weekday has `minEach` recoveries.
    static func means(_ days: [DaySummary], calendar: Calendar = .current) -> [Double]? {
        var by = [[Double]](repeating: [], count: 7)
        guard let last = days.last?.day else { return nil }
        let from = DayKey.shift(last, days: -90, calendar: calendar)
        for d in days where d.day > from {
            guard let r = d.recovery, let date = DayKey.date(d.day, calendar: calendar) else { continue }
            by[(calendar.component(.weekday, from: date) + 5) % 7].append(r)
        }
        guard by.allSatisfy({ $0.count >= minEach }) else { return nil }
        return by.map { $0.reduce(0, +) / Double($0.count) }
    }

    static func sentence(_ m: [Double]) -> String {
        guard let hi = m.indices.max(by: { m[$0] < m[$1] }), let lo = m.indices.min(by: { m[$0] < m[$1] }) else { return "" }
        if m[hi] - m[lo] >= 5 {
            return "Sueles amanecer mejor los \(names[hi]) (\(Int(m[hi].rounded())) %) y peor los \(names[lo]) (\(Int(m[lo].rounded())) %)."
        }
        return "Tu recuperación es parecida todos los días de la semana: entre \(Int(m[lo].rounded())) y \(Int(m[hi].rounded())) %."
    }
}

// MARK: Tools

struct IntelToolsRow: View {
    let report: IntelligenceReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "Herramientas")
            HStack(spacing: 8) {
                tool("Simular", "slider.horizontal.3") { WhatIfView() }
                tool("Explorar", "point.3.connected.trianglepath.dotted") { RelationExplorerView() }
                tool("Calendario", "calendar") { CalendarRecordsView() }
                tool("Informe", "doc.richtext") { MonthlyReportView() }
            }
            NavigationLink { IntelMoreView() } label: {
                IntelAreaRow(area: IntelArea(section: "", icon: "square.grid.2x2", title: "Todas las métricas",
                                             value: IntelArea.readyText(report), caption: "Cada análisis con su fórmula, y los que faltan por desbloquear",
                                             color: Theme.link))
            }
            .buttonStyle(.plain)
        }
    }

    private func tool<D: View>(_ title: String, _ icon: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.link)
                Text(title).font(.caption).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }
}

/// One area of the analysis reduced to its headline number and one sentence.
struct IntelArea: Identifiable {
    let section: String
    let icon: String
    let title: String
    let value: String
    let caption: String
    let color: Color
    var id: String { title }

    static func rows(_ r: IntelligenceReport) -> [IntelArea] {
        var out: [IntelArea] = []
        func section(_ t: String) -> IntelligenceReport.Section? { r.sections.first { $0.title == t } }
        if let s = section("Respuesta a la carga") {
            let m = r.metric("recoveryVelocity").flatMap { $0.isAvailable ? $0 : nil } ?? s.metrics.first(where: \.isAvailable)
            out.append(IntelArea(section: s.title, icon: "figure.run", title: "Cómo asimilas el esfuerzo",
                                 value: m.map(headline) ?? "Pronto", caption: m.map { firstSentence($0.summary) } ?? lockedText(s),
                                 color: Theme.strain))
        }
        if let s = section("Sueño y ritmo") {
            let m = s.metrics.first(where: \.isAvailable)
            out.append(IntelArea(section: s.title, icon: "moon.stars", title: "Sueño y ritmo",
                                 value: m.map(headline) ?? "Pronto", caption: m.map { "\($0.name): " + firstSentence($0.summary) } ?? lockedText(s),
                                 color: Theme.sleep))
        }
        if let s = section("Hábitos y predicción") {
            let clear = r.habits.filter(\.isClear).sorted { abs($0.recoveryDelta) > abs($1.recoveryDelta) }
            let value: String, caption: String
            if let h = clear.first {
                value = (h.recoveryDelta >= 0 ? "+" : "−") + "\(Int(abs(h.recoveryDelta).rounded())) %"
                caption = "\(h.label.replacingOccurrences(of: "whoop:", with: "")) es lo que más mueve tu recuperación"
                    + (clear.count > 1 ? " (y \(clear.count - 1) más)." : ".")
            } else if !r.habits.isEmpty {
                value = "Sin efecto claro"
                caption = "Ningún hábito de tu diario cambia tu recuperación de forma clara todavía."
            } else {
                value = "Pronto"
                caption = "Registra el diario unos días para ver qué te ayuda y qué te afecta."
            }
            out.append(IntelArea(section: s.title, icon: "checklist", title: "Lo que más te afecta", value: value, caption: caption,
                                 color: Theme.hrv))
        }
        return out
    }

    static func headline(_ m: MetricResult) -> String {
        guard let v = m.value else { return "–" }
        if m.unit == "noches" && v < 1 { return "< 1 noche" }
        let unit = m.unit.count <= 8 ? " " + m.unit : ""
        return MetricFormat.value(v) + unit
    }

    static func firstSentence(_ s: String) -> String {
        if let r = s.range(of: ". ") { return String(s[..<r.lowerBound]) + "." }
        return s
    }

    static func lockedText(_ s: IntelligenceReport.Section) -> String {
        let ready = s.metrics.filter { !$0.isLocked }.count
        return "\(ready) de \(s.metrics.count) análisis listos: se activan cuando hay datos suficientes."
    }

    static func readyText(_ r: IntelligenceReport) -> String {
        let all = r.sections.flatMap(\.metrics)
        return "\(all.filter { !$0.isLocked }.count)/\(all.count)"
    }
}

struct IntelAreaRow: View {
    let area: IntelArea

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: area.icon).font(.title3).foregroundStyle(area.color)
                .frame(width: 42, height: 42)
                .background(area.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Caps(area.title, size: 11, weight: .semibold)
                    Spacer(minLength: 6)
                    Text(area.value).scaledFont(17, weight: .bold, design: .rounded, relativeTo: .body).monospacedDigit()
                        .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(area.caption).font(.caption).foregroundStyle(Theme.secondary)
                    .lineLimit(2).multilineTextAlignment(.leading)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.tertiary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Level 2: each area in full

/// «Tu estado» opened: today, why this %, last night's coherence and tomorrow.
struct IntelTodayView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        DetailScreen(title: "Tu estado") {
            AnalysisTodayCard()
            if let d = model.today ?? model.days.last(where: { $0.recovery != nil }) { WaterfallCard(day: d) }
            if let r = model.intelligence {
                CoherenceCard(report: r)
                ForecastCard(report: r)
                if let s = r.sections.first(where: { $0.title == "Hoy" }) {
                    IntelMetricList(metrics: s.metrics.filter { !["coherence", "forecast"].contains($0.id) })
                }
            }
        }
    }
}

/// One section of the report: its own cards first, then its metrics (each opens its detail).
struct IntelSectionView: View {
    @EnvironmentObject var model: AppModel
    let title: String

    var body: some View {
        let r = model.intelligence
        let section = r?.sections.first { $0.title == title }
        DetailScreen(title: title, subtitle: section?.subtitle) {
            if let r, let section {
                switch title {
                case "Respuesta a la carga":
                    if !r.fingerprints.isEmpty { FingerprintCard(items: r.fingerprints) }
                case "Hábitos y predicción":
                    ImpactCard(items: r.habits)
                    IntelLink(title: "Comportamientos", subtitle: "Qué ayuda y qué afecta a tu recuperación", icon: "chart.bar.xaxis") { BehaviorsView() }
                default:
                    EmptyView()
                }
                IntelMetricList(metrics: section.metrics)
            } else {
                EmptyState(icon: "sparkles", title: "Calculando", message: "Tu análisis aparece en unos segundos.")
            }
        }
    }
}

/// Ready metrics as cards; the ones still waiting for data folded into one line each.
struct IntelMetricList: View {
    let metrics: [MetricResult]

    var body: some View {
        let ready = metrics.filter { !$0.isLocked }
        let locked = metrics.filter(\.isLocked)
        ForEach(ready) { m in
            NavigationLink { MetricDetailView(metric: m) } label: { MetricCard(metric: m) }.buttonStyle(.plain)
        }
        if !locked.isEmpty {
            PCard {
                CardHeader(title: "Por desbloquear", subtitle: "Se activan solos cuando hay datos suficientes para que sean fiables")
                ForEach(locked) { m in
                    HStack {
                        Image(systemName: "lock").font(.caption).foregroundStyle(Theme.tertiary)
                        Text(m.name).font(.subheadline).foregroundStyle(.white)
                        Spacer()
                        if let u = m.unlock { Text("\(u.have)/\(u.need)").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary) }
                    }
                }
            }
        }
    }
}

/// Every analysis by area, each opening its metrics and formulas, plus what's still unlocking and the export.
struct IntelMoreView: View {
    @EnvironmentObject var model: AppModel
    @State private var exportURL: URL?

    var body: some View {
        DetailScreen(title: "Todas las métricas") {
            if let r = model.intelligence {
                let point = r.lastNight?.point ?? r.deviation.last
                NavigationLink { IntelTodayView() } label: {
                    IntelAreaRow(area: IntelArea(section: "Hoy", icon: "sun.max", title: "Tu estado",
                                                 value: point.map { CoherenceCard.word($0.coherence) } ?? "Pronto",
                                                 caption: "Coherencia de anoche, deuda fisiológica, previsión y coste cardíaco", color: Theme.green))
                }
                .buttonStyle(.plain)
                ForEach(IntelArea.rows(r)) { area in
                    NavigationLink { IntelSectionView(title: area.section) } label: { IntelAreaRow(area: area) }
                        .buttonStyle(.plain)
                }
                IntelLink(title: "Comportamientos", subtitle: "Qué ayuda y qué afecta a tu recuperación", icon: "chart.bar.xaxis") { BehaviorsView() }
                UnlockCard(report: r)
                PCard {
                    CardHeader(title: "Tus datos")
                    Button {
                        exportURL = model.exportIntelligence()
                    } label: {
                        Label("Exportar el análisis (CSV)", systemImage: "tablecells")
                    }
                    if let url = exportURL {
                        ShareLink(item: url) { Label("Compartir", systemImage: "square.and.arrow.up") }
                    }
                    Text("Métricas derivadas de tus propios datos y comparadas solo contigo. Muestran asociaciones, no causas, y no son un diagnóstico médico. Cuando no hay datos suficientes lo indican en vez de inventar un valor.")
                        .font(.caption).foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

struct IntelLink<D: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let destination: () -> D

    var body: some View {
        NavigationLink { destination() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.link).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
