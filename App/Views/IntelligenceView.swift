import SwiftUI
import Charts
import PulsoStore
import PulsoIntelligence

/// "Inteligencia": derived metrics, patterns and the personal forecast.
struct IntelligenceContent: View {
    @EnvironmentObject var model: AppModel
    @State private var exportURL: URL?

    var body: some View {
        VStack(spacing: 16) {
            AnalysisTodayCard()
            if let d = model.today ?? model.days.last(where: { $0.recovery != nil }) { WaterfallCard(day: d) }
            if let r = model.intelligence {
                UnlockCard(report: r)
                ImpactCard(items: r.habits)
                AnalysisToolsLinks()
                CoherenceCard(report: r)
                ForecastCard(report: r)
                ForEach(r.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: section.title, subtitle: section.subtitle)
                            .padding(.horizontal, 4)
                        ForEach(section.metrics) { m in
                            NavigationLink {
                                MetricDetailView(metric: m)
                            } label: {
                                MetricCard(metric: m)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !r.fingerprints.isEmpty { FingerprintCard(items: r.fingerprints) }
                if !r.habits.isEmpty { HabitsCard(items: r.habits) }
                Card {
                    SectionTitle(title: "Tus datos")
                    Button {
                        exportURL = model.exportIntelligence()
                    } label: {
                        Label("Exportar el análisis (CSV)", systemImage: "tablecells")
                    }
                    if let url = exportURL {
                        ShareLink(item: url) { Label("Compartir", systemImage: "square.and.arrow.up") }
                    }
                    Text("Métricas derivadas de tus propios datos y comparadas solo contigo. Muestran asociaciones, no causas, y no son un diagnóstico médico. Cuando no hay datos suficientes lo indican en vez de inventar un valor.")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiary)
                }
            } else {
                Card {
                    HStack {
                        ProgressView()
                        Text("Calculando tu análisis…").foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
    }
}

/// Last night's coherence: what the percentile means, each signal against its usual band, and 14 nights.
struct CoherenceCard: View {
    let report: IntelligenceReport
    var showsGuide = true

    var body: some View {
        let night = report.lastNight
        let point = night?.point ?? (night == nil ? report.deviation.last : nil)
        let metric = report.metric("coherence")
        PCard {
            CardHeader(title: "Coherencia de anoche",
                       subtitle: point.map { "Noche del \(Deviation.shortDate($0.day)) frente a tus \($0.baselineNights) noches anteriores" }
                           ?? "¿Encajan tus constantes con tu patrón?")
            if let p = point {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(p.coherence.rounded()))")
                        .scaledFont(44, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3).monospacedDigit()
                        .foregroundStyle(Self.color(p.coherence))
                    Text("/100").font(.headline).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(Self.word(p.coherence)).font(.subheadline.weight(.semibold)).foregroundStyle(Self.color(p.coherence))
                }
                Text("Percentil: el \(Int(p.coherence.rounded())) % de esas noches eran al menos igual de raras. Alto = noche típica para ti; bajo = combinación poco habitual (no siempre mala: mira hacia dónde va cada señal).")
                    .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    ForEach(p.signals, id: \.key) { SignalBar(signal: $0) }
                }
                Text("Barra gris: tu rango habitual (8 de cada 10 noches). Punto: anoche, en desviaciones (σ) desde tu mediana.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
                if p.mixesSources {
                    Label("Tu referencia mezcla \(p.importedInBaseline) noches importadas con \(p.baselineNights - p.importedInBaseline) medidas por Pulso. Miden VFC y temperatura de forma distinta: la comparación pierde precisión.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(Theme.yellow)
                }
            } else {
                Text("–").scaledFont(44, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3).foregroundStyle(Theme.secondary)
                Text(metric?.summary ?? "Sin datos de anoche.").font(.subheadline).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let history = Array(report.deviation.suffix(14))
            if history.count >= 3 {
                Caps("Últimas \(history.count) noches", size: 10, color: Theme.secondary, weight: .semibold)
                Chart(history, id: \.day) { p in
                    if let d = DayKey.date(p.day) {
                        BarMark(x: .value("Noche", d, unit: .day), y: .value("Coherencia", max(2, p.coherence)))
                            .foregroundStyle(Self.color(p.coherence).opacity(p.day == point?.day ? 1 : 0.55))
                            .cornerRadius(2)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .leading, values: [0, 10, 50, 100]) }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .frame(height: 80)
            }
            if showsGuide, let m = metric { HowCalculated(metric: m) }
        }
    }

    static func color(_ c: Double) -> Color { c >= 50 ? Theme.green : (c >= 10 ? Theme.yellow : Theme.red) }
    static func word(_ c: Double) -> String { c >= 50 ? "Típica" : (c >= 10 ? "Algo inusual" : "Muy inusual") }
}

/// One signal of last night on a −3…+3 σ track, with the band your baseline nights usually fall in.
struct SignalBar: View {
    let signal: Deviation.Contributor

    var body: some View {
        let off = abs(signal.z) >= 1
        let color = !off ? Theme.secondary : (signal.adverse ? Theme.worse : Theme.better)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(signal.label).font(.subheadline).foregroundStyle(.white)
                Spacer()
                Text("\(value(signal.value)) · tu mediana \(value(signal.usual))").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                Text(String(format: "%+.1f σ", signal.z)).font(.caption.bold().monospacedDigit()).foregroundStyle(color)
                    .frame(width: 52, alignment: .trailing)
            }
            GeometryReader { g in
                let w = g.size.width
                let x = { (z: Double) in CGFloat((min(max(z, -3), 3) + 3) / 6) * w }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06)).frame(height: 6)
                    Capsule().fill(Color.white.opacity(0.22))
                        .frame(width: max(4, x(signal.band.upperBound) - x(signal.band.lowerBound)), height: 6)
                        .offset(x: x(signal.band.lowerBound))
                    Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 12).offset(x: w / 2)
                    Circle().fill(color == Theme.secondary ? .white : color).frame(width: 10, height: 10).offset(x: x(signal.z) - 5)
                }
            }
            .frame(height: 12)
        }
    }

    private func value(_ v: Double) -> String {
        switch signal.key {
        case "hrv": return "\(Int(v.rounded())) ms"
        case "rhr": return "\(Int(v.rounded())) lpm"
        case "resp": return String(format: "%.1f rpm", v)
        default: return String(format: "%.2f °C", v)
        }
    }
}

