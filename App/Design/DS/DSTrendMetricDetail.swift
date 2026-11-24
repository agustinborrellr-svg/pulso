import SwiftUI
import PulsoStore

/// A metric detail built from real daily data (`TrendMetric.value` over `model.days`) with the DS template: the
/// selected day's value, «tu normal» = mean ± 1 SD of the 30 days before, yesterday, your limits, 7 d / 30 d / 6 m
/// (weekly means), and the metric's own explanation. A starting point the areas can extend (`extra`, factors).
struct DSTrendMetricDetail<Extra: View>: View {
    @EnvironmentObject var model: AppModel
    let metric: TrendMetric
    var title: String
    var back: String?
    var color: Color = DS.recarga
    /// 0–100 score: level word from the 4-step scale, with the meter.
    var score = false
    /// A night metric: "noches", "Anoche".
    var night = false
    var yDomain: ClosedRange<Double>?
    var whatIs: String?
    var factors: [DSFactor] = []
    @ViewBuilder var extra: Extra

    var body: some View {
        DSMetricDetail(spec: DSTrendMetricSpec.make(model: model, metric: metric, title: title, back: back, color: color,
                                                    score: score, night: night, yDomain: yDomain, whatIs: whatIs, factors: factors)) {
            extra
        }
    }
}

extension DSTrendMetricDetail where Extra == EmptyView {
    init(metric: TrendMetric, title: String, back: String? = nil, color: Color = DS.recarga, score: Bool = false,
         night: Bool = false, yDomain: ClosedRange<Double>? = nil, whatIs: String? = nil, factors: [DSFactor] = []) {
        self.metric = metric
        self.title = title
        self.back = back
        self.color = color
        self.score = score
        self.night = night
        self.yDomain = yDomain
        self.whatIs = whatIs
        self.factors = factors
        self.extra = EmptyView()
    }
}

