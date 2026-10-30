import SwiftUI
import PulsoStore
import PulsoAnalytics

/// Recovery of the selected day: the dial, every vital against your last 30 days, what moved it and the week.
struct RecoveryDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAllChips = false

    var body: some View {
        DetailScreen(title: model.cycleTitle(model.selectedDay)) {
            if let day = model.selected {
                hero(day)
                effort(day)
                vitals(day)
                behaviours(day)
                RecoveryBreakdown(day: day)
                quality(day)
                SectionHeading(text: "Tendencias semanales")
                ForEach([TrendMetric.recovery, .hrv, .rhr, .respRate, .sleepPerformance], id: \.self) { m in
                    WeeklyTrendCard(metric: m)
                }
                ExplainerCard(title: TrendMetric.recovery.explainer.title, text: TrendMetric.recovery.explainer.text)
            } else {
                EmptyState(icon: "bolt.heart", title: "Sin recuperación", message: "Duerme con la pulsera y sincroniza por la mañana.")
            }
        }
    }

    private func hero(_ d: DaySummary) -> some View {
        let color = Theme.recoveryColor(d.recovery)
        return VStack(spacing: 0) {
            ZStack {
                Dial(progress: (d.recovery ?? 0) / 100, color: color, lineWidth: 22)
                VStack(spacing: 6) {
                    Text("PULSO").scaledFont(18, weight: .light, relativeTo: .body).tracking(4).foregroundStyle(Theme.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(d.recovery.map { "\(Int($0))" } ?? "–").scaledFont(64, weight: .heavy, relativeTo: .largeTitle, maxScale: 1.3).monospacedDigit()
                        if d.recovery != nil { Text("%").scaledFont(30, weight: .heavy, relativeTo: .title1) }
                    }
                    .foregroundStyle(.white)
                    Caps(d.calibrating && d.recovery == nil ? "Calibrando" : "Recuperación", size: 13)
                }
            }
            .frame(width: 270, height: 270)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func vitals(_ d: DaySummary) -> some View {
        let before = model.days.filter { $0.day < d.day }
        func usual(_ m: TrendMetric) -> Double? {
            TrendSeries.window(days: before, value: { m.value($0) }, period: .month, today: DayKey.shift(d.day, days: -1)).summary
        }
        let rows: [TrendMetric] = [.hrv, .rhr, .respRate, .sleepPerformance, .spo2, .skinTemp]
        return PCard(padding: 0, spacing: 0) {
            ForEach(rows) { m in
                NavigationLink {
                    TrendDetailView(metric: m)
                } label: {
                    let v = m.value(d), u = usual(m)
                    HStack(spacing: 12) {
                        Image(systemName: m.icon).foregroundStyle(Theme.secondary).frame(width: 24)
                        Caps(m.title, size: 12, weight: .semibold).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(v.map { m.label($0) } ?? "–")
                                    .scaledFont(22, weight: .bold, relativeTo: .title1).monospacedDigit().foregroundStyle(.white)
                                if v != nil { DeltaMark(delta: Delta(v, u, higherIsBetter: m.higherIsBetter)) }
                            }
                            if let u { Text(m.label(u)).scaledFont(11, relativeTo: .caption1).monospacedDigit().foregroundStyle(Theme.secondary) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                if m != rows.last { Divider().overlay(Theme.hairline).padding(.leading, 52) }
            }
            HStack(spacing: 6) {
                Image(systemName: "arrowtriangle.up.fill").foregroundStyle(Theme.better)
                Image(systemName: "arrowtriangle.down.fill").foregroundStyle(Theme.worse)
                Text("\(model.cycleTitle(d.day).capitalized) vs. los últimos 30 días").font(.caption).foregroundStyle(Theme.secondary)
            }
            .scaledFont(11, relativeTo: .caption1)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.25))
        }
    }

    /// Today's effort range, only when there's a real recovery behind it.
    private func effort(_ d: DaySummary) -> some View {
        let justified = d.recovery != nil && !d.calibrating
        let advice = model.coachAdvice(for: d)
        return PCard {
            HStack {
                Image(systemName: "flame").foregroundStyle(Theme.strain)
                Caps("Esfuerzo recomendado", size: 12)
                Spacer()
                if justified {
                    Text("\(Int(advice.strainTarget.lowerBound))–\(Int(advice.strainTarget.upperBound))")
                        .font(.headline.monospacedDigit()).foregroundStyle(.white)
                }
            }
            Text(justified ? advice.headline
                 : "Sin recomendación: hace falta una recuperación calculada con tus líneas base. Mientras tanto, guíate por cómo te encuentras.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    /// Which inputs went into the score, how mature the baselines are and where they came from.
    private func quality(_ d: DaySummary) -> some View {
        let before = model.days.filter { $0.day < d.day }
        let b = Baselines.from(history: before)
        let used = Set(d.contributors.map(\.key))
        let hrvNights = before.filter { ($0.hrv ?? 0) > 0 }.suffix(30)
        let imported = hrvNights.filter { $0.source != "strap" }.count
        let inputs: [(String, String, Bool, String)] = [
            ("hrv", "VFC", d.hrv != nil, b.lnHRV?.isUsable == true ? "" : "línea base calibrando"),
            ("rhr", "FC en reposo", d.rhr != nil, b.rhr?.isUsable == true ? "" : "línea base calibrando"),
            ("sleep", "Sueño", d.sleepPerformance != nil, ""),
            ("resp", "Respiración", d.respRate != nil, b.resp?.isUsable == true ? "" : "línea base calibrando"),
            ("temp", "Temperatura piel", d.skinTemp != nil, b.temp?.isUsable == true ? "" : "línea base calibrando"),
        ]
        return PCard {
            CardHeader(title: "Calidad de los datos")
            ForEach(inputs, id: \.0) { i in
                let on = used.contains(i.0)
                HStack(spacing: 10) {
                    Image(systemName: on ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(on ? Theme.better : Theme.secondary)
                    Text(i.1).font(.subheadline).foregroundStyle(.white)
                    Spacer()
                    Text(on ? "en el cálculo" : (i.2 ? (i.3.isEmpty ? "sin efecto hoy" : i.3) : "sin lectura"))
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "minus.circle").foregroundStyle(Theme.secondary)
                Text("SpO₂").font(.subheadline).foregroundStyle(.white)
                Spacer()
                Text("fuera (experimental)").font(.caption).foregroundStyle(Theme.secondary)
            }
            Divider().overlay(Theme.hairline)
            Text(hrvNights.isEmpty ? "Aún no hay noches anteriores con VFC: la recuperación aparece tras 4."
                 : "Líneas base: \(hrvNights.count) noches con VFC\(imported > 0 ? ", \(imported) importadas" : "")\(d.calibrating ? " · calibrando (hacen falta 4)" : "").")
                .font(.caption).foregroundStyle(Theme.secondary)
            if d.source != "strap" {
                Text("Este día es importado: sus valores vienen del archivo, no de la pulsera.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    /// What pushed the score up or down: the recovery contributors and yesterday's journal.
    private func behaviours(_ d: DaySummary) -> some View {
        let fromVitals = d.contributors.sorted { abs($0.impact) > abs($1.impact) }.filter { abs($0.impact) > 0.05 }.map {
            (text: $0.label, up: $0.impact > 0, color: $0.impact > 0 ? Theme.better : Theme.worse)
        }
        let yesterday = DayKey.shift(d.day, days: -1)
        let journal = model.journal(for: yesterday).filter { $0.value > 0 }.map {
            (text: JournalCatalog.label($0.key).replacingOccurrences(of: "whoop:", with: ""), up: Optional<Bool>.none, color: Theme.link)
        }
        let all: [(text: String, up: Bool?, color: Color)] = fromVitals.map { ($0.text, Optional($0.up), $0.color) } + journal
        return Group {
            if !all.isEmpty {
                PCard {
                    HStack {
                        Image(systemName: "lightbulb").foregroundStyle(Theme.secondary)
                        Caps("Información sobre comportamientos", size: 12)
                    }
                    Text("Esto es lo que más ha movido tu recuperación de hoy (y lo que apuntaste ayer en el diario).")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    if !journal.isEmpty {
                        Text("Asociación, no causa: lo del diario coincide con el día, no demuestra que lo haya provocado.")
                            .font(.caption).foregroundStyle(Theme.tertiary)
                    }
                    let shown = showAllChips ? all : Array(all.prefix(2))
                    FlowLayout(spacing: 8) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, c in
                            InsightChip(text: c.text, color: c.color, up: c.up)
                        }
                        if !showAllChips && all.count > 2 {
                            Button {
                                withAnimation { showAllChips = true }
                            } label: {
                                Text("+\(all.count - 2) más").scaledFont(13, weight: .semibold, relativeTo: .caption1).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(width, widest), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
