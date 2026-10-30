import Foundation
import PulsoStore

/// Sleep timing, regularity and how sleep structure relates to next-morning physiology.
public enum Rhythms {
    public static let version = "1.0"

    // MARK: - Regularity

    /// Sleep Regularity Index (Phillips et al. 2017): 200 · P(same sleep/wake state at t and t + 24 h) − 100,
    /// on a 1-minute grid over the last `days` days. 100 = identical every day, 0 = random.
    public static func sleepRegularityIndex(_ sleeps: [SleepSession], days: Int = 14, now: Int) -> (sri: Double, days: Int)? {
        let start = now - days * 86400
        let rel = sleeps.filter { $0.end > start && $0.start < now }
        guard !rel.isEmpty else { return nil }
        let minutes = days * 1440
        var asleep = [Bool](repeating: false, count: minutes)
        // Minutes with no recorded night are unknown, not "awake": only compare minutes we know.
        var known = [Bool](repeating: false, count: minutes)
        for s in rel {
            let a = max(0, (s.end - 86400 - start) / 60), b = min(minutes, (s.end - start) / 60)
            if a < b { for i in a..<b { known[i] = true } }
        }
        for s in rel {
            // Only asleep minutes (not awake stages) count as sleep.
            for (i, st) in s.stages.enumerated() where st != .awake {
                let idx = (s.start + i * 60 - start) / 60
                if idx >= 0 && idx < minutes { asleep[idx] = true }
            }
            if s.stages.isEmpty {
                let a = max(0, (s.start - start) / 60), b = min(minutes, (s.end - start) / 60)
                if a < b { for i in a..<b { asleep[i] = true } }
            }
        }
        let covered = Set(rel.map { DayKey.string(ts: $0.end) }).count
        guard covered >= 5 else { return nil }
        var same = 0, total = 0
        for i in 0..<(minutes - 1440) where known[i] && known[i + 1440] {
            total += 1
            if asleep[i] == asleep[i + 1440] { same += 1 }
        }
        guard total >= 1440 else { return nil }
        return (200 * Double(same) / Double(total) - 100, covered)
    }

    static func midSleepMinutes(_ s: SleepSession, calendar: Calendar) -> Double {
        let mid = (s.start + s.end) / 2
        var m = SleepCoachMinutes.minutesAfterMidnight(ts: mid, calendar: calendar)
        if m > 18 * 60 { m -= 1440 } // keep nights continuous around midnight
        return m
    }

