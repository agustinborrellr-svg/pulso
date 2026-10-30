import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

struct TrendsView: View {
    @EnvironmentObject var model: AppModel
    @State private var range: TrendRange = .month
    @State private var mode = 1
    @AppStorage("trends.extra") private var extraRaw = ""

    private var extra: Binding<[TrendMetric]> {
        Binding(
            get: { extraRaw.split(separator: ",").compactMap { TrendMetric(rawValue: String($0)) } },
            set: { extraRaw = $0.map(\.rawValue).joined(separator: ",") }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 28) {
                        tab("Inteligencia", 1)
                        tab("Tendencias", 0)
                        Spacer()
                    }
                    if mode == 1 {
                        IntelligenceContent()
                    } else {
                        trends
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(PulsoBackground())
            .pulsoTitle("Análisis")
        }
    }

    @ViewBuilder
    private var trends: some View {
        RangePicker(range: $range)
        MetricsMenu(extra: extra)
        if model.days.isEmpty {
            EmptyState(icon: "chart.xyaxis.line", title: "Sin datos todavía",
                       message: "Las tendencias aparecen cuando la pulsera haya registrado algunos días o importes tu historial.")
        } else {
            NotableChangesCard()
            ForEach(TrendMetric.main) { m in
                RangeTrendCard(metric: m, range: range)
            }
            let added = extra.wrappedValue.filter { !TrendMetric.main.contains($0) }
            ForEach(TrendMetric.Group.allCases, id: \.self) { g in
                let inGroup = added.filter { $0.group == g }
                if !inGroup.isEmpty {
                    SectionHeading(text: g.rawValue)
                    ForEach(inGroup) { m in
                        RangeTrendCard(metric: m, range: range) {
                            withAnimation(.easeInOut(duration: 0.25)) { extra.wrappedValue.removeAll { $0 == m } }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            CompareTrendsCard(range: range)
            TrainingLoadCard(points: model.trainingLoad.filter { $0.day >= DayKey.shift(model.currentDayKey, days: -89) })
            if model.profile.cycleTracking { CycleCard(days: model.days) }
            WeeklyCard(days: model.days)
            insightsCard
        }
    }

    private func tab(_ title: String, _ m: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { mode = m }
        } label: {
            VStack(spacing: 8) {
                Caps(title, size: 13, color: mode == m ? .white : Theme.secondary, weight: .semibold)
                Rectangle().fill(mode == m ? Color.white : Color.clear).frame(height: 2)
            }
            .fixedSize()
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }

    @ViewBuilder
    private var insightsCard: some View {
        Card {
            SectionTitle(title: "Qué te afecta", subtitle: "Tu diario vs la recuperación del día siguiente")
            if model.insights.isEmpty {
                Text("Registra tu diario (en Inicio) al menos 5 días con y 5 sin cada hábito y aquí verás su efecto real en ti.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            } else {
                ForEach(model.insights) { i in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.label).font(.subheadline).foregroundStyle(.white)
                            Text("\(i.yesCount) días sí · \(i.noCount) días no").font(.caption2).foregroundStyle(Theme.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%+.0f%%", i.recoveryDelta))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(i.recoveryDelta >= 0 ? Theme.green : Theme.red)
                            if let h = i.hrvDeltaPercent {
                                Text(String(format: "VFC %+.0f%%", h)).font(.caption2).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Acute (7 d) vs chronic (42 d) load and their ratio.
struct TrainingLoadCard: View {
    let points: [TrainingLoad.Point]

    var body: some View {
        if points.count >= 7 {
            let status = TrainingLoad.status(points)
            Card {
                HStack {
                    SectionTitle(title: "Carga de entrenamiento", subtitle: "Aguda 7 días · crónica 42 días")
                    Spacer()
                    if let r = points.last?.acwr {
                        Text(String(format: "%.2f", r)).font(.title3.bold().monospacedDigit()).foregroundStyle(color(status))
                    }
                }
                Chart {
                    ForEach(points, id: \.day) { p in
                        if let d = DayKey.date(p.day) {
                            LineMark(x: .value("Día", d, unit: .day), y: .value("Carga", p.atl), series: .value("Serie", "Aguda"))
                                .foregroundStyle(Theme.stress)
                            LineMark(x: .value("Día", d, unit: .day), y: .value("Carga", p.ctl), series: .value("Serie", "Crónica"))
                                .foregroundStyle(Theme.strain)
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 130)
                HStack(spacing: 14) {
                    Label("Aguda (fatiga)", systemImage: "circle.fill").foregroundStyle(Theme.stress)
                    Label("Crónica (forma)", systemImage: "circle.fill").foregroundStyle(Theme.strain)
                }
                .font(.caption2)
                Text("\(status.label). \(status.advice)").font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func color(_ s: TrainingLoad.Status) -> Color {
        switch s {
        case .optimal: return Theme.green
        case .overreaching: return Theme.yellow
        case .risk: return Theme.red
        default: return Theme.secondary
        }
    }
}

/// Estimated cycle phase from the nightly skin temperature (opt-in).
struct CycleCard: View {
    let days: [DaySummary]

    var body: some View {
        let e = CycleTracker.estimate(days)
        Card {
            SectionTitle(title: "Ciclo (estimado)", subtitle: "Temperatura de la piel por la noche")
            Text(e.phase.label).font(.headline).foregroundStyle(.white)
            if let next = e.nextPeriod {
                Text("Próximo periodo estimado: \(Fmt.dayTitle(next).lowercased())").font(.subheadline).foregroundStyle(Theme.secondary)
            }
            if let avg = e.averageCycleDays {
                Text("Duración media: \(Int(avg.rounded())) días").font(.caption).foregroundStyle(Theme.secondary)
            }
            if e.phase == .luteal {
                Text("En la fase lútea es normal que suban la FC en reposo y la temperatura y baje algo la VFC.")
                    .font(.caption).foregroundStyle(Theme.tertiary)
            }
            Text("Orientativo. No sirve como método anticonceptivo.").font(.caption2).foregroundStyle(Theme.tertiary)
        }
    }
}

/// This week vs last week.
struct WeeklyCard: View {
    let days: [DaySummary]

    var body: some View {
        let s = WeeklySummary.compute(days, endDay: DayKey.string(Date()))
        if s.recovery != nil || s.sleepMinutes != nil {
            Card {
                SectionTitle(title: "Últimos 7 días", subtitle: "Comparado con los 7 anteriores")
                Text(s.text.prefix(1).uppercased() + s.text.dropFirst()).font(.subheadline).foregroundStyle(.white)
            }
        }
    }
}
