import Foundation
import PulsoStore

/// Personal next-day recovery model (ridge regression on standardised features).
///
/// Validation is strictly chronological: each day is predicted with a model fitted only on the days
/// before it (rolling origin). Its error is compared with a simple reference (mean of the last 7
/// recoveries): predictability PP = 1 − MAE_model / MAE_ref. Intervals come from those
/// out-of-sample errors. Coefficients describe associations in your data, not causes.
public enum RecoveryModel {
    public static let version = "1.0"
    public static let minTrain = 21
    public static let lambda = 2.0

    public static let firstHabitFeature = 5
    /// A yes/no habit with fewer "yes" days than this stays out of the model: with one or two days its
    /// standardised scale is tiny and toggling it swings the forecast wildly.
    public static let minHabitDays = 5
    public static let habitKeys = ["alcohol", "late_caffeine", "late_meal"]
    public static let featureNames = ["Recuperación de hoy", "Esfuerzo de hoy", "Deuda de sueño", "Deuda fisiológica",
                                      "Horas de sueño", "Alcohol", "Cafeína por la tarde", "Cena tarde"]

    public struct Row: Equatable, Sendable {
        /// Day whose recovery is predicted.
        public var day: String
        public var y: Double
        public var x: [Double]
    }

    /// Inputs known on the evening of day D (plus the sleep of the night after it) → recovery of D + 1.
    public static func rows(days: [DaySummary], deviation: [Deviation.Point], journal: [JournalEntry]) -> [Row] {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let dev = Dictionary(deviation.map { ($0.day, $0.debt) }, uniquingKeysWith: { a, _ in a })
        let habits = Dictionary(grouping: journal.filter { $0.value > 0 }, by: { $0.day }).mapValues { Set($0.map { $0.key }) }
        return days.sorted { $0.day < $1.day }.compactMap { d in
            guard let rec = d.recovery, let strain = d.strain, let next = byDay[LoadResponse.shift(d.day, 1)],
                  let y = next.recovery, let sleep = next.sleepMinutes else { return nil }
            let h = habits[d.day] ?? []
            return Row(day: next.day, y: y, x: [rec, strain, (d.sleepDebtMinutes ?? 0) / 60, dev[d.day] ?? 0, sleep / 60,
                                               h.contains("alcohol") ? 1 : 0, h.contains("late_caffeine") ? 1 : 0, h.contains("late_meal") ? 1 : 0])
        }
    }

    /// A fitted model with its feature scaling.
    public struct Trained: Sendable {
        public var means: [Double]
        public var sds: [Double]
        public var beta: [Double]
        /// SD of out-of-sample errors (or in-sample residuals when not validated yet).
        public var errorSD: Double
        public var n: Int
        /// "Yes" days per habit feature in the training data (same order as `habitKeys`).
        public var habitDays: [Int] = []

        /// The habit has enough "yes" days to be part of the model.
        public func usesHabit(_ i: Int) -> Bool { i < habitDays.count && habitDays[i] >= RecoveryModel.minHabitDays }

        func scaled(_ x: [Double]) -> [Double] { (0..<x.count).map { (x[$0] - means[$0]) / sds[$0] } }

        public func predict(_ x: [Double]) -> Double {
            Num.clamp(beta[0] + Num.dot(Array(beta.dropFirst()), scaled(x)), 1, 99)
        }

        /// Points each feature adds versus an average day.
        public func contributions(_ x: [Double]) -> [(name: String, points: Double)] {
            let z = scaled(x)
            return (0..<z.count).filter { $0 < RecoveryModel.firstHabitFeature || usesHabit($0 - RecoveryModel.firstHabitFeature) }
                .map { j -> (name: String, points: Double) in
                var name = RecoveryModel.featureNames[j]
                // Habits are yes/no: when absent, say so ("sin alcohol") instead of naming the habit.
                if j >= RecoveryModel.firstHabitFeature && x[j] == 0 { name = "Sin " + name.lowercased() }
                return (name, beta[j + 1] * z[j])
            }.sorted { abs($0.points) > abs($1.points) }
        }

        /// Point prediction with an 80 % interval.
        public func forecast(_ x: [Double]) -> (value: Double, interval: ClosedRange<Double>) {
            let v = predict(x), h = 1.2816 * errorSD
            return (v, Num.clamp(v - h, 1, 99)...Num.clamp(v + h, 1, 99))
        }
    }

