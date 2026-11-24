import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// 50 · VO₂ máx: your estimate against people of your age and sex (five bands, percentile, the age median), its trend
/// (7 d · 30 d · 6 m with the "en la media" band), the age curves, what the estimate is made of, and what it is.
struct VO2MaxView: View {
    @EnvironmentObject var model: AppModel

    private var pairs: [(day: String, v: Double)] { model.days.compactMap { d in d.vo2max.map { (d.day, $0) } } }

    var body: some View {
        let age = model.profile.age, sex = model.profile.sex
        let latest = pairs.last
        DSScreen("VO₂ máx", subtitle: latest.map { "Estimado · \(DSFmt.dayMonth($0.day))" }, back: "Actividad") {
            if let latest {
                hero(latest.v, day: latest.day, age: age, sex: sex)
                DSMetricChartCard(spec: chartSpec(age: age, sex: sex))
            } else {
                DSEmptyState(icon: "lungs", title: "Aún no hay estimación",
                             message: "Necesita unas noches con la pulsera para tu FC en reposo.")
            }
            DSSectionHeader("Por edad")
            norms(age: age, sex: sex, you: latest?.v)
            inputs
            DSSectionHeader("Qué es")
            DSWhatIs(text: "El oxígeno máximo que tu cuerpo usa en ejercicio: el mejor reflejo de tu salud cardiovascular. Pulso lo estima sin prueba (Jurca 2005) con sexo, edad, IMC, FC en reposo y minutos en zonas 2-5; con 3 carreras en 90 días mandan las carreras.",
                     footnote: "Estimación, no prueba de laboratorio.")
        }
    }

