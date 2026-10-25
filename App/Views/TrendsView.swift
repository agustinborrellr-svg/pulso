import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

struct TrendsView: View {
    @EnvironmentObject var model: AppModel
    @State private var range = 30

    private var window: [DaySummary] {
        let from = DayKey.shift(DayKey.string(Date()), days: -(range - 1))
        return model.days.filter { $0.day >= from }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Periodo", selection: $range) {
                        Text("7 días").tag(7)
                        Text("30 días").tag(30)
                        Text("90 días").tag(90)
                        Text("1 año").tag(365)
                    }
                    .pickerStyle(.segmented)

                    averages
                    TrendChart(title: "Recuperación", unit: "%", days: window, color: Theme.green, style: .bars,
                               value: { $0.recovery }, colorFor: { Theme.recoveryColor($0) }, domain: 0...100)
                    TrendChart(title: "VFC", unit: "ms", days: window, color: Theme.hrv, style: .line, value: { $0.hrv })
                    TrendChart(title: "FC en reposo", unit: "lpm", days: window, color: Theme.red, style: .line, value: { $0.rhr })
                    TrendChart(title: "Esfuerzo", unit: "", days: window, color: Theme.strain, style: .bars, value: { $0.strain }, domain: 0...21)
                    TrainingLoadCard(points: model.trainingLoad.filter { p in window.first.map { p.day >= $0.day } ?? false })
                    TrendChart(title: "Horas de sueño", unit: "h", days: window, color: Theme.sleep, style: .bars,
                               value: { $0.sleepMinutes.map { $0 / 60 } }, reference: { $0.sleepNeedMinutes.map { $0 / 60 } })
                    TrendChart(title: "Respiración", unit: "rpm", days: window, color: Theme.hrv, style: .line, value: { $0.respRate })
                    TrendChart(title: "Temperatura de la piel (desviación)", unit: "°C", days: window, color: Theme.yellow, style: .line,
                               value: { $0.skinTempDeviation })
                    TrendChart(title: "Estrés medio", unit: "", days: window, color: Theme.stress, style: .bars, value: { $0.stressAvg },
                               colorFor: { Theme.stressColor($0) }, domain: 0...3)
                    TrendChart(title: "VO₂máx estimado", unit: "", days: window, color: Theme.strain, style: .line, value: { $0.vo2max })
                    if model.profile.cycleTracking { CycleCard(days: model.days) }
                    WeeklyCard(days: model.days)
                    insightsCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Tendencias")
        }
    }

    private var averages: some View {
        let rec = Stats.mean(window.compactMap { $0.recovery })
        let hrv = Stats.mean(window.compactMap { $0.hrv })
        let strain = Stats.mean(window.compactMap { $0.strain })
        let sleep = Stats.mean(window.compactMap { $0.sleepMinutes })
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricTile(title: "Recuperación media", value: Fmt.int(rec), unit: "%", icon: "circle.circle", tint: Theme.recoveryColor(rec))
            MetricTile(title: "VFC media", value: Fmt.int(hrv), unit: "ms", icon: "waveform.path.ecg", tint: Theme.hrv)
            MetricTile(title: "Esfuerzo medio", value: Fmt.one(strain), icon: "flame", tint: Theme.strain)
            MetricTile(title: "Sueño medio", value: Fmt.hm(sleep), icon: "moon.zzz", tint: Theme.sleep)
        }
    }

    @ViewBuilder
    private var insightsCard: some View {
        Card {
            SectionTitle(title: "Qué te afecta", subtitle: "Tu diario vs la recuperación del día siguiente")
            if model.insights.isEmpty {
                Text("Registra tu diario (pestaña Hoy) al menos 5 días con y 5 sin cada hábito y aquí verás su efecto real en ti.")
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

struct TrendPointValue: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let reference: Double?
}

struct TrendChart: View {
    enum Style { case bars, line }

    let title: String
    let unit: String
    let days: [DaySummary]
    let color: Color
    let style: Style
    let value: (DaySummary) -> Double?
    var reference: ((DaySummary) -> Double?)?
    var colorFor: ((Double) -> Color)?
    var domain: ClosedRange<Double>?

    init(title: String, unit: String, days: [DaySummary], color: Color, style: Style,
         value: @escaping (DaySummary) -> Double?, reference: ((DaySummary) -> Double?)? = nil,
         colorFor: ((Double) -> Color)? = nil, domain: ClosedRange<Double>? = nil) {
        self.title = title
        self.unit = unit
        self.days = days
        self.color = color
        self.style = style
        self.value = value
        self.reference = reference
        self.colorFor = colorFor
        self.domain = domain
    }

    private var points: [TrendPointValue] {
        days.compactMap { d in
            guard let v = value(d), v.isFinite, let date = DayKey.date(d.day) else { return nil }
            return TrendPointValue(id: d.day, date: date, value: v, reference: reference?(d))
        }
    }

    var body: some View {
        let pts = points
        if pts.count >= 2 {
            Card {
                HStack {
                    SectionTitle(title: title)
                    Spacer()
                    if let last = pts.last {
                        Text(String(format: "%.1f %@", last.value, unit)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondary)
                    }
                }
                chart(pts)
                    .frame(height: 140)
            }
        }
    }

    @ViewBuilder
    private func chart(_ pts: [TrendPointValue]) -> some View {
        let avg = Stats.mean(pts.map { $0.value }) ?? 0
        let base = Chart {
            ForEach(pts) { p in
                switch style {
                case .bars:
                    BarMark(x: .value("Día", p.date, unit: .day), y: .value(title, p.value))
                        .foregroundStyle(colorFor?(p.value) ?? color)
                        .cornerRadius(3)
                case .line:
                    LineMark(x: .value("Día", p.date, unit: .day), y: .value(title, p.value))
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Día", p.date, unit: .day), y: .value(title, p.value))
                        .foregroundStyle(color)
                        .symbolSize(pts.count > 40 ? 8 : 24)
                }
                if let r = p.reference {
                    PointMark(x: .value("Día", p.date, unit: .day), y: .value("Referencia", r))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .symbol(.circle)
                        .symbolSize(10)
                }
            }
            RuleMark(y: .value("Media", avg))
                .foregroundStyle(Color.white.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        if let domain {
            base.chartYScale(domain: domain)
        } else {
            base.chartYScale(domain: .automatic(includesZero: false))
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