/// Tomorrow's forecast and how far to trust it; opens the simulator.
struct ForecastCard: View {
    let report: IntelligenceReport

    var body: some View {
        if let f = report.metric("forecast"), let o = report.outlook {
            PCard {
                CardHeader(title: "Mañana", subtitle: "Recuperación esperada si duermes lo habitual")
                if let v = f.value, let i = f.interval {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(v))%").scaledFont(34, weight: .bold, design: .rounded, relativeTo: .title1).foregroundStyle(Theme.recoveryColor(v))
                        Text("entre \(Int(i.lowerBound)) y \(Int(i.upperBound)) %").font(.caption).foregroundStyle(Theme.secondary)
                        Spacer()
                    }
                    IntervalBar(value: v, interval: i)
                }
                ModelHonesty(outlook: o)
                NavigationLink {
                    WhatIfView()
                } label: {
                    Label("Simular mañana", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.red)
            }
        }
    }
}

/// The model's track record in one line: whether the forecast/simulator is worth anything for you yet.
struct ModelHonesty: View {
    let outlook: RecoveryModel.Outlook

    var body: some View {
        let reliable = (outlook.evaluation?.predictability ?? 0) > 0.05
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: reliable ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(reliable ? Theme.better : Theme.yellow)
            Text(text).font(.caption).foregroundStyle(reliable ? Theme.secondary : Theme.yellow)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var text: String {
        guard let ev = outlook.evaluation else {
            return "Aún sin validar: hacen falta \(RecoveryModel.minTrain + 5) pares de días (llevas \(outlook.model.n)). No te fíes todavía."
        }
        let pct = Int((ev.predictability * 100).rounded())
        if ev.predictability > 0.05 {
            return "Predictibilidad \(pct) %: acierta mejor que tu media de 7 días (error medio \(Int(ev.maeModel.rounded())) puntos frente a \(Int(ev.maeReference.rounded()))), probado en \(ev.tested) días."
        }
        return "Predictibilidad \(pct) %: no acierta mejor que tu media de 7 días (probado en \(ev.tested) días). El simulador aún no es fiable para ti."
    }
}

struct ConfidencePill: View {
    let metric: MetricResult

