import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// 12 Edad Pulso: the age with your real age and the last month's, week by week against your real age, what each habit
/// takes off or adds (its years, opening the habit) and «Qué es». No error margins on screen.
struct HoyEdadPulsoView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let r = model.pulsoAge
        DSScreen("Edad Pulso", subtitle: subtitle, back: "Hoy") {
            if let r, let age = r.pulsoAge {
                hero(r, age)
                if model.ageTrend.count >= 2 {
                    DSSectionHeader("Semana a semana", note: model.ageTrend.first.map { "desde \(Self.monthName($0.day))" })
                    trend(realNow: r.age)
                }
                habits(r)
            } else {
                DSEmptyState(icon: "hourglass", title: "Calculando", message: "Hacen falta unas semanas de datos para estimarla.")
            }
            DSSectionHeader("Qué es")
            DSWhatIs(text: "La edad que corresponde a tu forma y tus hábitos de los últimos 6 meses, comparados con estudios de personas de tu edad. Se recalcula cada lunes.",
                     footnote: "Es una estimación, no una medida biológica.")
        }
    }

    private var subtitle: String {
        "Actualizada el " + DSFmt.shortDate(AppModel.weekStart(model.currentDayKey)).lowercased()
    }

    static func monthName(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "LLLL"
        return f.string(from: d)
    }

    private func hero(_ r: PulsoAge.Result, _ age: Double) -> some View {
        var side: [(String, String)] = [("Edad real", Fmt.dec(r.age))]
        if let recent = r.recentAge { side.append(("Tu último mes", Fmt.dec(recent))) }
        return HoyHero(value: Fmt.dec(age), unit: "años", side: side) {
            if let d = r.difference {
                if abs(d) < 0.05 {
                    Text("Como tu edad real").dsFont(15, .semibold).foregroundStyle(DS.t2)
                } else {
                    DSDelta(text: "\(Fmt.dec(abs(d))) años \(d < 0 ? "más joven" : "mayor")", up: d > 0,
                            color: d < 0 ? DSLevel.excelente.ink : DSLevel.justa.ink)
                }
            }
        }
    }

    private func trend(realNow: Double) -> some View {
        let pts = model.ageTrend.compactMap { p in DayKey.date(p.day).map { (date: $0, age: p.age) } }
        let today = Date()
        let real = pts.map { (date: $0.date, age: realNow - today.timeIntervalSince($0.date) / (365.25 * 86_400)) }
        let all = pts.map(\.age) + real.map(\.age)
        let lo = floor((all.min() ?? 0) - 0.3), hi = ceil((all.max() ?? 1) + 0.3)
        return VStack(spacing: 6) {
            Chart {
                ForEach(real.indices, id: \.self) { i in
                    LineMark(x: .value("Semana", real[i].date), y: .value("Edad", real[i].age), series: .value("s", "Real"))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                        .foregroundStyle(DS.t2)
                }
                ForEach(pts.indices, id: \.self) { i in
                    AreaMark(x: .value("Semana", pts[i].date), yStart: .value("Pulso", pts[i].age), yEnd: .value("Real", real[i].age))
                        .foregroundStyle(DS.bien.opacity(0.14))
                    LineMark(x: .value("Semana", pts[i].date), y: .value("Edad", pts[i].age), series: .value("s", "Pulso"))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(DS.bien)
                }
                if let last = pts.last {
                    PointMark(x: .value("Semana", last.date), y: .value("Edad", last.age))
                        .symbol { Circle().fill(DS.bien).overlay(Circle().stroke(DS.card, lineWidth: 2)).frame(width: 9, height: 9) }
                        .annotation(position: .bottom, alignment: .trailing, spacing: 4) {
                            Text("Pulso").dsFont(12, .semibold, relativeTo: .caption1).foregroundStyle(DS.bien)
                        }
                }
                if let last = real.last {
                    PointMark(x: .value("Semana", last.date), y: .value("Edad", last.age)).symbolSize(0)
                        .annotation(position: .top, alignment: .trailing, spacing: 4) {
                            Text("Real").dsFont(12, .medium, relativeTo: .caption1).foregroundStyle(DS.t2)
                        }
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { v in
                    AxisValueLabel {
                        if let d = v.as(Date.self) { Text(DSFmt.monthName(d)).dsFont(12, .medium).foregroundStyle(DS.t3) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(DS.sep)
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text("\(Int(d))").dsFont(11, .medium).foregroundStyle(DS.t3) }
                    }
                }
            }
            .frame(height: 190)
        }
        .dsCard(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Edad Pulso semana a semana frente a tu edad real")
    }

    @ViewBuilder
    private func habits(_ r: PulsoAge.Result) -> some View {
        let items = r.items.filter { $0.years != nil }.sorted { ($0.years ?? 0) < ($1.years ?? 0) }
        if !items.isEmpty {
            let maxAbs = max(items.map { abs($0.years ?? 0) }.max() ?? 1, 0.1)
            let rows = items.map { i -> HoyPointRow in
                let y = i.years ?? 0
                let shown = (y * 10).rounded() / 10
                return HoyPointRow(id: i.key, icon: Self.icon(i.key), iconColor: Self.color(i.key), title: Self.title(i),
                                   subtitle: Self.subtitle(i), effect: -y / maxAbs, good: y <= 0,
                                   word: (shown > 0 ? "+" : (shown < 0 ? "−" : "")) + Fmt.dec(abs(shown)), route: .metric(.habito(i.key)))
            }
            DSSectionHeader("Qué te quita y te suma años")
            HoyPointsList(rows: rows, axis: ("Suma", "Quita")) {
                DSDivider().padding(.horizontal, -14)
                Text("Juntos explican la diferencia con tu edad real.").dsFont(13).foregroundStyle(DS.t3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }
        }
    }

    static func icon(_ key: String) -> String {
        switch key {
        case "vo2max": return "lungs.fill"
        case "rhr": return "heart.fill"
        case "zonesLight", "zonesHard": return "flame.fill"
        case "regularity": return "clock"
        case "steps": return "shoeprints.fill"
        case "strength": return "dumbbell.fill"
        default: return "moon.fill"
        }
    }

    static func color(_ key: String) -> Color {
        switch key {
        case "vo2max", "rhr": return DS.cor
        case "regularity", "sleepHours": return DS.sueno
        default: return DS.act
        }
    }

    static func title(_ i: PulsoAge.Item) -> String {
        switch i.key {
        case "vo2max": return "VO₂ máx"
        case "rhr": return "FC en reposo"
        case "zonesLight": return "Zonas 1–3"
        case "zonesHard": return "Zonas 4–5"
        case "regularity": return "Regularidad del sueño"
        case "steps": return "Pasos"
        case "strength": return "Fuerza"
        case "sleepHours": return "Sueño"
        default: return i.label
        }
    }

    static func subtitle(_ i: PulsoAge.Item) -> String? {
        guard let v = i.longTerm else { return nil }
        switch i.key {
        case "vo2max": return "\(Int(v.rounded())) ml/kg/min"
        case "rhr": return "\(Int(v.rounded())) lpm"
        case "zonesLight", "zonesHard", "strength": return "\(DSFmt.duration(v)) a la semana"
        case "regularity": return "\(Int(v.rounded())) %"
        case "steps": return "\(DSFmt.thousands(v)) al día"
        case "sleepHours": return "\(DSFmt.duration(v)) de media"
        default: return nil
        }
    }
}