    public static func regularityMetrics(sleeps: [SleepSession], now: Int, calendar: Calendar = .current) -> [MetricResult] {
        let main = sleeps.filter { !$0.isNap && $0.end > now - 28 * 86400 }.sorted { $0.start < $1.start }
        var out: [MetricResult] = []
        let fSRI = "SRI = 200 · P(mismo estado dormido/despierto a la misma hora en días consecutivos) − 100, minuto a minuto, 14 días"
        let sriRes = sleepRegularityIndex(sleeps, now: now)
        if let r = sriRes {
            let text = r.sri >= 80 ? "Horarios de sueño muy regulares." :
                (r.sri >= 60 ? "Regularidad aceptable; acostarte y levantarte a horas parecidas te ayudaría." :
                    "Horarios irregulares: tu cuerpo no sabe bien cuándo toca dormir.")
            out.append(MetricResult(id: "sri", name: "Regularidad del sueño", value: r.sri.rounded(), unit: "/100", summary: text,
                                    confidence: .from(samples: r.days, medium: 10, high: 14), sampleSize: r.days, formula: fSRI, version: version))
        } else {
            out.append(.insufficient("sri", "Regularidad del sueño", unit: "/100", need: "5 noches en las últimas dos semanas", have: main.count,
                                     formula: fSRI, version: version))
        }

        // Social jet lag: weekend vs weekday mid-sleep.
        let fSJL = "|mediana del punto medio del sueño en fin de semana − entre semana|"
        let wk = main.filter { [2, 3, 4, 5, 6].contains(calendar.component(.weekday, from: Date(timeIntervalSince1970: TimeInterval($0.end)))) }
        let we = main.filter { [1, 7].contains(calendar.component(.weekday, from: Date(timeIntervalSince1970: TimeInterval($0.end)))) }
        var jetlag: Double?
        if wk.count >= 3, we.count >= 2, let a = Num.median(wk.map { midSleepMinutes($0, calendar: calendar) }),
           let b = Num.median(we.map { midSleepMinutes($0, calendar: calendar) }) {
            let h = abs(b - a) / 60
            jetlag = h
            out.append(MetricResult(id: "socialJetlag", name: "Jet lag social", value: (h * 10).rounded() / 10, unit: "h",
                                    summary: h < 0.5 ? "Duermes a horas parecidas entre semana y el fin de semana." :
                                        String(format: "El fin de semana tu sueño se desplaza %.1f h: es como cambiar de huso horario cada semana.", locale: Num.spanish, h),
                                    confidence: .from(samples: min(wk.count, we.count * 2), medium: 4, high: 8), sampleSize: wk.count + we.count,
                                    formula: fSJL, version: version))
        } else {
            out.append(.insufficient("socialJetlag", "Jet lag social", unit: "h", need: "3 noches entre semana y 2 de fin de semana",
                                     have: main.count, formula: fSJL, version: version))
        }

        // Composite disruption index.
        let fCDI = "0,6·(100 − SRI) + 0,25·min(100, 40·jet lag h) + 0,15·min(100, 50·DE hora de acostarse h)"
        let bedSD = main.count >= 5 ? Num.sd(main.suffix(14).map { midSleepMinutes($0, calendar: calendar) - Double($0.end - $0.start) / 120 }).map { $0 / 60 } : nil
        if let r = sriRes, let sd = bedSD {
            let idx = Num.clamp(0.6 * (100 - r.sri) + 0.25 * min(100, 40 * (jetlag ?? 0)) + 0.15 * min(100, 50 * sd), 0, 100)
            out.append(MetricResult(id: "circadian", name: "Índice de disrupción del ritmo", value: idx.rounded(), unit: "/100",
                                    summary: (idx < 25 ? "Ritmo estable." : (idx < 50 ? "Algo de desorden en tus horarios." : "Ritmo bastante alterado: horarios cambiantes.")) +
                                        " Mide la irregularidad observable, no tu reloj biológico interno.",
                                    confidence: .from(samples: r.days, medium: 10, high: 14), sampleSize: r.days, formula: fCDI, version: version))
        } else {
            out.append(.insufficient("circadian", "Índice de disrupción del ritmo", unit: "/100", need: "dos semanas de noches", have: main.count,
                                     formula: fCDI, version: version))
        }
        return out
    }

    // MARK: - Nocturnal heart-rate nadir

    /// Position of the lowest 15-minute heart rate within the night (0 = falling asleep, 1 = waking).
    public static func nadirFraction(_ s: SleepSession) -> Double? {
        let pts = s.trend.compactMap { p in p.hr.map { (ts: p.ts, hr: $0) } }
        guard pts.count >= 12, s.end > s.start else { return nil }
        var best = Double.infinity, at = 0
        for i in 0...(pts.count - 3) {
            let m = (pts[i].hr + pts[i + 1].hr + pts[i + 2].hr) / 3
            if m < best { best = m; at = pts[i + 1].ts }
        }
        return Double(at - s.start) / Double(s.end - s.start)
    }

