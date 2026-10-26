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
            if let r = model.intelligence {
                IntelTodayCard(report: r)
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

/// Coherence of last night, its 30-night chart, and tomorrow's forecast with the simulator.
struct IntelTodayCard: View {
    @EnvironmentObject var model: AppModel
    let report: IntelligenceReport

    var body: some View {
        let points = Array(report.deviation.suffix(30))
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(title: "Coherencia de anoche", subtitle: "¿Encajan tus constantes con tu patrón?")
                    if let p = points.last {
                        Text("\(Int(p.coherence.rounded()))")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(Self.color(p.coherence))
                        + Text(" /100").font(.headline).foregroundStyle(Theme.secondary)
                    } else {
                        Text("–").font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                if let f = report.metric("forecast"), f.isAvailable, let v = f.value {
                    VStack(alignment: .trailing, spacing: 4) {
                        SectionTitle(title: "Mañana")
                        Text("\(Int(v))%").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.recoveryColor(v))
                        if let i = f.interval {
                            Text("\(Int(i.lowerBound))–\(Int(i.upperBound)) %").font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            if points.count >= 3 {
                Chart(points, id: \.day) { p in
                    if let d = DayKey.date(p.day) {
                        BarMark(x: .value("Noche", d, unit: .day), y: .value("Desviación", p.strain))
                            .foregroundStyle(p.strain > 1 ? (p.strain > 2 ? Theme.red : Theme.yellow) : Theme.green.opacity(0.7))
                            .cornerRadius(2)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading, values: [0, 1, 2, 3]) }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 90)
                Text("Desviación desfavorable de cada noche (en σ). Por encima de 1 = fuera de tu patrón habitual.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
            if let p = points.last {
                let top = p.contributors.filter { abs($0.z) >= 1 }.prefix(3)
                if !top.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(top), id: \.key) { c in
                            Text("\(c.label) \(c.z > 0 ? "↑" : "↓")\(String(format: "%.1f", abs(c.z)))σ")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background((c.adverse ? Theme.red : Theme.green).opacity(0.18), in: Capsule())
                                .foregroundStyle(c.adverse ? Theme.red : Theme.green)
                        }
                    }
                }
            }
            if report.outlook != nil {
                NavigationLink {
                    WhatIfView()
                } label: {
                    Label("Simular mañana: ¿y si duermo más, no bebo…?", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.red)
            }
        }
    }

    static func color(_ c: Double) -> Color { c >= 50 ? Theme.green : (c >= 10 ? Theme.yellow : Theme.red) }
}

struct ConfidencePill: View {
    let metric: MetricResult

    var body: some View {
        let ok = metric.isAvailable
        Text(ok ? "Confianza \(metric.confidence.label)" : "Faltan datos")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        guard metric.isAvailable else { return Theme.secondary }
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
            Text(metric.summary).font(.caption).foregroundStyle(metric.isAvailable ? Theme.secondary : Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(metric.isAvailable ? 1 : 0.7)
    }
}

enum MetricFormat {
    static func value(_ v: Double) -> String {
        if abs(v) >= 1000 { return Int(v.rounded()).formatted() }
        if abs(v - v.rounded()) < 0.05 { return String(Int(v.rounded())) }
        return String(format: "%.1f", v)
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
                Card {
                    SectionTitle(title: "Cómo se calcula")
                    Text(metric.formula).font(.footnote.monospaced()).foregroundStyle(.white)
                    LabeledContent("Observaciones", value: "\(metric.sampleSize)").font(.caption)
                    LabeledContent("Confianza", value: metric.confidence.label).font(.caption)
                    LabeledContent("Versión del algoritmo", value: metric.version).font(.caption)
                    if case .insufficient(let why) = metric.status {
                        Label("Necesita: \(why)", systemImage: "hourglass").font(.caption).foregroundStyle(Theme.yellow)
                    }
                }
                Text("Asociación estadística con tus propios datos; no implica causa ni es un diagnóstico.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
            .padding(16)
        }
        .background(PulsoBackground())
        .navigationTitle(metric.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func history(_ r: IntelligenceReport) -> some View {
        switch metric.id {
        case "coherence", "physDebt":
            let pts = Array(r.deviation.suffix(60))
            if pts.count >= 3 {
                Card {
                    SectionTitle(title: metric.id == "coherence" ? "Coherencia por noche" : "Deuda fisiológica")
                    Chart(pts, id: \.day) { p in
                        if let d = DayKey.date(p.day) {
                            LineMark(x: .value("Noche", d, unit: .day), y: .value("v", metric.id == "coherence" ? p.coherence : p.debt))
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
        case "recoveryVelocity", "recoveryEfficiency", "recoveryConsistency", "adaptation", "recoveryCeiling":
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
                            Text(e.recoveryNights.map { String(format: "%.1f noches", $0) } ?? "> 5 noches")
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
            SectionTitle(title: "Hábitos y recuperación", subtitle: "Efecto medio al día siguiente, con su margen de incertidumbre")
            let span = max(10, items.map { max(abs($0.interval.lowerBound), abs($0.interval.upperBound)) }.max() ?? 10)
            ForEach(items) { h in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(h.label).font(.subheadline)
                        Spacer()
                        Text(String(format: "%+.0f", h.recoveryDelta)).font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(h.isClear ? (h.recoveryDelta >= 0 ? Theme.green : Theme.red) : Theme.secondary)
                    }
                    GeometryReader { geo in
                        let w = geo.size.width
                        let x = { (v: Double) in w / 2 + CGFloat(v / span) * w / 2 }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.06)).frame(height: 6)
                            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 12).offset(x: w / 2)
                            Capsule()
                                .fill((h.isClear ? (h.recoveryDelta >= 0 ? Theme.green : Theme.red) : Theme.secondary).opacity(0.6))
                                .frame(width: max(3, x(h.interval.upperBound) - x(h.interval.lowerBound)), height: 6)
                                .offset(x: x(h.interval.lowerBound))
                            Circle().fill(.white).frame(width: 8, height: 8).offset(x: x(h.recoveryDelta) - 4)
                        }
                    }
                    .frame(height: 12)
                    Text("\(h.withCount) días con · \(h.withoutCount) sin\(h.isClear ? "" : " · sin efecto claro")")
                        .font(.caption2).foregroundStyle(Theme.tertiary)
                }
            }
        }
    }
}

/// "Gemelo digital": tomorrow's recovery under hypothetical choices.
struct WhatIfView: View {
    @EnvironmentObject var model: AppModel
    @State private var sleep = 7.5
    @State private var strain = 10.0
    @State private var alcohol = false
    @State private var caffeine = false
    @State private var lateMeal = false
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let o = model.intelligence?.outlook {
                    let f = RecoveryModel.scenario(o, sleepHours: sleep, alcohol: alcohol, caffeine: caffeine, lateMeal: lateMeal, strain: strain)
                    let base = o.model.forecast(o.todayInputs)
                    Card {
                        SectionTitle(title: "Recuperación prevista mañana")
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(f.value.rounded()))%").font(.system(size: 56, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.recoveryColor(f.value))
                                .contentTransition(.numericText())
                                .animation(.snappy, value: Int(f.value))
                            Spacer()
                            let diff = f.value - base.value
                            if abs(diff) >= 1 {
                                Text(String(format: "%+.0f vs lo habitual", diff)).font(.subheadline.bold())
                                    .foregroundStyle(diff > 0 ? Theme.green : Theme.red)
                            }
                        }
                        IntervalBar(value: f.value, interval: f.interval)
                        Text("Entre \(Int(f.interval.lowerBound)) y \(Int(f.interval.upperBound)) % (80 % de las veces).")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Card {
                        SectionTitle(title: "Esta noche")
                        VStack(alignment: .leading) {
                            Text("Dormir \(Fmt.hm(sleep * 60))").font(.subheadline)
                            Slider(value: $sleep, in: 4...10, step: 0.25).tint(Theme.sleep)
                        }
                        VStack(alignment: .leading) {
                            Text("Esfuerzo de hoy \(String(format: "%.1f", strain))").font(.subheadline)
                            Slider(value: $strain, in: 0...21, step: 0.5).tint(Theme.strain)
                        }
                        Toggle("Alcohol", isOn: $alcohol)
                        Toggle("Cafeína por la tarde", isOn: $caffeine)
                        Toggle("Cena tarde", isOn: $lateMeal)
                    }
                    Card {
                        SectionTitle(title: "Qué pesa en la predicción")
                        let x = scenarioInputs(o)
                        ForEach(Array(o.model.contributions(x).prefix(5).enumerated()), id: \.offset) { _, c in
                            HStack {
                                Text(c.name).font(.subheadline)
                                Spacer()
                                Text(String(format: "%+.0f", c.points)).font(.subheadline.monospacedDigit())
                                    .foregroundStyle(c.points >= 0 ? Theme.green : Theme.red)
                            }
                        }
                        Text("Puntos que suma o resta cada factor frente a un día medio tuyo.").font(.caption2).foregroundStyle(Theme.tertiary)
                    }
                    Text("Simulación basada en asociaciones de tus datos, no en causas. Sirve para orientarte, no es una garantía.")
                        .font(.caption2).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
                } else {
                    EmptyState(icon: "slider.horizontal.3", title: "Aún no hay modelo",
                               message: "Hacen falta unas tres semanas de días con recuperación para que el simulador aprenda cómo respondes.")
                }
            }
            .padding(16)
        }
        .background(PulsoBackground())
        .navigationTitle("Simulador")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded, let o = model.intelligence?.outlook else { return }
            loaded = true
            sleep = (o.usualSleepHours * 4).rounded() / 4
            strain = o.todayInputs[1]
            alcohol = o.todayInputs[5] > 0
            caffeine = o.todayInputs[6] > 0
            lateMeal = o.todayInputs[7] > 0
        }
    }

    private func scenarioInputs(_ o: RecoveryModel.Outlook) -> [Double] {
        var x = o.todayInputs
        x[1] = strain
        x[4] = sleep
        x[5] = alcohol ? 1 : 0
        x[6] = caffeine ? 1 : 0
        x[7] = lateMeal ? 1 : 0
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
