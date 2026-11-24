import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

// Metric details of Actividad (studio C 51–54): pasos and calorías on the shared template, zonas and carga with their
// own hero and chart. Only real data; parts without data are left out.

// MARK: - 51 Pasos

struct StepsDetailView: View {
    var body: some View {
        DSTrendMetricDetail(metric: .steps, title: "Pasos", back: "Actividad", color: DS.act)
    }
}

// MARK: - 52 Calorías

struct CaloriesDetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        DSTrendMetricDetail(metric: .calories, title: "Calorías", back: "Actividad", color: DS.act) {
            if let d = model.selected, let kcal = d.kcal, let active = d.activeKcal, kcal > 0 {
                let workouts = model.workouts(for: d).reduce(0) { $0 + $1.kcal }
                let basal = max(0, kcal - active)
                let rest = max(0, active - workouts)
                let parts: [(String, Double, Color)] = [("Basal", basal, DS.fill2), ("Entrenos", workouts, DS.act), ("Resto del día", rest, DS.zone(1))]
                    .filter { $0.1 >= 1 }
                DSSectionHeader("De dónde salen", note: model.selectedDay >= model.currentDayKey ? "hoy" : DSFmt.dayMonth(d.day))
                VStack(spacing: 10) {
                    GeometryReader { g in
                        let gap: CGFloat = 3
                        let usable = g.size.width - gap * CGFloat(max(0, parts.count - 1))
                        HStack(spacing: gap) {
                            ForEach(parts.indices, id: \.self) { i in
                                Capsule().fill(parts[i].2).frame(width: max(4, usable * CGFloat(parts[i].1 / kcal)))
                            }
                        }
                    }
                    .frame(height: 10)
                    ForEach(parts.indices, id: \.self) { i in
                        if i > 0 { DSDivider() }
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(parts[i].2).frame(width: 9, height: 9)
                            Text(parts[i].0).dsFont(16).foregroundStyle(DS.t1)
                            Spacer()
                            HoyValue(value: DSFmt.thousands(parts[i].1), unit: "kcal", size: 17)
                        }
                        .frame(minHeight: 40)
                    }
                }
                .dsCard(padding: 14)
            }
        }
    }
}

// MARK: - 54 Zonas de FC

