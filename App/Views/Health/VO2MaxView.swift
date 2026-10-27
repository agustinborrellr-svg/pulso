import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// VO₂ máx: your level against people of your age and sex, its trend and the age norms.
struct VO2MaxView: View {
    @EnvironmentObject var model: AppModel

    private var latest: Double? { model.days.last { $0.vo2max != nil }?.vo2max }

    var body: some View {
        let age = model.profile.age, sex = model.profile.sex
        DetailScreen(title: "VO₂ máx") {
            levelCard(age: age, sex: sex)
            NavigationLink { TrendDetailView(metric: .vo2max) } label: {
                PCard {
                    CardHeader(title: "Tu VO₂ máx en el tiempo", chevron: true)
                    let w = TrendSeries.window(days: model.days, value: { $0.vo2max }, period: .halfYear, today: model.currentDayKey)
                    MetricChart(metric: .vo2max, points: w.points, period: .halfYear, highlightLast: false, compact: true)
                        .frame(height: 170)
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
            normsCard(age: age, sex: sex)
            ExplainerCard(title: "¿Qué es el VO₂ máx?", text: TrendMetric.vo2max.explainer.text)
            ExplainerCard(title: "¿Cómo se estima?",
                          text: "Pulso usa la relación de Uth: VO₂ máx ≈ 15,3 × FC máxima / FC en reposo. Tu FC en reposo sale de tus noches y la máxima de la mayor que has alcanzado en los últimos 6 meses (o de la que pongas en tu perfil). Es una estimación: entrenar de verdad cerca de tu máximo y dormir con la pulsera la afinan. Las normas por edad son aproximadas, de registros de pruebas de esfuerzo en cinta.")
        }
    }

    private func levelCard(age: Int, sex: Sex) -> some View {
        let bands = VO2Norms.bands(age: age, sex: sex)
        let colors: [Color] = [Theme.worse, Color(red: 0.9, green: 0.75, blue: 0.2), Color(white: 0.75), Theme.hrv, Theme.better]
        let lo = bands.first!.lower, hi = bands.last!.upper
        return PCard {
            CardHeader(title: "Tu nivel de condición cardiovascular")
            if let v = latest {
                GeometryReader { geo in
                    let x = CGFloat(Stats.clamp((v - lo) / (hi - lo), 0, 1)) * geo.size.width
                    VStack(alignment: .leading, spacing: 4) {
                        VStack(spacing: 2) {
                            Text(Fmt.dec(v)).font(.title3.bold().monospacedDigit()).foregroundStyle(.white)
                            Image(systemName: "arrowtriangle.down.fill").font(.caption).foregroundStyle(.white)
                        }
                        .fixedSize()
                        .offset(x: min(max(0, x - 20), geo.size.width - 40))
                        HStack(spacing: 2) {
                            ForEach(0..<bands.count, id: \.self) { i in
                                Rectangle().fill(colors[i])
                                    .frame(width: max(2, geo.size.width * (bands[i].upper - bands[i].lower) / (hi - lo) - 2), height: 6)
                            }
                        }
                        HStack {
                            ForEach(0..<bands.count, id: \.self) { i in
                                Text("\(Int(bands[i].lower.rounded()))").font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondary)
                                if i < bands.count - 1 { Spacer() }
                            }
                        }
                    }
                }
                .frame(height: 78)
                let band = VO2Norms.band(v, age: age, sex: sex)
                Text("\(band.label) (\(Int(band.lower.rounded()))-\(Int(band.upper.rounded())) ml/kg/min)")
                    .font(.headline).foregroundStyle(.white)
                Text("Tu VO₂ máx está en el percentil \(Int(VO2Norms.percentile(v, age: age, sex: sex).rounded())) de las personas de tu edad y sexo.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            } else {
                Text("Aún no hay estimación: necesita unas noches con la pulsera para tu FC en reposo.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func normsCard(age: Int, sex: Sex) -> some View {
        let ages = Array(stride(from: 20, through: 80, by: 5))
        let lines: [(String, Double, Color)] = [("Alto (95.º percentil)", 0.95, Theme.better), ("Medio (50.º percentil)", 0.5, .white),
                                                ("Bajo (5.º percentil)", 0.05, Theme.worse)]
        return PCard {
            CardHeader(title: "VO₂ máx (ml/kg/min) por edad")
            Chart {
                ForEach(lines, id: \.0) { l in
                    ForEach(ages, id: \.self) { a in
                        LineMark(x: .value("Edad", a), y: .value("VO₂", VO2Norms.value(percentile: l.1, age: a, sex: sex)), series: .value("p", l.0))
                            .foregroundStyle(l.2)
                            .interpolationMethod(.catmullRom)
                    }
                }
                if let v = latest {
                    PointMark(x: .value("Edad", age), y: .value("VO₂", v))
                        .symbolSize(140)
                        .foregroundStyle(Theme.link)
                        .annotation(position: .top) { Text("Tú").font(.caption.bold()).foregroundStyle(Theme.link) }
                }
            }
            .chartXScale(domain: 20...80)
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(Theme.hairline); AxisValueLabel() } }
            .frame(height: 220)
            Caps("Edad (años)", size: 10, color: Theme.secondary, weight: .semibold).frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(lines, id: \.0) { l in
                HStack(spacing: 8) {
                    Rectangle().fill(l.2).frame(width: 14, height: 3)
                    Text(l.0).font(.subheadline).foregroundStyle(.white)
                }
            }
        }
    }
}