    static func train(_ rows: [Row], errorSD: Double? = nil) -> Trained? {
        guard rows.count >= 8, let p = rows.first?.x.count else { return nil }
        let habitDays = (firstHabitFeature..<p).map { j in rows.filter { $0.x[j] > 0 }.count }
        let off = Set((firstHabitFeature..<p).filter { habitDays[$0 - firstHabitFeature] < minHabitDays })
        let means = (0..<p).map { j in off.contains(j) ? 0 : Num.mean(rows.map { $0.x[j] }) ?? 0 }
        let sds = (0..<p).map { j in off.contains(j) ? 1 : max(Num.sd(rows.map { $0.x[j] }) ?? 1, 1e-3) }
        let z = rows.map { r in (0..<p).map { off.contains($0) ? 0 : (r.x[$0] - means[$0]) / sds[$0] } }
        guard var fit = Num.ridge(z, rows.map { $0.y }, lambda: lambda) else { return nil }
        for j in off { fit.beta[j + 1] = 0 }
        return Trained(means: means, sds: sds, beta: fit.beta, errorSD: errorSD ?? fit.residualSD, n: rows.count, habitDays: habitDays)
    }

    public struct Evaluation: Equatable, Sendable {
        public var maeModel: Double
        public var maeReference: Double
        public var predictability: Double
        public var errorSD: Double
        public var tested: Int
        /// (day, observed, predicted) of the out-of-sample predictions.
        public var predictions: [Prediction]

        public struct Prediction: Equatable, Sendable {
            public var day: String
            public var observed: Double
            public var predicted: Double
        }
    }

    /// Rolling-origin evaluation: day t is predicted by a model trained on days < t only.
    public static func evaluate(_ rows: [Row]) -> Evaluation? {
        guard rows.count > minTrain + 4 else { return nil }
        var em: [Double] = [], er: [Double] = [], preds: [Evaluation.Prediction] = []
        for t in minTrain..<rows.count {
            guard let m = train(Array(rows[..<t])) else { continue }
            let pred = m.predict(rows[t].x)
            let ref = Num.mean(rows[max(0, t - 7)..<t].map { $0.y }) ?? pred
            em.append(rows[t].y - pred)
            er.append(rows[t].y - ref)
            preds.append(.init(day: rows[t].day, observed: rows[t].y, predicted: pred))
        }
        guard em.count >= 5 else { return nil }
        let mae = em.map(abs).reduce(0, +) / Double(em.count)
        let maeRef = er.map(abs).reduce(0, +) / Double(er.count)
        return Evaluation(maeModel: mae, maeReference: maeRef, predictability: maeRef > 0 ? 1 - mae / maeRef : 0,
                          errorSD: Num.sd(em) ?? mae * 1.25, tested: em.count, predictions: preds)
    }

    // MARK: - Report pieces

    public struct Outlook: Sendable {
        public var model: Trained
        public var evaluation: Evaluation?
        /// Today's evening inputs (with the usual sleep), ready for scenarios.
        public var todayInputs: [Double]
        public var usualSleepHours: Double
    }

    /// Builds the model with everything up to now, and today's inputs for tomorrow's forecast.
    public static func outlook(days: [DaySummary], deviation: [Deviation.Point], journal: [JournalEntry], today: String) -> Outlook? {
        let r = rows(days: days, deviation: deviation, journal: journal)
        guard r.count >= minTrain else { return nil }
        let ev = evaluate(r)
        guard let m = train(r, errorSD: ev?.errorSD), let d = days.first(where: { $0.day == today }),
              let rec = d.recovery else { return nil }
        let usual = Num.median(days.suffix(14).compactMap { $0.sleepMinutes }) .map { $0 / 60 } ?? 7.5
        let h = Set(journal.filter { $0.day == today && $0.value > 0 }.map { $0.key })
        let debt = deviation.last(where: { $0.day <= today })?.debt ?? 0
        let x: [Double] = [rec, d.strain ?? 0, (d.sleepDebtMinutes ?? 0) / 60, debt, usual,
                 h.contains("alcohol") ? 1 : 0, h.contains("late_caffeine") ? 1 : 0, h.contains("late_meal") ? 1 : 0]
        return Outlook(model: m, evaluation: ev, todayInputs: x, usualSleepHours: usual)
    }

    /// What-if: tomorrow's recovery if tonight you sleep `sleepHours`, with these habits and today's strain.
    public static func scenario(_ o: Outlook, sleepHours: Double, alcohol: Bool, caffeine: Bool, lateMeal: Bool, strain: Double? = nil)
        -> (value: Double, interval: ClosedRange<Double>) {
        var x = o.todayInputs
        if let strain { x[1] = strain }
        x[4] = sleepHours
        x[5] = alcohol ? 1 : 0
        x[6] = caffeine ? 1 : 0
        x[7] = lateMeal ? 1 : 0
        return o.model.forecast(x)
    }