    public static func nadirMetric(_ sleeps: [SleepSession]) -> MetricResult {
        let f = "Momento del mínimo de FC (media de 15 min) como fracción de la noche; mediana de 14 noches"
        let fr = sleeps.filter { !$0.isNap }.suffix(14).compactMap(nadirFraction)
        guard fr.count >= 5, let med = Num.median(fr) else {
            return .insufficient("nadir", "Mínimo de pulso nocturno", unit: "%", need: "5 noches con pulso", have: fr.count, formula: f, version: version)
        }
        let text: String
        switch med {
        case ..<0.5: text = "Tu pulso toca fondo en la primera mitad de la noche: te recuperas pronto."
        case ..<0.7: text = "Tu pulso toca fondo hacia la mitad de la noche."
        default: text = "Tu pulso toca fondo tarde, al final de la noche. Suele pasar con cenas tardías, alcohol, entrenos nocturnos o estrés."
        }
        return MetricResult(id: "nadir", name: "Mínimo de pulso nocturno", value: (med * 100).rounded(), unit: "% de la noche", summary: text,
                            confidence: .from(samples: fr.count, medium: 8, high: 14), sampleSize: fr.count, formula: f, version: version)
    }

    // MARK: - Sleep structure → recovery

    /// Two personal regressions on the nights each one can use:
    /// - timing: recovery ~ hours asleep + |bedtime − usual bedtime| (h). Imported nights count (they have
    ///   bedtime and hours), with a source term so the two recovery scales don't mix.
    /// - awakenings: recovery ~ hours asleep + awakenings + |bedtime shift|, only nights with an awakening count
    ///   (imported summaries don't carry it).
    /// Both give 90 % intervals.
    public static func sleepEffects(days: [DaySummary], calendar: Calendar = .current) -> [MetricResult] {
        let fFrag = "Regresión recuperación ~ horas dormidas + despertares + |hora de acostarse − la habitual|; sólo noches con despertares contados; coeficiente de despertares con IC 90 %"
        let fTime = "Regresión recuperación ~ horas dormidas + |hora de acostarse − la habitual| (+ término por fuente si mezcla noches importadas); coeficiente por hora de desfase con IC 90 %"
        struct Row { var y: Double; var h: Double; var w: Double?; var bed: Double; var imported: Bool }
        let rows = days.compactMap { d -> Row? in
            guard let r = d.recovery, let m = d.sleepMinutes, let s = d.sleepStart else { return nil }
            var b = SleepCoachMinutes.minutesAfterMidnight(ts: s, calendar: calendar)
            if b < 12 * 60 { b += 1440 }
            return Row(y: r, h: m / 60, w: d.disturbances.map(Double.init), bed: b, imported: d.source != "strap")
        }
        func sig(_ c: ClosedRange<Double>) -> Bool { c.lowerBound > 0 || c.upperBound < 0 }
        func fitCoef(_ x: [[Double]], _ y: [Double], _ j: Int) -> (Double, ClosedRange<Double>)? {
            guard let fit = Num.ridge(x, y), let se = fit.se else { return nil }
            let t = Num.tCritical(df: fit.n - (x.first?.count ?? 0) - 1)
            return (fit.beta[j], (fit.beta[j] - t * se[j])...(fit.beta[j] + t * se[j]))
        }

        var out: [MetricResult] = []
        let fragRows = rows.filter { $0.w != nil }
        if fragRows.count >= 21, let usual = Num.median(fragRows.map(\.bed)),
           let (wake, wci) = fitCoef(fragRows.map { [$0.h, $0.w ?? 0, abs($0.bed - usual) / 60] }, fragRows.map(\.y), 2) {
            out.append(MetricResult(id: "fragmentationCost", name: "Coste de cada despertar", value: (wake * 10).rounded() / 10, unit: "pts", summary:
                            sig(wci) ? String(format: "Cada despertar de más se asocia con %+.1f puntos de recuperación (a igual duración de sueño). Asociación, no causa.", locale: Num.spanish, wake)
                                     : "No se ve una relación clara entre tus despertares y tu recuperación.",
                         interval: wci, confidence: .from(samples: fragRows.count, medium: 40, high: 80), sampleSize: fragRows.count,
                         formula: fFrag, version: version))
        } else {
            out.append(.insufficient("fragmentationCost", "Coste de cada despertar", unit: "pts",
                                     need: "21 noches medidas por Pulso (las importadas no traen los despertares)", have: fragRows.count,
                                     formula: fFrag, version: version))
        }

        let mixed = rows.filter(\.imported).count >= 5 && rows.filter { !$0.imported }.count >= 5
        if rows.count >= 21, let usual = Num.median(rows.map(\.bed)),
           let (bed, bci) = fitCoef(rows.map { [$0.h, abs($0.bed - usual) / 60] + (mixed ? [$0.imported ? 1 : 0] : []) }, rows.map(\.y), 2) {
            out.append(MetricResult(id: "timingSensitivity", name: "Sensibilidad al horario", value: (bed * 10).rounded() / 10, unit: "pts/h", summary:
                            sig(bci) ? String(format: "Cada hora que te acuestas fuera de tu hora habitual se asocia con %+.1f puntos de recuperación, aun durmiendo lo mismo. Asociación, no causa.", locale: Num.spanish, bed)
                                     : "Tu recuperación no parece depender de a qué hora te acuestas, sino de cuánto duermes.",
                         interval: bci, confidence: .from(samples: rows.count, medium: 40, high: 80), sampleSize: rows.count,
                         formula: fTime, version: version))
        } else {
            out.append(.insufficient("timingSensitivity", "Sensibilidad al horario", unit: "pts/h", need: "21 noches con recuperación y hora de acostarse",
                                     have: rows.count, formula: fTime, version: version))
        }
        return out
    }