    var body: some View {
        Text(metric.isLocked ? "Faltan datos" : (metric.confidenceNote ?? "Confianza \(metric.confidence.label)"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        guard !metric.isLocked else { return Theme.secondary }
        switch metric.confidence {
        case .high: return Theme.green
        case .medium: return Theme.yellow
        case .low: return Theme.stress
        }
    }
}

struct MetricCard: View {
    let metric: MetricResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                ConfidencePill(metric: metric)
            }
            if metric.isAvailable, let v = metric.value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(MetricFormat.value(v)).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                    Text(metric.unit).font(.caption).foregroundStyle(Theme.secondary)
                    if let i = metric.interval {
                        Text("(\(MetricFormat.value(i.lowerBound)) a \(MetricFormat.value(i.upperBound)))").font(.caption).foregroundStyle(Theme.tertiary)
                    }
                }
            }
            Text(metric.summary).font(.caption).foregroundStyle(metric.isLocked ? Theme.tertiary : Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if let g = MetricGuide.of(metric.id) { Text(g.kind.label) }
                Text("n = \(metric.sampleSize)")
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(metric.isLocked ? 0.7 : 1)
    }
}

/// The same "Cómo se calcula" on every analysis: definition, formula, data, period, n, confidence, reading, limits.
struct HowCalculated: View {
    let id: String
    var formula: String?
    var n: Int?
    var confidence: String?
    var need: String?
    var startsOpen = false
    @State private var open: Bool?

    init(id: String, formula: String? = nil, n: Int? = nil, confidence: String? = nil, need: String? = nil, startsOpen: Bool = false) {
        self.id = id
        self.formula = formula
        self.n = n
        self.confidence = confidence
        self.need = need
        self.startsOpen = startsOpen
    }

    init(metric m: MetricResult, startsOpen: Bool = false) {
        var need: String?
        if case .insufficient(let why) = m.status { need = why }
        self.init(id: m.id, formula: m.formula, n: m.sampleSize,
                  confidence: m.confidenceNote ?? "\(m.confidence.label.capitalized) (según cuántos datos hay)", need: need, startsOpen: startsOpen)
    }