enum DSTrendMetricSpec {
    @MainActor
    static func make(model: AppModel, metric: TrendMetric, title: String, back: String?, color: Color, score: Bool,
                     night: Bool, yDomain: ClosedRange<Double>?, whatIs: String?, factors: [DSFactor]) -> DSMetricSpec {
        let pairs: [(day: String, v: Double)] = model.days.compactMap { d in metric.value(d).map { (day: d.day, v: $0) } }
        let key = model.selectedDay
        let current = pairs.last { $0.day <= key }
        let fmt: (Double) -> String = { metric.format($0) }
        var unit = metric.unit
        if metric.isDuration { unit = "" }
        if metric == .calories { unit = "kcal" }

        var spec = DSMetricSpec(title: title, value: current.map { fmt($0.v) } ?? "–", unit: current == nil ? "" : unit)
        spec.subtitle = current.map { (night ? "Anoche · " : "") + (night ? DSFmt.dayMonth($0.day) : DSFmt.shortDate($0.day)) }
        spec.back = back
        spec.color = color
        spec.format = fmt
        spec.statUnit = unit == "%" ? "%" : (metric.isDuration ? "" : unit)
        spec.unitWord = night ? "noches" : "días"
        spec.endLabel = night ? "Anoche" : "Hoy"
        spec.yDomain = yDomain
        spec.whatIs = whatIs ?? metric.explainer.text.components(separatedBy: "\n\n").first
        spec.factors = factors

        guard let current else { return spec }

        // Your normal: the 30 days before the shown day.
        let from = DayKey.shift(current.day, days: -30)
        let base = pairs.filter { $0.day < current.day && $0.day >= from }.map(\.v)
        var sd = 0.0
        if base.count >= 7 {
            let mean = base.reduce(0, +) / Double(base.count)
            sd = sqrt(base.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(base.count - 1))
            let half = max(sd, abs(mean) * 0.01, 0.01)
            spec.normal = (mean - half)...(mean + half)
            spec.mean = mean
            sd = half
        }

        // Level.
        let v = current.v
        if score {
            let lv = DSLevel(score: v)
            spec.level = lv
            spec.meter = true
        } else if let n = spec.normal {
            if n.contains(v) {
                spec.level = .buena
                spec.levelText = "En tu rango"
            } else {
                let above = v > n.upperBound
                let good = metric.higherIsBetter.map { $0 == above }
                let far = above ? v > n.upperBound + sd : v < n.lowerBound - sd
                spec.level = good == true ? .buena : (far ? .baja : .justa)
                spec.levelText = above ? "Por encima de tu normal" : "Por debajo de tu normal"
            }
        }
        if let mean = spec.mean, abs(v - mean) >= 0.05 * max(sd, 0.01) {
            let d = v - mean
            let u = unit.isEmpty ? "" : " \(unit)"
            spec.delta = "\(fmt(abs(d)))\(u) \(d > 0 ? "sobre" : "bajo") tu media"
            spec.deltaUp = d > 0
        }

        // Side table.
        var side: [(String, String)] = []
        if let n = spec.normal { side.append(("Tu normal", "\(fmt(n.lowerBound))–\(fmt(n.upperBound))")) }
        if let prev = pairs.last(where: { $0.day < current.day }) {
            side.append((prev.day == DayKey.shift(current.day, days: -1) ? (night ? "Noche anterior" : "Ayer") : DSFmt.dayMonth(prev.day), fmt(prev.v)))
        }
        spec.side = side

        // Limits: amber within one SD out of your normal, red beyond, green inside (and on the good side).
        if let n = spec.normal, sd > 0 {
            let lo = min(n.lowerBound - 2 * sd, v), hi = max(n.upperBound + 2 * sd, v)
            let span = max(hi - lo, 0.0001)
            let p = { (x: Double) in (x - lo) / span }
            let good = metric.higherIsBetter
            let below: [DSRangeBar.Stretch] = good == true
                ? [.init(to: p(n.lowerBound - sd), color: DS.baja), .init(to: p(n.lowerBound), color: DS.justa)]
                : (good == false ? [.init(to: p(n.lowerBound), color: DS.buena)]
                                 : [.init(to: p(n.lowerBound - sd), color: DS.baja), .init(to: p(n.lowerBound), color: DS.justa)])
            let inside: [DSRangeBar.Stretch] = good == false ? [] : [.init(to: p(n.upperBound), color: DS.buena)]
            let above: [DSRangeBar.Stretch] = good == true
                ? [.init(to: 1, color: DS.buena)]
                : (good == false ? [.init(to: p(n.upperBound), color: DS.buena), .init(to: p(n.upperBound + sd), color: DS.justa), .init(to: 1, color: DS.baja)]
                                 : [.init(to: p(n.upperBound + sd), color: DS.justa), .init(to: 1, color: DS.baja)])
            spec.rangeBar = DSRangeBar(stretches: below + inside + above, marker: p(v), markerColor: spec.level?.mark ?? DS.t1,
                                       labels: [(p(n.lowerBound), fmt(n.lowerBound)), (p(n.upperBound), fmt(n.upperBound))])
            spec.rangeTitle = "Tus límites, con tus 30 \(night ? "noches" : "días") anteriores"
        }

        // Series.
        func points(days: Int) -> [DSPoint] {
            let start = DayKey.shift(current.day, days: -(days - 1))
            return pairs.filter { $0.day >= start && $0.day <= current.day }.compactMap { p in DayKey.date(p.day).map { DSPoint(date: $0, value: p.v) } }
        }
        var series: [DSPeriod: [DSPoint]] = [.week: points(days: 7), .month: points(days: 30)]
        let half = points(days: 182)
        if let first = half.first?.date {
            var weeks: [Int: [Double]] = [:]
            for p in half { weeks[Int(p.date.timeIntervalSince(first) / (7 * 86_400)), default: []].append(p.value) }
            series[.halfYear] = weeks.keys.sorted().map { w in
                let vals = weeks[w] ?? []
                return DSPoint(date: first.addingTimeInterval(Double(w * 7 + 3) * 86_400), value: vals.reduce(0, +) / Double(max(vals.count, 1)))
            }
        }
        spec.series = series
        return spec
    }
}