    // MARK: - Cardiac cost of daily life

    /// Compares only complete days: the cycle in progress (`today` and later) has fewer awake minutes, so a
    /// relative % against full days would always read low. It is reported apart, without comparison.
    public static func cardiacCostMetric(_ days: [DaySummary], today: String) -> MetricResult {
        let f = "CCDL = Σ max(0, FC − FC reposo) por minuto despierto, fuera de entrenos y siestas (latidos de más); último día completo frente a la mediana de los 28 días completos anteriores"
        let all = days.sorted { $0.day < $1.day }.compactMap { d in d.extraBeats.map { (day: d.day, beats: $0) } }
        let complete = all.filter { $0.day < today }
        let partial = all.last { $0.day >= today }
        let partialText = partial.map { " Hoy, en lo que va de día: \(Int($0.beats).formatted()) (sin comparar: el día no ha terminado)." } ?? ""
        guard complete.count >= 5, let last = complete.last, let med = Num.median(complete.dropLast().suffix(28).map(\.beats)), med > 0 else {
            return .insufficient("cardiacCost", "Coste cardíaco del día", unit: "latidos",
                                 need: "5 días completos medidos por Pulso (los importados no traen el pulso minuto a minuto)", have: complete.count,
                                 formula: f, version: version)
        }
        let rel = (last.beats / med - 1) * 100
        let when = last.day == DayKey.shift(today, days: -1) ? "Ayer" : "El \(Deviation.shortDate(last.day))"
        let text = "\(when) tu corazón hizo \(Int(last.beats).formatted()) latidos de más fuera de los entrenos" +
            (abs(rel) < 10 ? ", lo normal para ti." : String(format: ", un %+.0f %% frente a tu día típico.", locale: Num.spanish, rel)) + partialText +
            " Estrés, calor, cafeína o enfermedad lo suben. No mide calorías."
        return MetricResult(id: "cardiacCost", name: "Coste cardíaco del día", value: last.beats.rounded(), unit: "latidos", summary: text,
                            confidence: .from(samples: complete.count, medium: 10, high: 28), sampleSize: complete.count, formula: f, version: version)
    }
}

/// Local copy of the clock helper (keeps this module independent of PulsoAnalytics internals).
enum SleepCoachMinutes {
    static func minutesAfterMidnight(ts: Int, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}