    var body: some View {
        let g = MetricGuide.of(id)
        DisclosureGroup(isExpanded: Binding(get: { open ?? startsOpen }, set: { open = $0 })) {
            VStack(alignment: .leading, spacing: 8) {
                if let g {
                    HStack(spacing: 6) {
                        Text(g.kind.label).font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.link.opacity(0.18), in: Capsule()).foregroundStyle(Theme.link)
                        Text(g.kind.explanation).font(.caption2).foregroundStyle(Theme.tertiary)
                    }
                    row("Definición", g.definition)
                }
                if let formula { row("Fórmula", formula, mono: true) }
                if let g {
                    row("Datos necesarios", g.data)
                    row("Periodo", g.period)
                }
                if let n { row("Observaciones (n)", "\(n)") }
                if let confidence { row("Confianza", confidence) }
                if let g {
                    row("Cómo leerlo", g.interpretation)
                    row("Limitaciones", g.limitations)
                }
                if let need { row("Necesita", need) }
            }
            .padding(.top, 6)
        } label: {
            Text("Cómo se calcula").font(.caption.weight(.semibold)).foregroundStyle(Theme.link)
        }
        .tint(Theme.link)
    }

    private func row(_ k: String, _ v: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Caps(k, size: 9, color: Theme.tertiary, weight: .semibold)
            Text(v).font(mono ? .caption2.monospaced() : .caption).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum MetricFormat {
    static func value(_ v: Double) -> String {
        if abs(v) >= 1000 { return Int(v.rounded()).formatted() }
        if abs(v - v.rounded()) < 0.05 { return String(Int(v.rounded())) }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
}

/// Everything about one metric: value, meaning, formula, reliability and its history.
struct MetricDetailView: View {
    @EnvironmentObject var model: AppModel
    let metric: MetricResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MetricCard(metric: metric)
                if let r = model.intelligence { history(r) }
                PCard {
                    HowCalculated(metric: metric, startsOpen: true)
                    Text("Versión del algoritmo \(metric.version)").font(.caption2).foregroundStyle(Theme.tertiary)
                }
                Text("Calculado solo con tus datos y comparado solo contigo. Ningún análisis de aquí demuestra una causa ni es un diagnóstico.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
            .padding(16)
        }
        .background(PulsoBackground())
        .pulsoTitle(metric.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func history(_ r: IntelligenceReport) -> some View {
        switch metric.id {
        case "coherence":
            CoherenceCard(report: r, showsGuide: false)
        case "physDebt":
            let pts = Array(r.deviation.suffix(60))
            if pts.count >= 3 {
                Card {
                    SectionTitle(title: "Deuda fisiológica")
                    Chart(pts, id: \.day) { p in
                        if let d = DayKey.date(p.day) {
                            LineMark(x: .value("Noche", d, unit: .day), y: .value("v", p.debt))
                                .foregroundStyle(Theme.red)
                                .interpolationMethod(.monotone)
                        }
                    }
                    .frame(height: 160)
                }
            }
        case "forecast", "predictability", "surprise":
            if let preds = r.outlook?.evaluation?.predictions, preds.count >= 3 {
                Card {
                    SectionTitle(title: "Predicho vs real", subtitle: "Cada día predicho solo con los días anteriores")
                    Chart(Array(preds.suffix(45)), id: \.day) { p in
                        if let d = DayKey.date(p.day) {
                            LineMark(x: .value("Día", d, unit: .day), y: .value("%", p.observed), series: .value("s", "Real"))
                                .foregroundStyle(Theme.green)
                            LineMark(x: .value("Día", d, unit: .day), y: .value("%", p.predicted), series: .value("s", "Predicho"))
                                .foregroundStyle(Theme.red)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 170)
                    HStack(spacing: 14) {
                        Label("Real", systemImage: "circle.fill").foregroundStyle(Theme.green)
                        Label("Predicho", systemImage: "circle.fill").foregroundStyle(Theme.red)
                    }
                    .font(.caption2)
                }
            }
        case "recoveryCeiling":
            LoadCeilingSections(report: r)
        case "recoveryVelocity", "recoveryEfficiency", "recoveryConsistency", "adaptation":
            let ev = Array(r.events.suffix(12).reversed())
            if !ev.isEmpty {
                Card {
                    SectionTitle(title: "Días exigentes recientes")
                    ForEach(ev, id: \.day) { e in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(e.sport) · \(e.intensity)").font(.subheadline)
                                Text("\(Fmt.dayTitle(e.day)) · esfuerzo \(String(format: "%.1f", e.strain))\(e.chained ? " · encadenado" : "")")
                                    .font(.caption2).foregroundStyle(Theme.tertiary)
                            }
                            Spacer()
                            Text(e.recoveryNights.map { String(format: "%.1f noches", $0) } ?? (e.censored ? "≥ 5 noches" : "sin medir"))
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        case "habits":
            HabitsCard(items: r.habits)
        default:
            EmptyView()
        }
    }
}

/// Per sport / intensity response profile.
struct FingerprintCard: View {
    let items: [LoadResponse.Fingerprint]

    var body: some View {
        Card {
            SectionTitle(title: "Tu huella de respuesta", subtitle: "Qué te provoca cada tipo de esfuerzo (medianas)")
            ForEach(items) { f in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(f.sport) · \(f.intensity)").font(.subheadline.bold())
                    HStack(spacing: 12) {
                        stat("Recuperas", f.recoveryNights.map { String(format: "%.1f n", $0) } ?? "–")
                        stat("VFC", f.hrvChangePct.map { String(format: "%+.0f%%", $0) } ?? "–")
                        stat("FC reposo", f.rhrChange.map { String(format: "%+.0f", $0) } ?? "–")
                        stat("Coste", String(format: "%.1f", f.cost))
                    }
                    Text("\(f.count) sesiones").font(.caption2).foregroundStyle(Theme.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.caption.bold().monospacedDigit())
            Text(k).font(.caption2).foregroundStyle(Theme.tertiary)
        }
    }
}

/// Habit effects with their 90 % intervals drawn as bars around zero.
struct HabitsCard: View {
    let items: [HabitImpact.Item]

    var body: some View {
        Card {
            SectionTitle(title: "Hábitos y recuperación", subtitle: "Diferencia media al día siguiente, con vs sin, con su margen 90 %")
            let span = max(10, items.map { max(abs($0.interval.lowerBound), abs($0.interval.upperBound)) }.max() ?? 10)
            ForEach(items) { h in
                let tint = h.isClear ? (h.recoveryDelta >= 0 ? Theme.better : Theme.worse) : Theme.secondary
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(h.label).font(.subheadline)
                        Spacer()
                        Text(h.isClear ? String(format: "%+.0f", h.recoveryDelta) : "no claro").font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(tint)
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        let x = { (v: Double) in w / 2 + CGFloat(v / span) * w / 2 }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.06)).frame(height: 6)
                            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 12).offset(x: w / 2)
                            Capsule().fill(tint.opacity(0.6))
                                .frame(width: max(3, x(h.interval.upperBound) - x(h.interval.lowerBound)), height: 6)
                                .offset(x: x(h.interval.lowerBound))
                            Circle().fill(.white).frame(width: 8, height: 8).offset(x: x(h.recoveryDelta) - 4)
                        }
                    }
                    .frame(height: 12)
                    Text(HabitText.counts(h)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.tertiary)
                }
            }
            Text(HabitText.footnote(items.count)).font(.caption2).foregroundStyle(Theme.tertiary)
        }
    }
}

enum HabitText {
    static func counts(_ h: HabitImpact.Item) -> String {
        "n = \(h.n) (\(h.withCount) con · \(h.withoutCount) sin) · q = \(String(format: "%.2f", h.qValue)) · confianza \(h.confidence.label)"
    }

    static func footnote(_ count: Int) -> String {
        "Asociación, no causa: esos días pueden diferir en otras cosas. Solo cuentan los días en que se preguntó por cada hábito. Con \(count) hábitos comparados se corrige por comparaciones múltiples: «claro» exige que el margen no cruce 0 y q < 0,10 (Benjamini–Hochberg)."
    }
}

/// «Techo de carga» in full: tolerable load, recovery, pulse recovery, adaptation, trends and limits.
struct LoadCeilingSections: View {
    let report: IntelligenceReport

    var body: some View {
        let c = LoadResponse.ceiling(report.events)
        let ceiling = report.metric("recoveryCeiling")
        PCard {
            CardHeader(title: "Carga tolerable", subtitle: "Noches hasta recuperarte según el esfuerzo de los 3 días")
            if c.points.count >= 3 {
                Chart {
                    ForEach(c.points, id: \.day) { p in
                        PointMark(x: .value("Esfuerzo 3 días", p.load), y: .value("Noches", p.nights))
                            .symbol(p.censored ? .triangle : .circle)
                            .foregroundStyle(p.censored ? Theme.worse : Theme.link.opacity(0.8))
                    }
                    if let k = c.knee {
                        RuleMark(x: .value("Codo", k)).foregroundStyle(Theme.yellow).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYScale(domain: 0...5.5)
                .frame(height: 170)
                Text("Triángulos: no te recuperaste en 5 noches (cuentan como «5 o más»). Línea amarilla: el codo.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
            Text(ceiling?.summary ?? "").font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        section("Recuperación", "Noches hasta volver a tu patrón", report.metric("recoveryVelocity"),
                extra: c.overloads > 0 ? "\(c.overloads) de \(c.points.count) días exigentes siguieron fuera de rango 5 noches después." : nil)
        PCard {
            CardHeader(title: "Recuperación del pulso a 60 s", subtitle: "Cuánto baja tu pulso al terminar cada entreno")
            let drops = report.hrrDrops.suffix(20)
            if drops.count >= 3 {
                Chart(Array(drops.enumerated()), id: \.offset) { _, d in
                    if let date = DayKey.date(d.day) {
                        PointMark(x: .value("Día", date, unit: .day), y: .value("lpm", d.drop)).foregroundStyle(Theme.red)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 120)
            }
            if let m = report.metric("hrr60") {
                Text(m.summary).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        section("Adaptación", "A igual esfuerzo, ¿te desajustas menos con el tiempo?", report.metric("adaptation"))
        PCard {
            CardHeader(title: "Tendencias", subtitle: "Tus últimos días exigentes frente a los anteriores")
            ForEach(trends(), id: \.0) { t in
                LabeledContent(t.0, value: t.1).font(.subheadline)
            }
        }
        PCard {
            CardHeader(title: "Límites de interpretación")
            Text("• Es una hipótesis sobre tus datos: solo vale dentro de las cargas que ya has hecho.\n• «No se ve límite» significa que no hay codo en ese rango, no que no exista.\n• Los días que no se recuperan en 5 noches cuentan como 5: el tiempo real puede ser mayor.\n• Sueño, enfermedad o estrés de esos días también alargan la recuperación; no se separan.")
                .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if let m = ceiling { HowCalculated(metric: m) }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ subtitle: String, _ m: MetricResult?, extra: String? = nil) -> some View {
        PCard {
            CardHeader(title: title, subtitle: subtitle)
            if let m {
                if m.isAvailable, let v = m.value {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(MetricFormat.value(v)).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                        Text(m.unit).font(.caption).foregroundStyle(Theme.secondary)
                        if let i = m.interval {
                            Text("(\(MetricFormat.value(i.lowerBound)) a \(MetricFormat.value(i.upperBound)))").font(.caption).foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                        ConfidencePill(metric: m)
                    }
                }
                Text(m.summary).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let extra { Text(extra).font(.caption).foregroundStyle(Theme.worse) }
        }
    }

    private func trends() -> [(String, String)] {
        let ev = report.events.filter { !$0.chained }
        let recent = ev.suffix(8), earlier = ev.dropLast(8).suffix(8)
        func med(_ x: [Double]) -> Double? {
            guard !x.isEmpty else { return nil }
            let s = x.sorted()
            return s[s.count / 2]
        }
        func pair(_ f: (LoadResponse.Event) -> Double?, _ fmt: String) -> String {
            let a = med(recent.compactMap(f)), b = med(earlier.compactMap(f))
            guard let a else { return "–" }
            guard let b, earlier.count >= 4 else { return String(format: fmt, a) }
            return String(format: fmt, a) + " (antes " + String(format: fmt, b) + ")"
        }
        return [
            ("Días exigentes", "\(recent.count) recientes · \(earlier.count) anteriores"),
            ("Esfuerzo 3 días (mediana)", pair({ $0.load3d }, "%.0f")),
            ("Noches hasta recuperarte", pair({ $0.nightsAtLeast }, "%.1f")),
            ("Coste de recuperación", pair({ $0.cost }, "%.1f")),
        ]
    }
}

/// What-if for tomorrow: a few levers, the expected range, and how far the model can be trusted.
struct WhatIfView: View {
    @EnvironmentObject var model: AppModel
    @State private var sleep = 7.5
    @State private var strain = 10.0
    @State private var habits = [false, false, false]
    @State private var loaded = false

    private static let habitLabels = ["Alcohol", "Cafeína por la tarde", "Cena tarde"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let o = model.intelligence?.outlook {
                    let f = RecoveryModel.scenario(o, sleepHours: sleep, alcohol: habits[0], caffeine: habits[1], lateMeal: habits[2], strain: strain)
                    let base = o.model.forecast(o.todayInputs)
                    let reliable = (o.evaluation?.predictability ?? 0) > 0.05
                    PCard {
                        CardHeader(title: "Recuperación esperada mañana")
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(f.interval.lowerBound))–\(Int(f.interval.upperBound)) %")
                                .scaledFont(40, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3).monospacedDigit()
                                .foregroundStyle(reliable ? Theme.recoveryColor(f.value) : Theme.secondary)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: Int(f.value))
                            Spacer()
                            let diff = f.value - base.value
                            if abs(diff) >= 1 {
                                Text(String(format: "%+.0f vs lo habitual", diff)).font(.subheadline.bold())
                                    .foregroundStyle(diff > 0 ? Theme.better : Theme.worse)
                            }
                        }
                        IntervalBar(value: f.value, interval: f.interval)
                        Text("Centro \(Int(f.value.rounded())) %. El rango cubre 8 de cada 10 errores pasados del modelo.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                        ModelHonesty(outlook: o)
                    }
                    PCard {
                        CardHeader(title: "Esta noche")
                        VStack(alignment: .leading) {
                            Text("Dormir \(Fmt.hm(sleep * 60))").font(.subheadline)
                            Slider(value: $sleep, in: 4...10, step: 0.25).tint(Theme.sleep)
                        }
                        VStack(alignment: .leading) {
                            Text("Esfuerzo de hoy \(String(format: "%.1f", strain))").font(.subheadline)
                            Slider(value: $strain, in: 0...21, step: 0.5).tint(Theme.strain)
                        }
                        ForEach(0..<3, id: \.self) { i in
                            if o.model.usesHabit(i) {
                                Toggle(Self.habitLabels[i], isOn: $habits[i])
                            } else {
                                LabeledContent(Self.habitLabels[i]) {
                                    Text("necesita \(RecoveryModel.minHabitDays) días con (llevas \(i < o.model.habitDays.count ? o.model.habitDays[i] : 0))")
                                        .font(.caption).foregroundStyle(Theme.tertiary)
                                }
                            }
                        }
                    }
                    .tint(Theme.green)
                    PCard {
                        CardHeader(title: "Qué pesa", subtitle: "Puntos frente a un día medio tuyo")
                        ForEach(Array(o.model.contributions(inputs(o)).prefix(4).enumerated()), id: \.offset) { _, c in
                            HStack {
                                Text(c.name).font(.subheadline)
                                Spacer()
                                Text(String(format: "%+.0f", c.points)).font(.subheadline.monospacedDigit())
                                    .foregroundStyle(c.points >= 0 ? Theme.better : Theme.worse)
                            }
                        }
                        if let m = model.intelligence?.metric("forecast") { HowCalculated(metric: m) }
                    }
                    Text("Estimación con asociaciones de tus datos, no con causas: orienta, no garantiza.")
                        .font(.caption2).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
                } else {
                    EmptyState(icon: "slider.horizontal.3", title: "Aún no hay modelo",
                               message: "Hacen falta unas tres semanas de días con recuperación para que el simulador aprenda cómo respondes.")
                }
            }
            .padding(16)
        }
        .background(PulsoBackground())
        .pulsoTitle("Simulador")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let o = model.intelligence?.outlook else { return }
            loaded = true
            sleep = (o.usualSleepHours * 4).rounded() / 4
            strain = o.todayInputs[1]
            habits = (0..<3).map { o.model.usesHabit($0) && o.todayInputs[RecoveryModel.firstHabitFeature + $0] > 0 }
        }
    }

    private func inputs(_ o: RecoveryModel.Outlook) -> [Double] {
        var x = o.todayInputs
        x[1] = strain
        x[4] = sleep
        for i in 0..<3 { x[RecoveryModel.firstHabitFeature + i] = habits[i] ? 1 : 0 }
        return x
    }
}

struct IntervalBar: View {
    let value: Double
    let interval: ClosedRange<Double>

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                LinearGradient(colors: [Theme.red, Theme.yellow, Theme.green], startPoint: .leading, endPoint: .trailing)
                    .opacity(0.25)
                    .clipShape(Capsule())
                Capsule().fill(Theme.recoveryColor(value).opacity(0.6))
                    .frame(width: max(4, CGFloat((interval.upperBound - interval.lowerBound) / 100) * w))
                    .offset(x: CGFloat(interval.lowerBound / 100) * w)
                Circle().fill(.white).frame(width: 12, height: 12).offset(x: CGFloat(value / 100) * w - 6)
            }
            .animation(.snappy, value: value)
        }
        .frame(height: 12)
    }
}