    static let fForecast = "Ridge (λ = 2) sobre variables estandarizadas: recuperación y esfuerzo de hoy, deuda de sueño, deuda fisiológica, horas de sueño y hábitos; intervalo 80 % con el error fuera de muestra"
    static let fPP = "PP = 1 − MAE_modelo / MAE_referencia, con predicción día a día usando solo días anteriores; referencia = media de las 7 últimas recuperaciones"
    static let fSurprise = "PS = |recuperación observada − predicha ayer| / DE del error fuera de muestra"

    public static func forecastMetric(_ o: Outlook?) -> MetricResult {
        guard let o else {
            return .insufficient("forecast", "Recuperación prevista para mañana", unit: "%",
                                 need: "\(minTrain) pares de días consecutivos con recuperación", have: 0, formula: fForecast, version: version)
        }
        let f = o.model.forecast(o.todayInputs)
        let top = o.model.contributions(o.todayInputs).prefix(2).filter { abs($0.points) >= 2 }
        var text = String(format: "Si duermes tus %.1f h habituales, mañana rondarías el %.0f %% (entre %.0f y %.0f).", locale: Num.spanish, o.usualSleepHours, f.value,
                          f.interval.lowerBound, f.interval.upperBound)
        if !top.isEmpty {
            text += " Pesa sobre todo: " + top.map { String(format: "%@ (%+.0f)", locale: Num.spanish, $0.name.lowercased(), $0.points) }.joined(separator: ", ") + "."
        }
        var conf: MetricResult.Confidence = (o.evaluation?.predictability ?? 0) > 0.15 ? .high : ((o.evaluation?.predictability ?? 0) > 0 ? .medium : .low)
        // A range as wide as most of the scale can't be called confident, whatever the back-test says.
        let width = f.interval.upperBound - f.interval.lowerBound
        if width > 40 { conf = .low } else if width > 25, conf == .high { conf = .medium }
        return MetricResult(id: "forecast", name: "Recuperación prevista para mañana", value: f.value.rounded(), unit: "%", summary: text,
                            interval: f.interval, confidence: conf, sampleSize: o.model.n, formula: fForecast, version: version)
    }

    public static func predictabilityMetric(_ o: Outlook?) -> MetricResult {
        guard let ev = o?.evaluation else {
            return .insufficient("predictability", "Predictibilidad", need: "\(minTrain + 5) pares de días para validar", have: o?.model.n ?? 0,
                                 formula: fPP, version: version)
        }
        let pct = ev.predictability * 100
        let text: String
        if pct > 15 {
            text = String(format: "El modelo personal acierta un %.0f %% mejor que tu media reciente (error medio %.0f puntos frente a %.0f).", locale: Num.spanish, pct, ev.maeModel, ev.maeReference)
        } else if pct > 0 {
            text = String(format: "El modelo personal mejora poco a tu media reciente (%.0f %%): tu recuperación depende de cosas que aún no registras.", locale: Num.spanish, pct)
        } else {
            text = "Por ahora el modelo no supera a tu media reciente: hacen falta más días o más variedad. Úsalo con cautela."
        }
        return MetricResult(id: "predictability", name: "Predictibilidad", value: (pct).rounded(), unit: "%", summary: text,
                            confidence: .from(samples: ev.tested, medium: 15, high: 40), sampleSize: ev.tested, formula: fPP, version: version)
    }

    public static func surpriseMetric(_ o: Outlook?) -> MetricResult {
        guard let ev = o?.evaluation, let last = ev.predictions.last, ev.errorSD > 0 else {
            return .insufficient("surprise", "Sorpresa fisiológica", unit: "σ", need: "un modelo validado", have: 0, formula: fSurprise, version: version)
        }
        let ps = abs(last.observed - last.predicted) / ev.errorSD
        let dir = last.observed > last.predicted ? "mejor" : "peor"
        let text = ps < 1 ? "Hoy has amanecido como cabía esperar." :
            (ps < 2 ? "Hoy has amanecido algo \(dir) de lo esperado." :
                String(format: "Hoy has amanecido mucho %@ de lo esperado (%.0f %% frente a %.0f %%). Algo no registrado ha influido.", locale: Num.spanish, dir, last.observed, last.predicted))
        return MetricResult(id: "surprise", name: "Sorpresa fisiológica", value: (ps * 10).rounded() / 10, unit: "σ", summary: text,
                            confidence: .from(samples: ev.tested, medium: 15, high: 40), sampleSize: ev.tested, formula: fSurprise, version: version)
    }
}