struct ZonesDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var period: DSPeriod = .week

    var body: some View {
        let day = model.selected
        let zones = Array((day?.zoneMinutes ?? [0, 0, 0, 0, 0]).prefix(5))
        let light = zones.prefix(3).reduce(0, +), hard = zones.dropFirst(3).reduce(0, +)
        let m = model.heartRateModel
        DSScreen("Zonas de FC", subtitle: day.map { DSFmt.shortDate($0.day) }, back: "Actividad") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    hero("Zonas 1-3", light, "base aeróbica")
                    hero("Zonas 4-5", hard, "potencia")
                }
                ZoneBar(minutes: zones).frame(height: 10)
                DSDivider()
                VStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { z in
                        if z > 1 { DSDivider() }
                        ActZoneRow(zone: z, range: ActZones.text(z, m), trailing: ActFmt.hmm(zones[z - 1]))
                    }
                }
            }
            .dsCard(padding: 14)

            chartCard(end: day?.day ?? model.currentDayKey)

            DSSectionHeader("Qué es")
            DSWhatIs(text: "Las zonas salen de tu reserva de FC (FC máx − FC en reposo). Las 1-3 construyen la base aeróbica; las 4-5, la potencia. Para la salud: mucho tiempo en 2-3 y algo en 4-5 cada semana.",
                     footnote: "No es un dispositivo médico.")
        }
    }

    private func hero(_ k: String, _ minutes: Double, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).dsFont(14).foregroundStyle(DS.t2)
            ActDurationValue(minutes: minutes, size: 48)
            Text(note).dsFont(15).foregroundStyle(DS.t2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Per day (7 d / 30 d) or per week (6 m): minutes in 1-3 and in 4-5, stacked.
    private func chartCard(end: String) -> some View {
        let n = period.days
        let keys = (0..<n).map { DayKey.shift(end, days: $0 - (n - 1)) }
        var bars: [(label: String, light: Double, hard: Double)] = keys.map { k in
            let z = model.day(k)?.zoneMinutes ?? []
            return (label: k, light: z.prefix(3).reduce(0, +), hard: z.dropFirst(3).prefix(2).reduce(0, +))
        }
        if period == .halfYear {
            bars = stride(from: 0, to: bars.count, by: 7).map { i in
                let chunk = bars[i..<min(bars.count, i + 7)]
                return (label: chunk.first!.label, light: chunk.reduce(0) { $0 + $1.light }, hard: chunk.reduce(0) { $0 + $1.hard })
            }
        }
        let week = keys.suffix(7).compactMap { model.day($0)?.zoneMinutes }
        let weekLight = week.reduce(0) { $0 + $1.prefix(3).reduce(0, +) }
        let weekHard = week.reduce(0) { $0 + $1.dropFirst(3).prefix(2).reduce(0, +) }
        let hardDays = week.filter { $0.dropFirst(3).prefix(2).reduce(0, +) >= 1 }.count
        let top = max(60, bars.map { $0.light + $0.hard }.max() ?? 60)
        return VStack(alignment: .leading, spacing: 12) {
            DSSegmented(options: DSPeriod.standard.map { ($0, $0.label) }, selection: $period).frame(width: 190)
            HStack(spacing: 14) {
                HStack(spacing: 5) { DSDot(color: DS.zone(1)); Text("Zonas 1-3") }
                HStack(spacing: 5) { DSDot(color: DS.zone(5)); Text("Zonas 4-5") }
            }
            .dsFont(13).foregroundStyle(DS.t2)
            Chart {
                ForEach(Array(bars.enumerated()), id: \.offset) { i, b in
                    BarMark(x: .value("d", i), y: .value("min", b.light / 60))
                        .foregroundStyle(i == bars.count - 1 ? DS.zone(2) : DS.zone(2).opacity(0.5))
                        .cornerRadius(3)
                    BarMark(x: .value("d", i), y: .value("min", b.hard / 60))
                        .foregroundStyle(DS.zone(5))
                        .cornerRadius(3)
                }
            }
            .chartXScale(domain: -0.6...(Double(bars.count) - 0.4))
            .chartYScale(domain: 0...(top / 60) * 1.1)
            .chartXAxis {
                AxisMarks(values: xMarks(bars.count)) { v in
                    AxisValueLabel {
                        if let i = v.as(Int.self), i < bars.count {
                            Text(period == .week ? ActWeek.initial(bars[i].label) : DSFmt.dayMonth(bars[i].label))
                                .dsFont(11, i == bars.count - 1 ? .bold : .medium, relativeTo: .caption2)
                                .foregroundStyle(i == bars.count - 1 ? DS.t1 : DS.t3)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine().foregroundStyle(DS.sep)
                    AxisValueLabel { Text("\(Fmt.dec(v.as(Double.self) ?? 0)) h").dsFont(11, relativeTo: .caption2).foregroundStyle(DS.t3) }
                }
            }
            .frame(height: 160)
            DSDivider()
            DSStatStrip(stats: [
                DSStat(label: "Semana 1-3", value: DSFmt.duration(weekLight)),
                DSStat(label: "Semana 4-5", value: DSFmt.duration(weekHard)),
                DSStat(label: "Días con 4-5", value: "\(hardDays)", unit: "de \(week.count)"),
            ])
        }
        .dsCard(padding: 14)
    }

    private func xMarks(_ n: Int) -> [Int] {
        if n <= 7 { return Array(0..<n) }
        let step = max(1, n / 4)
        return Array(stride(from: n - 1, through: 0, by: -step)).reversed()
    }
}

// MARK: - 53 Carga de entrenamiento

struct LoadDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var period: DSPeriod = .month

    var body: some View {
        let series = model.trainingLoad
        let last = series.last
        let status = TrainingLoad.status(series)
        let lv = ActLoad.level(status)
        let weekAgo = series.dropLast(7).last?.acwr
        DSScreen("Carga de entrenamiento", subtitle: last.map { DSFmt.shortDate($0.day) }) {
            if let last, let r = last.acwr {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Fmt.dec(r, 2)).dsFont(60, .semibold, relativeTo: .largeTitle, maxScale: 1.15).foregroundStyle(DS.t1)
                            ActLevelLine(text: status.label, color: lv?.mark ?? DS.t3, ink: lv?.ink ?? DS.t2)
                            Text(status.advice).dsFont(14).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        DSSideTable(rows: [("Aguda · 7 d", Fmt.int(last.atl)), ("Crónica · 28 d", Fmt.int(last.ctl))]
                                    + (weekAgo.map { [("Hace 7 días", Fmt.dec($0, 2))] } ?? []), width: 160)
                    }
                    DSDivider()
                    Text("Aguda frente a crónica").dsFont(14).foregroundStyle(DS.t2)
                    DSRangeBar(stretches: ActLoad.stretches, marker: min(max(ActLoad.position(r), 0), 1), markerColor: DS.t1,
                               labels: ActLoad.cuts.map { (ActLoad.position($0), Fmt.dec($0)) })
                    HStack {
                        ForEach(["Baja", "Mantiene", "Óptima", "Alta", "Riesgo"], id: \.self) { w in
                            Text(w).dsFont(12.5, w == ActLoad.word(status) ? .semibold : .regular)
                                .foregroundStyle(w == ActLoad.word(status) ? DS.t1 : DS.t3)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .dsCard(padding: 16)
            } else {
                DSEmptyState(icon: "gauge.with.dots.needle.33percent", title: "Calibrando", message: TrainingLoad.Status.calibrating.advice)
            }
            if series.count >= 2 { chart(series) }
            added(series)
            DSSectionHeader("Qué es")
            DSWhatIs(text: "Cada día suma los minutos en cada zona por su número. La aguda es tu media de 7 días (fatiga) y la crónica, la de 28 (forma). Entre 1,0 y 1,3 subes a buen ritmo.",
                     footnote: "No es un dispositivo médico.")
        }
    }

    private func chart(_ series: [TrainingLoad.Point]) -> some View {
        let pts = Array(series.suffix(period.days))
        let lo = (pts.map { min($0.atl, $0.ctl) }.min() ?? 0) * 0.85
        let hi = (pts.map { max($0.atl, $0.ctl) }.max() ?? 1) * 1.1
        return VStack(alignment: .leading, spacing: 12) {
            DSSegmented(options: DSPeriod.standard.map { ($0, $0.label) }, selection: $period).frame(width: 190)
            HStack(spacing: 14) {
                HStack(spacing: 5) { DSDot(color: DS.act); Text("Aguda (fatiga)") }
                HStack(spacing: 5) { Text("---"); Text("Crónica (forma)") }
            }
            .dsFont(13).foregroundStyle(DS.t2)
            Chart {
                ForEach(Array(pts.enumerated()), id: \.offset) { i, p in
                    LineMark(x: .value("d", i), y: .value("v", p.ctl), series: .value("s", "ctl"))
                        .foregroundStyle(DS.t2).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3])).interpolationMethod(.monotone)
                    LineMark(x: .value("d", i), y: .value("v", p.atl), series: .value("s", "atl"))
                        .foregroundStyle(DS.act).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round)).interpolationMethod(.monotone)
                }
                if let l = pts.last {
                    PointMark(x: .value("d", pts.count - 1), y: .value("v", l.atl)).foregroundStyle(DS.act).symbolSize(40)
                }
            }
            .chartXScale(domain: 0...max(1, pts.count - 1))
            .chartYScale(domain: lo...max(hi, lo + 1))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(DS.sep)
                    AxisValueLabel().foregroundStyle(DS.t3)
                }
            }
            .frame(height: 150)
            HStack {
                Text("Hace \(pts.count) días").foregroundStyle(DS.t3)
                Spacer()
                Text("Hoy").fontWeight(.semibold).foregroundStyle(DS.t1)
            }
            .dsFont(13, relativeTo: .footnote)
            .padding(.trailing, 34)
        }
        .dsCard(padding: 14)
    }

    /// «Qué ha sumado»: the last 7 days' load (TRIMP) with what you did each day.
    @ViewBuilder
    private func added(_ series: [TrainingLoad.Point]) -> some View {
        let week = Array(series.suffix(7))
        let top = max(1, week.map(\.load).max() ?? 1)
        if week.contains(where: { $0.load > 0 }) {
            DSSectionHeader("Qué ha sumado", note: "últimos 7 días")
            VStack(spacing: 0) {
                ForEach(Array(week.enumerated()), id: \.offset) { i, p in
                    if i > 0 { DSDivider() }
                    let isLast = i == week.count - 1
                    HStack(spacing: 12) {
                        Text(isLast && p.day == model.currentDayKey ? "hoy" : weekday(p.day)).dsFont(15, isLast ? .semibold : .regular)
                            .foregroundStyle(isLast ? DS.t1 : DS.t3).frame(width: 40, alignment: .leading)
                        Text(what(p.day)).dsFont(15).foregroundStyle(DS.t2).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DS.fill)
                                Capsule().fill(isLast ? DS.act : DS.fill2).frame(width: max(4, g.size.width * CGFloat(p.load / top)))
                            }
                        }
                        .frame(width: 96, height: 8)
                        Text(Fmt.int(p.load)).dsFont(16, .semibold).foregroundStyle(DS.t1).frame(width: 40, alignment: .trailing)
                    }
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 14)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        }
    }

    private func weekday(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    private func what(_ key: String) -> String {
        guard let d = model.day(key) else { return "Sin datos" }
        let names = model.workouts(for: d).map(\.sport).filter { !Breathwork.activityNames.contains($0) }
        if names.isEmpty { return "Actividad diaria" }
        var seen: [String] = []
        for n in names where !seen.contains(n) { seen.append(n) }
        return seen.prefix(2).joined(separator: " + ")
    }
}
