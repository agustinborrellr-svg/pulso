import SwiftUI
import PulsoStore
import PulsoAnalytics

/// 05–09 VFC, FC en reposo, Respiración, SpO₂ and Temperatura piel with the metric template, built from the same
/// reading as the monitor (`AppModel.vitalReadings()`): your range of 30 nights («tu normal»), the amber and red
/// limits, last night against your mean and the night before, the chart and «Qué es». Skin temperature reads as the
/// change from your usual; out of range above, the causes the app lists. SpO₂ uses the fixed clinical ranges.
struct HoyVitalDetail: View {
    @EnvironmentObject var model: AppModel
    let id: String

    var body: some View {
        if let r = model.vitalReadings().first(where: { $0.id == id }) {
            let spec = HoyVitalSpec.make(r, days: model.days)
            DSMetricDetail(spec: spec) {
                let causes = Self.causes(r)
                if !causes.isEmpty {
                    DSSectionHeader("Puede deberse a")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(causes.indices, id: \.self) { i in
                            if i > 0 { DSDivider() }
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Circle().fill(DS.justa).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                Text(causes[i]).dsFont(16).foregroundStyle(DS.t1).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 11)
                        }
                    }
                    .dsCard(padding: 14)
                }
            }
        } else {
            DSScreen(HoyVitalSpec.title(id), back: "Monitor") {
                DSEmptyState(icon: "waveform.path.ecg", title: "Sin lecturas", message: "Aparece tras tu primera noche con la pulsera.")
            }
        }
    }

    /// The causes listed in the reading's detail (only for a skin temperature above your range).
    static func causes(_ r: VitalReading) -> [String] {
        guard r.id == "temp", r.level == .orange || r.level == .red, let range = r.range, r.raw > range.upperBound else { return [] }
        return r.detail.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.map { String($0.dropFirst(2)) }
    }
}

enum HoyVitalSpec {
    static func title(_ id: String) -> String {
        id == "temp" ? "Temperatura piel" : HoyVital.shortTitle(id)
    }

    static func value(_ id: String, _ d: DaySummary) -> Double? {
        switch id {
        case "hrv": return d.hrv
        case "rhr": return d.rhr
        case "resp": return d.respRate
        case "spo2": return d.spo2
        default: return d.skinTemp
        }
    }

    static func whatIs(_ r: VitalReading) -> String {
        switch r.id {
        case "hrv":
            return "La variación del tiempo entre latidos, medida durante el sueño. Alta: tu sistema nervioso está relajado. Baja: cansancio, alcohol, estrés o algo que incubas. Compárala solo contigo."
        case "temp":
            return "La temperatura de tu piel en la muñeca durante la noche. Importa cuánto se aleja de lo tuyo, no el valor: varias noches altas seguidas pueden anunciar fiebre o, en mujeres, la fase lútea."
        default:
            return r.explanation
        }
    }

