import SwiftUI
import PulsoStore
import PulsoAnalytics

/// Every metric that has a trend screen: what it is, how to read and draw it, and what it means.
enum TrendMetric: String, CaseIterable, Identifiable {
    case recovery, hrv, rhr, respRate, spo2, skinTemp
    case sleepPerformance, sleepHours, hoursVsNeed, restorativeHours, restorativePct, regularity, efficiency, sleepDebt, timeInBed
    case strain, avgHR, calories, steps, zonesLight, zonesHard, vo2max
    case stress, stressHigh

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case recovery = "Recuperación"
        case sleep = "Sueño"
        case strain = "Esfuerzo"
        case stress = "Estrés"
    }

    enum Kind { case bar, line }

    var group: Group {
        switch self {
        case .recovery, .hrv, .rhr, .respRate, .spo2, .skinTemp: return .recovery
        case .sleepPerformance, .sleepHours, .hoursVsNeed, .restorativeHours, .restorativePct, .regularity, .efficiency, .sleepDebt, .timeInBed:
            return .sleep
        case .strain, .avgHR, .calories, .steps, .zonesLight, .zonesHard, .vo2max: return .strain
        case .stress, .stressHigh: return .stress
        }
    }

    var title: String {
        switch self {
        case .recovery: return "Recuperación"
        case .hrv: return "Variabilidad de la frecuencia cardíaca"
        case .rhr: return "Frecuencia cardíaca en reposo"
        case .respRate: return "Frecuencia respiratoria"
        case .spo2: return "Oxígeno en sangre"
        case .skinTemp: return "Temperatura cutánea"
        case .sleepPerformance: return "Calificación del sueño"
        case .sleepHours: return "Horas de sueño"
        case .hoursVsNeed: return "Horas vs. lo necesario"
        case .restorativeHours: return "Sueño reparador (h)"
        case .restorativePct: return "Sueño reparador (%)"
        case .regularity: return "Regularidad del sueño"
        case .efficiency: return "Eficiencia del sueño"
        case .sleepDebt: return "Deuda de sueño"
        case .timeInBed: return "Tiempo en cama"
        case .strain: return "Esfuerzo del día"
        case .avgHR: return "Frecuencia cardíaca promedio"
        case .calories: return "Calorías"
        case .steps: return "Pasos"
        case .zonesLight: return "Zonas de FC 1-3"
        case .zonesHard: return "Zonas de FC 4-5"
        case .vo2max: return "VO₂ máx"
        case .stress: return "Estrés diurno"
        case .stressHigh: return "Estrés alto"
        }
    }

    var icon: String {
        switch self {
        case .recovery: return "bolt.heart"
        case .hrv: return "waveform.path.ecg"
        case .rhr: return "heart"
        case .respRate: return "lungs"
        case .spo2: return "drop"
        case .skinTemp: return "thermometer.medium"
        case .sleepPerformance: return "moon"
        case .sleepHours: return "moon.zzz"
        case .hoursVsNeed: return "bed.double"
        case .restorativeHours, .restorativePct: return "sparkles"
        case .regularity: return "clock.arrow.circlepath"
        case .efficiency: return "chart.bar"
        case .sleepDebt: return "hourglass"
        case .timeInBed: return "timer"
        case .strain: return "flame"
        case .avgHR: return "heart.text.square"
        case .calories: return "flame"
        case .steps: return "shoeprints.fill"
        case .zonesLight, .zonesHard: return "heart.circle"
        case .vo2max: return "lungs.fill"
        case .stress, .stressHigh: return "gauge.with.dots.needle.33percent"
        }
    }

    var kind: Kind {
        switch self {
        case .hrv, .rhr, .respRate, .spo2, .skinTemp, .efficiency, .avgHR, .vo2max, .stress: return .line
        default: return .bar
        }
    }

    var aggregate: TrendSeries.Aggregate {
        switch self {
        case .zonesLight, .zonesHard, .stressHigh: return .total
        default: return .average
        }
    }

    /// nil when neither direction is "better".
    var higherIsBetter: Bool? {
        switch self {
        case .recovery, .hrv, .sleepPerformance, .sleepHours, .hoursVsNeed, .restorativeHours, .restorativePct, .regularity,
             .efficiency, .steps, .zonesLight, .zonesHard, .vo2max, .spo2:
            return true
        case .rhr, .sleepDebt, .stress, .stressHigh, .respRate:
            return false
        case .skinTemp, .strain, .avgHR, .calories, .timeInBed:
            return nil
        }
    }

    func value(_ d: DaySummary) -> Double? {
        switch self {
        case .recovery: return d.recovery
        case .hrv: return d.hrv
        case .rhr: return d.rhr
        case .respRate: return d.respRate
        case .spo2: return d.spo2
        case .skinTemp: return d.skinTemp
        case .sleepPerformance: return d.sleepPerformance.map { $0 * 100 }
        case .sleepHours: return d.sleepMinutes
        case .hoursVsNeed:
            guard let s = d.sleepMinutes, let n = d.sleepNeedMinutes, n > 0 else { return nil }
            return s / n * 100
        case .restorativeHours:
            if let r = d.restorativeMinutes { return r }
            guard let a = d.deepMinutes, let b = d.remMinutes else { return nil }
            return a + b
        case .restorativePct:
            guard let s = d.sleepMinutes, s > 0, let r = TrendMetric.restorativeHours.value(d) else { return nil }
            return r / s * 100
        case .regularity: return d.sleepConsistency
        case .efficiency: return d.sleepEfficiency.map { $0 * 100 }
        case .sleepDebt: return d.sleepDebtMinutes
        case .timeInBed:
            if let m = d.inBedMinutes { return m }
            guard let a = d.sleepStart, let b = d.sleepEnd, b > a else { return nil }
            return Double(b - a) / 60
        case .strain: return d.strain
        case .avgHR: return d.avgHR
        case .calories: return d.kcal
        case .steps: return d.steps.map(Double.init)
        case .zonesLight:
            let z = d.zoneMinutes
            let v = z.prefix(3).reduce(0, +)
            return d.strain == nil && v == 0 ? nil : v
        case .zonesHard:
            let z = d.zoneMinutes
            let v = z.dropFirst(3).reduce(0, +)
            return d.strain == nil && v == 0 ? nil : v
        case .vo2max: return d.vo2max
        case .stress: return d.stressAvg
        case .stressHigh: return d.stressHighMinutes
        }
    }

    /// Unit shown next to the big number ("" when the format already says it).
    var unit: String {
        switch self {
        case .recovery, .sleepPerformance, .hoursVsNeed, .restorativePct, .regularity, .efficiency, .spo2: return "%"
        case .hrv: return "ms"
        case .rhr, .avgHR: return "lpm"
        case .respRate: return "rpm"
        case .skinTemp: return "°C"
        case .sleepHours, .restorativeHours, .sleepDebt, .timeInBed, .zonesLight, .zonesHard, .stressHigh: return "hr"
        case .calories: return "Calorías"
        case .vo2max: return "mL/kg/min"
        case .strain, .steps, .stress: return ""
        }
    }

    var isDuration: Bool {
        switch self {
        case .sleepHours, .restorativeHours, .sleepDebt, .timeInBed, .zonesLight, .zonesHard, .stressHigh: return true
        default: return false
        }
    }

    func format(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "–" }
        if isDuration { return Fmt.hmm(v) }
        switch self {
        case .strain, .respRate, .stress, .spo2: return Fmt.dec(v)
        case .skinTemp: return Fmt.dec(v, 2)
        case .steps, .calories: return Fmt.thousands(v)
        default: return "\(Int(v.rounded()))"
        }
    }

    /// Text on top of a bar / point.
    func label(_ v: Double) -> String {
        guard v.isFinite else { return "–" }
        switch self {
        case .recovery, .sleepPerformance, .hoursVsNeed, .restorativePct, .regularity, .efficiency: return "\(Int(v.rounded())) %"
        default: return format(v)
        }
    }

    func color(_ v: Double?) -> Color {
        switch self {
        case .recovery: return Theme.recoveryColor(v)
        case .strain, .avgHR, .calories, .steps, .zonesLight, .zonesHard, .vo2max: return Theme.strain
        case .stress, .stressHigh: return Theme.stressColor(self == .stress ? v : 1.5)
        case .hrv, .rhr, .respRate, .spo2, .skinTemp: return Theme.hrv
        default: return Theme.sleep
        }
    }

    /// Chart y-range so bars and lines sit well.
    func domain(_ values: [Double]) -> ClosedRange<Double> {
        switch self {
        case .recovery, .sleepPerformance, .restorativePct, .regularity: return 0...100
        case .strain: return 0...21
        case .stress: return 0...3
        case .hoursVsNeed: return 0...max(110, (values.max() ?? 100) * 1.08)
        default:
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            if kind == .bar { return 0...max(hi * 1.18, 1) }
            let pad = max((hi - lo) * 0.35, abs(hi) * 0.04, 1)
            return (lo - pad)...(hi + pad)
        }
    }

    /// Summary label: "PROMEDIO" or "TOTAL SEMANAL".
    func summaryLabel(_ period: TrendPeriod) -> String {
        aggregate == .total ? (period == .week ? "Total semanal" : "Media semanal") : "Promedio"
    }

    /// "▲ 3,9 vs. la semana anterior": absolute for scores, relative for the rest.
    func deltaText(_ now: Double, _ before: Double, period: TrendPeriod) -> String {
        let d = now - before
        switch self {
        case .strain, .respRate, .stress:
            return "\(Fmt.dec(abs(d))) vs. \(period.previousText)"
        case .skinTemp:
            return "\(Fmt.dec(abs(d), 2)) °C vs. \(period.previousText)"
        default:
            guard before != 0 else { return "vs. \(period.previousText)" }
            return "\(Int(abs(d / before * 100).rounded())) % vs. \(period.previousText)"
        }
    }

    func narrative(_ w: TrendWindow, period: TrendPeriod) -> String {
        let length = period == .week ? "7 días" : (period == .month ? "30 días" : "6 meses")
        guard let now = w.summary else { return "Aún no hay datos de \(title.lowercased()) en este periodo." }
        let what = aggregate == .total ? "tu total semanal de \(title.lowercased())" : "tu \(title.lowercased()) promedio"
        guard let before = w.previous, before != 0 else {
            return "Durante este periodo de \(length), \(what) fue \(format(now))\(unit.isEmpty || unit == "hr" ? "" : " \(unit)")."
        }
        let rel = (now - before) / abs(before)
        let compare = abs(rel) < 0.03 ? "estuvo cerca de" : (rel > 0 ? "fue superior a" : "fue inferior a")
        return "Durante este periodo de \(length), \(what) (\(format(now))) \(compare) \(period == .week ? "la de los 7 días anteriores" : "la del periodo anterior") (\(format(before)))."
    }

    struct Bucket: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
        /// "3x" (days) or "1:13" (time).
        let text: String
    }

    /// "DESGLOSE DE …" under the chart.
    func breakdown(_ w: TrendWindow, days: [DaySummary]) -> (title: String, buckets: [Bucket])? {
        func count(_ test: (Double) -> Bool) -> Double { Double(w.values.filter(test).count) }
        func times(_ n: Double) -> String { "\(Int(n))x" }
        switch self {
        case .recovery:
            let g = count { $0 >= 67 }, y = count { $0 >= 34 && $0 < 67 }, r = count { $0 < 34 }
            return ("Desglose de la recuperación (días)", [
                Bucket(label: "Verde (67-99%)", value: g, color: Theme.green, text: times(g)),
                Bucket(label: "Amarillo (34-66%)", value: y, color: Theme.yellow, text: times(y)),
                Bucket(label: "Rojo (1-33%)", value: r, color: Theme.red, text: times(r)),
            ])
        case .strain:
            let a = count { $0 > 18 }, b = count { $0 > 14 && $0 <= 18 }, c = count { $0 > 10 && $0 <= 14 }, d = count { $0 <= 10 }
            return ("Desglose del esfuerzo (días)", [
                Bucket(label: "Esfuerzo total (>18,0)", value: a, color: Theme.strain, text: times(a)),
                Bucket(label: "Extenuante (14,1-18,0)", value: b, color: Theme.strain.opacity(0.8), text: times(b)),
                Bucket(label: "Moderado (10,1-14,0)", value: c, color: Theme.strain.opacity(0.6), text: times(c)),
                Bucket(label: "Ligero (<10,0)", value: d, color: Theme.strain.opacity(0.4), text: times(d)),
            ])
        case .restorativePct:
            let a = count { $0 > 45 }, b = count { $0 >= 30 && $0 <= 45 }, c = count { $0 < 30 }
            return ("Desglose del % de restauración (días)", [
                Bucket(label: "Alto (>45%)", value: a, color: Theme.sleep, text: times(a)),
                Bucket(label: "Suficiente (30-45%)", value: b, color: Theme.sleep.opacity(0.65), text: times(b)),
                Bucket(label: "Bajo (<30%)", value: c, color: Theme.sleep.opacity(0.35), text: times(c)),
            ])
        case .sleepPerformance:
            let a = count { $0 >= 85 }, b = count { $0 >= 70 && $0 < 85 }, c = count { $0 < 70 }
            return ("Desglose de la calificación (días)", [
                Bucket(label: "Óptimo (≥85%)", value: a, color: Theme.sleep, text: times(a)),
                Bucket(label: "Suficiente (70-84%)", value: b, color: Theme.sleep.opacity(0.65), text: times(b)),
                Bucket(label: "Deficiente (<70%)", value: c, color: Theme.sleep.opacity(0.35), text: times(c)),
            ])
        case .zonesLight, .zonesHard:
            let range = self == .zonesLight ? 0..<3 : 3..<5
            let inWindow = days.filter { $0.day >= w.from && $0.day <= w.to }
            let totals = range.map { z in inWindow.reduce(0) { $0 + ($1.zoneMinutes.count > z ? $1.zoneMinutes[z] : 0) } }
            return ("Desglose de las zonas de FC (total)", zip(range, totals).map { z, t in
                Bucket(label: "Zona \(z + 1)", value: t, color: Theme.zoneColor(z + 1), text: Fmt.hmm(t))
            })
        default:
            return nil
        }
    }

    var explainer: (title: String, text: String) {
        switch self {
        case .recovery:
            return ("¿Qué es la recuperación?", "La recuperación mide lo preparado que está tu cuerpo para soportar esfuerzo. Se calcula por la noche con tu VFC, tu frecuencia cardíaca en reposo, tu respiración, tu temperatura y tu oxígeno, comparados con tu propio normal de las últimas semanas.\n\nEl esfuerzo, el estrés, el alcohol o enfermar pueden bajarla aunque hayas dormido bien, y al revés. Apunta tus hábitos en el diario para ver cuáles te afectan.")
        case .hrv:
            return ("¿Qué es la VFC?", "La variabilidad de la frecuencia cardíaca es la variación de tiempo entre latido y latido (RMSSD, en milisegundos), medida durante el sueño profundo. Una VFC más alta que tu normal suele indicar que tu sistema nervioso está relajado y recuperado; más baja, que está gestionando estrés, cansancio o algo que incubas.\n\nCompárala solo contigo mismo: varía mucho de una persona a otra.")
        case .rhr:
            return ("¿Qué es la frecuencia cardíaca en reposo?", "Es tu pulso más bajo y estable durante el sueño. Bajar con el tiempo suele indicar mejor forma física. Una subida de varios latidos sobre tu normal es una de las señales más claras de cansancio, alcohol, calor o enfermedad.")
        case .respRate:
            return ("¿Qué es la frecuencia respiratoria?", "Respiraciones por minuto durante el sueño, calculadas a partir de cómo cambia tu pulso al respirar. Es muy estable en cada persona: una subida sostenida de más de 1 rpm suele acompañar a infecciones respiratorias.")
        case .spo2:
            return ("¿Qué es el oxígeno en sangre?", "El porcentaje de saturación de oxígeno estimado por la pulsera durante el sueño. Lo normal es 95-100 %. Es una estimación de bienestar: no sirve para diagnosticar.")
        case .skinTemp:
            return ("¿Qué es la temperatura cutánea?", "La temperatura de tu piel en la muñeca durante el sueño. Lo importante no es el valor absoluto sino cuánto se aleja de tu normal: subidas de más de 0,5 °C suelen acompañar a fiebre, alcohol o una habitación caliente.")
        case .sleepPerformance:
            return ("¿Qué es la calificación del sueño?", "Compara lo que has dormido con lo que necesitabas esa noche. Tu necesidad sube con el esfuerzo del día anterior y con la deuda que arrastras, y baja con las siestas. 85 % o más es una noche óptima.")
        case .sleepHours:
            return ("¿Qué son las horas de sueño?", "El tiempo realmente dormido, sin contar los ratos despierto en la cama. La pulsera lo detecta por tu pulso, tu VFC y tu movimiento.")
        case .hoursVsNeed:
            return ("¿Qué es horas vs. lo necesario?", "El porcentaje de tu necesidad de sueño que cubriste. Tu necesidad = tu base (en tu perfil) + lo que pide el esfuerzo reciente + parte de tu deuda de sueño.")
        case .restorativeHours, .restorativePct:
            return ("¿Qué es el sueño reparador?", "La suma del sueño profundo (cuando el cuerpo se repara físicamente) y del REM (cuando el cerebro consolida memoria y aprendizaje). Más del 45 % del sueño es alto; menos del 30 %, bajo. Las fases son estimaciones: tómalas como orientación.")
        case .regularity:
            return ("¿Qué es la regularidad del sueño?", "Mide si te acuestas y te levantas a horas parecidas a las de los días anteriores. Un horario regular mejora la calidad del sueño y la recuperación más de lo que parece.")
        case .efficiency:
            return ("¿Qué es la eficiencia del sueño?", "El porcentaje del tiempo en cama que pasaste dormido. Por encima del 90 % es muy bueno; si baja mucho, mira cafeína, pantallas o la temperatura del cuarto.")
        case .sleepDebt:
            return ("¿Qué es la deuda de sueño?", "Lo que te ha faltado por dormir en las últimas noches. No se borra de golpe: se va pagando poco a poco durmiendo algo más que tu necesidad.")
        case .timeInBed:
            return ("¿Qué es el tiempo en cama?", "Desde que te duermes hasta que te despiertas, incluidos los ratos despierto. La pulsera no sabe cuándo te tumbas si estás quieto y despierto, así que cuenta desde que te duermes.")
        case .strain:
            return ("¿Qué es el esfuerzo del día?", "El esfuerzo mide la carga total sobre tu cuerpo durante todo el día, en una escala de 0 a 21. Suma el tiempo con el pulso alto, en entrenos y en la vida normal; cada punto cuesta más que el anterior.\n\nCompararlo con tu recuperación te ayuda a entrenar cuando estás listo y a descansar cuando lo necesitas.")
        case .avgHR:
            return ("¿Qué es la frecuencia cardíaca promedio?", "Tu pulso medio a lo largo del día. Sube con la actividad, pero también con el estrés, el calor o el cansancio. No es lo mismo que la frecuencia en reposo, que se mide durante el sueño.")
        case .calories:
            return ("¿Qué son las calorías?", "La energía que gastas cada día: tu metabolismo basal (por tu edad, peso, altura y sexo del perfil) más lo que añade tu pulso cuando te mueves. Es una estimación.")
        case .steps:
            return ("¿Qué son los pasos?", "Pasos estimados a partir del contador de la pulsera. Más pasos al día se asocian a mejor salud cardiovascular, sobre todo hasta unos 8.000-10.000.")
        case .zonesLight, .zonesHard:
            return ("¿En qué consiste el entrenamiento por zonas?", "Las zonas se calculan con tu reserva de frecuencia cardíaca (FC máx. − FC en reposo):\n• Zona 5 (90-100 %): intensidad máxima\n• Zona 4 (80-89 %): alta\n• Zona 3 (70-79 %): moderada\n• Zona 2 (60-69 %): ligera\n• Zona 1 (50-59 %): muy ligera\n\nLas zonas 1-3 construyen la base aeróbica; las 4-5, la potencia. Para la salud, lo más útil es acumular bastante tiempo en 2-3 y algo en 4-5 cada semana.")
        case .vo2max:
            return ("¿Qué es el VO₂ máx?", "La cantidad máxima de oxígeno que tu cuerpo puede usar durante el ejercicio. Es la métrica que mejor refleja la salud cardiovascular a largo plazo. Pulso la estima con tu pulso en reposo, tu frecuencia máxima y tus entrenos; es una estimación, no una prueba de laboratorio.")
        case .stress, .stressHigh:
            return ("¿Qué es el estrés?", "El estrés de 0 a 3 compara tu pulso y tu VFC con tu estado de calma cuando estás quieto y despierto, fuera de entrenos. 0-1 es bajo, 1-2 medio y 2-3 alto. El estrés no es bueno ni malo: lo importante es que haya equilibrio con momentos de calma.")
        }
    }
}