    private func hero(_ v: Double, day: String, age: Int, sex: Sex) -> some View {
        let bands = VO2Norms.bands(age: age, sex: sex)
        let band = VO2Norms.band(v, age: age, sex: sex)
        let i = bands.firstIndex(of: band) ?? 2
        let lo = bands.first!.lower, hi = bands.last!.upper
        let p = { (x: Double) in (x - lo) / max(hi - lo, 1) }
        let old: (day: String, v: Double)? = pairs.last { $0.day <= DayKey.shift(day, days: -182) }
            ?? pairs.first.flatMap { $0.day < DayKey.shift(day, days: -60) ? $0 : nil }
        let who = sex == .female ? "mujeres" : (sex == .male ? "hombres" : "personas")
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt.dec(v)).dsFont(60, .semibold, relativeTo: .largeTitle, maxScale: 1.15).foregroundStyle(DS.t1)
                    Text("ml/kg/min").dsFont(15).foregroundStyle(DS.t2)
                    ActLevelLine(text: band.label, color: ActVO2.colors[i], ink: i == 2 ? DS.t2 : ActVO2.colors[i])
                    if let old, abs(v - old.v) >= 0.05 {
                        DSDelta(text: "\(Fmt.dec(abs(v - old.v))) desde \(DSFmt.month(old.day))", up: v > old.v,
                                color: v > old.v ? DSLevel.buena.ink : DSLevel.justa.ink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DSSideTable(rows: [("Percentil", "\(Int(VO2Norms.percentile(v, age: age, sex: sex).rounded()))"),
                                   ("Media de tu edad", Fmt.dec(VO2Norms.median(age: age, sex: sex)))], width: 170)
            }
            DSDivider()
            Text("Frente a \(who) de tu edad").dsFont(14).foregroundStyle(DS.t2)
            DSRangeBar(stretches: ActVO2.stretches(bands), marker: min(max(p(v), 0), 1), markerColor: DS.t1,
                       labels: bands.dropFirst().map { (p($0.lower), Fmt.dec($0.lower)) })
            HStack(spacing: 0) {
                ForEach(bands.indices, id: \.self) { j in
                    Text(["Bajo", "Bajo media", "Media", "Bueno", "Excelente"][j])
                        .dsFont(12.5, j == i ? .semibold : .regular).foregroundStyle(j == i ? DS.t1 : DS.t3)
                        .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
        .dsCard(padding: 16)
    }

    private func chartSpec(age: Int, sex: Sex) -> DSMetricSpec {
        let bands = VO2Norms.bands(age: age, sex: sex)
        let end = pairs.last?.day ?? model.currentDayKey
        func points(_ days: Int) -> [DSPoint] {
            let start = DayKey.shift(end, days: -(days - 1))
            return pairs.filter { $0.day >= start }.compactMap { p in DayKey.date(p.day).map { DSPoint(date: $0, value: p.v) } }
        }
        var spec = DSMetricSpec(title: "VO₂ máx", value: "")
        spec.color = DS.act
        spec.initialPeriod = .halfYear
        spec.series = [.week: points(7), .month: points(30), .halfYear: weekly(points(182))]
        spec.normal = bands[2].lower...bands[2].upper
        spec.format = { Fmt.dec($0) }
        spec.outWord = "Fuera"
        return spec
    }

    private func weekly(_ pts: [DSPoint]) -> [DSPoint] {
        guard let first = pts.first?.date else { return [] }
        var weeks: [Int: [Double]] = [:]
        for p in pts { weeks[Int(p.date.timeIntervalSince(first) / (7 * 86_400)), default: []].append(p.value) }
        return weeks.keys.sorted().map { w in
            let v = weeks[w] ?? []
            return DSPoint(date: first.addingTimeInterval(Double(w * 7 + 3) * 86_400), value: v.reduce(0, +) / Double(max(v.count, 1)))
        }
    }

    private func norms(age: Int, sex: Sex, you: Double?) -> some View {
        let ages = Array(stride(from: 20, through: 80, by: 5))
        let lines: [(String, Double, Color)] = [("Alto", 0.95, DS.buena), ("Medio", 0.5, DS.t2), ("Bajo", 0.05, DS.baja)]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ForEach(lines, id: \.0) { l in
                    HStack(spacing: 5) { DSDot(color: l.2); Text(l.0) }
                }
            }
            .dsFont(13).foregroundStyle(DS.t2)
            Chart {
                ForEach(lines, id: \.0) { l in
                    ForEach(ages, id: \.self) { a in
                        LineMark(x: .value("Edad", a), y: .value("VO₂", VO2Norms.value(percentile: l.1, age: a, sex: sex)), series: .value("p", l.0))
                            .foregroundStyle(l.2)
                            .interpolationMethod(.catmullRom)
                    }
                }
                if let you {
                    PointMark(x: .value("Edad", age), y: .value("VO₂", you))
                        .symbolSize(90)
                        .foregroundStyle(DS.act)
                        .annotation(position: .top) { Text("Tú").dsFont(13, .semibold).foregroundStyle(DS.act) }
                }
            }
            .chartXScale(domain: 20...80)
            .chartXAxis { AxisMarks(values: [20, 40, 60, 80]) { _ in AxisValueLabel().foregroundStyle(DS.t3) } }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(DS.sep)
                    AxisValueLabel().foregroundStyle(DS.t3)
                }
            }
            .frame(height: 170)
        }
        .dsCard(padding: 14)
    }

    /// What the estimate is made of, with your values (no made-up weights: the model's inputs only).
    @ViewBuilder
    private var inputs: some View {
        let p = model.profile
        let rhr = Stats.median(model.days.suffix(14).compactMap(\.rhr))
        let recent = model.days.suffix(28)
        let aerobic = recent.reduce(0.0) { $0 + $1.zoneMinutes.dropFirst().prefix(4).reduce(0, +) } / 4
        let bmi = p.heightCm > 0 ? p.weightKg / pow(p.heightCm / 100, 2) : nil
        let since = Int(Date().timeIntervalSince1970) - 90 * 86_400
        let runs = ((try? model.db.workouts(from: since, to: Int(Date().timeIntervalSince1970))) ?? [])
            .filter { ($0.distanceMeters ?? 0) > 0 && $0.durationMinutes >= 12 }.count
        DSSectionHeader("Con qué se calcula")
        DSGroup {
            if let rhr { DSRow(icon: "heart.fill", iconColor: DS.cor, label: "FC en reposo", subtitle: "tus noches", value: "\(Int(rhr.rounded())) lpm") }
            if !recent.isEmpty {
                DSRow(icon: "flame.fill", iconColor: DS.act, label: "Ejercicio aeróbico", subtitle: "zonas 2-5, por semana", value: DSFmt.duration(aerobic))
            }
            if let bmi { DSRow(icon: "gauge.with.dots.needle.50percent", label: "IMC", subtitle: "del perfil", value: Fmt.dec(bmi)) }
            DSRow(icon: "figure.run", iconColor: DS.act, label: "Carreras", subtitle: "con distancia, 90 días", value: "\(min(runs, 3)) de 3")
        }
    }
}