    static func make(_ r: VitalReading, days: [DaySummary]) -> DSMetricSpec {
        let dev = r.asDeviation
        let centre = r.range.map { ($0.lowerBound + $0.upperBound) / 2 } ?? 0
        // Skin temperature in change from your usual; the rest in their own units.
        let toShown: (Double) -> Double = dev ? { $0 - centre } : { $0 }
        let fmt: (Double) -> String = dev ? { HoyVital.signed($0, r.format) } : r.format
        let unit = r.unit
        let night = r.history.last?.day
        var spec = DSMetricSpec(title: title(r.id), value: dev ? r.monitorValue : r.value, unit: unit == "%" ? "%" : unit)
        spec.subtitle = night.map { "\(r.when == "Anoche" ? "Anoche" : "Noche") · \(DSFmt.dayMonth($0))" }
        spec.back = "Monitor"
        spec.color = HoyVital.color(r.id)
        spec.format = fmt
        spec.statUnit = unit
        spec.unitWord = "noches"
        spec.endLabel = "Anoche"
        spec.whatIs = whatIs(r)

        // Level.
        if let lv = DSLevel(r.level) {
            spec.level = lv
            spec.levelText = r.level == .green ? (r.personal ? "En tu rango" : "En rango") : HoyVital.capitalized(r.chip)
        } else {
            spec.levelText = "Calibrando tu rango"
        }
        let before = r.history.dropLast().map(\.value)
        let mean = before.isEmpty ? nil : before.reduce(0, +) / Double(before.count)
        if !r.personal {
            spec.delta = "Experimental"
        } else if dev {
            if r.level != .none { spec.delta = "frente a tu media" }
        } else if let mean, abs(r.raw - mean) >= 0.5 * pow(10, -Double(decimals(r))) {
            let d = r.raw - mean
            spec.delta = "\(r.format(abs(d))) \(unit) \(d > 0 ? "sobre" : "bajo") tu media"
            spec.deltaUp = d > 0
        }

        // Side table.
        var side: [(String, String)] = []
        if dev { side.append(("Medida", "\(Fmt.dec(r.raw)) °C")) } else if r.personal, let mean { side.append(("Tu media", r.format(mean))) }
        if r.history.count >= 2 {
            let prev = r.history[r.history.count - 2]
            let label = night.map { prev.day == DayKey.shift($0, days: -1) ? "Ayer" : DSFmt.dayMonth(prev.day) } ?? "Ayer"
            side.append((label, fmt(toShown(prev.value))))
        }
        spec.side = side

        // Limits.
        if let range = r.range, let outer = r.outer {
            let rg = toShown(range.lowerBound)...toShown(range.upperBound)
            let o = toShown(outer.lowerBound)...toShown(outer.upperBound)
            let v = toShown(r.raw)
            let span = max(o.upperBound - o.lowerBound, 0.0001)
            let lo = min(o.lowerBound - span * 0.25, v)
            let hi = r.personal ? max(o.upperBound + span * 0.25, v) : max(o.upperBound, v)
            let p = { (x: Double) in (x - lo) / max(hi - lo, 0.0001) }
            var stretches: [DSRangeBar.Stretch]
            var labels: [(Double, String)]
            switch r.bad {
            case -1:
                stretches = [.init(to: p(o.lowerBound), color: DS.baja), .init(to: p(rg.lowerBound), color: DS.justa), .init(to: 1, color: DS.buena)]
                labels = [(p(o.lowerBound), fmt(o.lowerBound)), (p(rg.lowerBound), fmt(rg.lowerBound))]
            case 1:
                stretches = [.init(to: p(rg.upperBound), color: DS.buena), .init(to: p(o.upperBound), color: DS.justa), .init(to: 1, color: DS.baja)]
                labels = [(p(rg.upperBound), fmt(rg.upperBound)), (p(o.upperBound), fmt(o.upperBound))]
            default:
                stretches = [.init(to: p(o.lowerBound), color: DS.baja), .init(to: p(rg.lowerBound), color: DS.justa),
                             .init(to: p(rg.upperBound), color: DS.buena), .init(to: p(o.upperBound), color: DS.justa), .init(to: 1, color: DS.baja)]
                labels = [(p(o.lowerBound), fmt(o.lowerBound)), (p(rg.lowerBound), fmt(rg.lowerBound)),
                          (p(rg.upperBound), fmt(rg.upperBound)), (p(o.upperBound), fmt(o.upperBound))]
            }
            spec.rangeBar = DSRangeBar(stretches: stretches, marker: p(v), markerColor: spec.level?.mark ?? DS.t1, labels: labels)
            spec.rangeTitle = r.personal ? "Tus límites, con tus 30 noches anteriores" : "Rangos de referencia, iguales para todos"
            spec.normal = rg
        }

        // Series: 7 and 30 nights, 6 months as weekly means.
        let pairs: [(day: String, v: Double)] = days.compactMap { d in value(r.id, d).map { (day: d.day, v: toShown($0)) } }
        if let end = night ?? pairs.last?.day {
            func points(_ n: Int) -> [DSPoint] {
                let start = DayKey.shift(end, days: -(n - 1))
                return pairs.filter { $0.day >= start && $0.day <= end }.compactMap { p in DayKey.date(p.day).map { DSPoint(date: $0, value: p.v) } }
            }
            var series: [DSPeriod: [DSPoint]] = [.week: points(7), .month: points(30)]
            let half = points(182)
            if let first = half.first?.date {
                var weeks: [Int: [Double]] = [:]
                for p in half { weeks[Int(p.date.timeIntervalSince(first) / (7 * 86_400)), default: []].append(p.value) }
                series[.halfYear] = weeks.keys.sorted().map { w in
                    let vals = weeks[w] ?? []
                    return DSPoint(date: first.addingTimeInterval(Double(w * 7 + 3) * 86_400), value: vals.reduce(0, +) / Double(max(vals.count, 1)))
                }
            }
            spec.series = series
            if r.personal, let mean { spec.mean = toShown(mean) }
        }
        return spec
    }

    private static func decimals(_ r: VitalReading) -> Int { r.format(1.5).contains(",") ? 1 : 0 }
}
