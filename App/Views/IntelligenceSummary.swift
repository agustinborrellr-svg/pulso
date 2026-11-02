import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoIntelligence

// MARK: - «Inteligencia»: one verdict, then drill down

/// The analysis in layers: one sentence about your state, four rows with a single number each, and every row
/// opens the full analysis behind it (whose metrics open their own detail and formula).
struct IntelligenceContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            if let r = model.intelligence {
                IntelHeroCard(report: r)
                SectionHeading(text: "Profundiza")
                VStack(spacing: 10) {
                    ForEach(IntelArea.rows(r)) { area in
                        NavigationLink { IntelSectionView(title: area.section) } label: { IntelAreaRow(area: area) }
                            .buttonStyle(.plain)
                    }
                    NavigationLink { IntelMoreView() } label: {
                        IntelAreaRow(area: IntelArea(section: "", icon: "square.grid.2x2", title: "Herramientas",
                                                     value: IntelArea.readyText(r), caption: "Simulador, explorador, calendario e informe mensual",
                                                     color: Theme.link))
                    }
                    .buttonStyle(.plain)
                }
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
    }
}

/// The one thing to know: how usual last night was for you, the signal that stands out, and what to expect.
struct IntelHeroCard: View {
    @EnvironmentObject var model: AppModel
    let report: IntelligenceReport

    var body: some View {
        let point = report.lastNight?.point ?? report.deviation.last
        let day = model.today ?? model.days.last(where: { $0.recovery != nil })
        NavigationLink { IntelTodayView() } label: {
            PCard(padding: 18) {
                HStack {
                    Caps("Tu estado", size: 12, color: Theme.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.tertiary)
                }
                if let p = point {
                    Text(Self.verdict(p.coherence))
                        .scaledFont(30, weight: .bold, design: .rounded, relativeTo: .title1)
                        .foregroundStyle(CoherenceCard.color(p.coherence))
                    Text(Self.standout(p)).font(.subheadline).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Aún aprendiendo tu patrón").scaledFont(26, weight: .bold, design: .rounded, relativeTo: .title1).foregroundStyle(.white)
                    Text("Con unas noches más Pulso sabrá qué es normal para ti.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                if let d = day, d.recovery != nil {
                    Text(model.coachAdvice(for: d).headline).font(.subheadline).foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 0) {
                    stat("Hoy", Fmt.int(day?.recovery), "%", Theme.recoveryColor(day?.recovery))
                    let f = report.metric("forecast")?.value
                    stat("Mañana", f.map { "\(Int($0))" } ?? "–", f == nil ? "" : "%", Theme.recoveryColor(f))
                    stat("Coherencia", point.map { "\(Int($0.coherence.rounded()))" } ?? "–", "/100", point.map { CoherenceCard.color($0.coherence) } ?? Theme.secondary)
                }
                .padding(.top, 4)
            }
        }
        .buttonStyle(.plain)
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
        return "Lo que más se sale: \(s.label.lowercased()) \(dir) de lo habitual" + (s.adverse ? "." : ", y eso es buena señal.")
    }

    private func stat(_ k: String, _ v: String, _ unit: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(v).scaledFont(22, weight: .bold, design: .rounded, relativeTo: .title2).monospacedDigit().foregroundStyle(c)
                Text(unit).font(.caption2).foregroundStyle(Theme.secondary)
            }
            Caps(k, size: 9.5, color: Theme.secondary, weight: .semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Tools and everything that doesn't fit an area: simulator, explorer, calendar, report, export.
struct IntelMoreView: View {
    @EnvironmentObject var model: AppModel
    @State private var exportURL: URL?

    var body: some View {
        DetailScreen(title: "Herramientas") {
            IntelLink(title: "Simular mañana", subtitle: "Mueve sueño, esfuerzo y hábitos y mira tu recuperación esperada", icon: "slider.horizontal.3") { WhatIfView() }
            AnalysisToolsLinks()
            if let r = model.intelligence {
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
