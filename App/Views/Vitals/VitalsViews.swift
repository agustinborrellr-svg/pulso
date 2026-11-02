import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

// MARK: - Model

/// One vital of the latest night against your own last-30-nights range: green inside it, orange a bit outside on
/// the bad side, red well outside.
struct VitalReading: Identifiable {
    enum Level: Int, Comparable {
        case none, green, orange, red
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    let id: String
    let icon: String
    let title: String
    let short: String
    let metric: TrendMetric
    let raw: Double
    let value: String
    let unit: String
    let level: Level
    let chip: String
    let when: String
    let explanation: String
    let detail: String
    let limits: [(Level, String)]
    /// Your usual range (green) and the outer limit (orange), in the vital's own units; nil while calibrating.
    let range: ClosedRange<Double>?
    let outer: ClosedRange<Double>?
    /// +1 when high is bad, −1 when low is bad, 0 both ways.
    let bad: Int
    let format: (Double) -> String
    /// Nights of the 30 days up to this one, oldest first.
    let history: [(day: String, value: Double)]

    static func color(_ l: Level) -> Color {
        switch l {
        case .green: return Theme.better
        case .orange: return Theme.worse
        case .red: return Theme.red
        case .none: return Theme.secondary
        }
    }

    var color: Color { Self.color(level) }
}

/// All vitals in one verdict: bien (all in range), regular (something a bit off) or mal (something well off).
struct VitalsSummary {
    let readings: [VitalReading]

    var judged: [VitalReading] { readings.filter { $0.level != .none } }
    var inRange: Int { judged.filter { $0.level == .green }.count }
    var worst: VitalReading.Level { judged.map(\.level).max() ?? .none }
    var off: [VitalReading] { judged.filter { $0.level != .green } }

    var word: String {
        if readings.isEmpty { return "Sin datos" }
        switch worst {
        case .none: return "Calibrando"
        case .green: return "Bien"
        case .orange: return "Regular"
        case .red: return "Mal"
        }
    }

    var icon: String {
        switch worst {
        case .green: return "checkmark.circle.fill"
        case .orange: return "exclamationmark.circle.fill"
        case .red: return "exclamationmark.triangle.fill"
        case .none: return "hourglass"
        }
    }

    var color: Color { VitalReading.color(worst) }

    var count: String { judged.isEmpty ? "" : "\(inRange)/\(judged.count) en tu rango" }

    var sentence: String {
        if readings.isEmpty { return "Aparecen tras tu primera noche con la pulsera." }
        if judged.isEmpty { return "Tu rango normal se calcula con 4 noches." }
        if off.isEmpty { return "Todas tus constantes están en tu rango habitual." }
        let names = off.map(\.short)
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " y " + names.last!
        return "Fuera de lo normal: \(list)."
    }
}

extension AppModel {
    var vitalsSummary: VitalsSummary { VitalsSummary(readings: vitalReadings()) }

    func vitalReadings() -> [VitalReading] {
        var out: [VitalReading] = []
        func add(_ id: String, _ icon: String, _ title: String, _ short: String, _ metric: TrendMetric, _ key: KeyPath<DaySummary, Double?>,
                 unit: String, bad: Int, fmt: @escaping (Double) -> String, base: (Baselines) -> Baseline?, log: Bool = false,
                 phrase: String, explanation: String) {
            guard let (v, d) = latestDay(with: key) else { return }
            let b = Baselines.from(history: days.filter { $0.day < d.day && $0.day >= DayKey.shift(d.day, days: -30) })
            let toUser: (Double) -> Double = log ? { exp($0) } : { $0 }
            let x = log ? Foundation.log(max(v, 1)) : v
            var level = VitalReading.Level.none, chip = "calibrando tu rango", limits: [(VitalReading.Level, String)] = [], detail = ""
            var range: ClosedRange<Double>?, outer: ClosedRange<Double>?
            if let bl = base(b), bl.isUsable {
                let z = bl.z(x) * Double(bad == 0 ? 1 : bad)
                let a = bad == 0 ? abs(z) : z
                level = a < 1.5 ? .green : (a < 2.5 ? .orange : .red)
                let lo = toUser(bl.center - 1.5 * bl.spread), hi = toUser(bl.center + 1.5 * bl.spread)
                let lo2 = toUser(bl.center - 2.5 * bl.spread), hi2 = toUser(bl.center + 2.5 * bl.spread)
                range = lo...hi
                outer = lo2...hi2
                chip = level == .green ? "en tu rango"
                    : ((bad >= 0 && x > bl.center) ? (level == .red ? "muy alta" : "alta") : (level == .red ? "muy baja" : "baja")) + " para ti"
                detail = "Tu \(phrase) de \(fmt(v)) \(unit) \(level == .green ? "está dentro de" : "está fuera de") tu rango típico de \(fmt(lo)) a \(fmt(hi)) \(unit)."
                switch bad {
                case 1: limits = [(.green, "Verde = \(fmt(hi)) \(unit) e inferior"), (.orange, "Naranja = \(fmt(hi)) a \(fmt(hi2)) \(unit)"), (.red, "Rojo = \(fmt(hi2)) \(unit) y superior")]
                case -1: limits = [(.green, "Verde = \(fmt(lo)) \(unit) y superior"), (.orange, "Naranja = \(fmt(lo2)) a \(fmt(lo)) \(unit)"), (.red, "Rojo = \(fmt(lo2)) \(unit) e inferior")]
                default: limits = [(.green, "Verde = \(fmt(lo)) a \(fmt(hi)) \(unit)"), (.orange, "Naranja = fuera, hasta \(fmt(lo2)) / \(fmt(hi2)) \(unit)"), (.red, "Rojo = más allá")]
                }
            }
            let when = d.day == currentDayKey ? "Anoche" : Fmt.dayTitle(d.day)
            let from = DayKey.shift(d.day, days: -29)
            let history: [(day: String, value: Double)] = days.filter { $0.day >= from && $0.day <= d.day }.compactMap { day in day[keyPath: key].map { (day.day, $0) } }
            out.append(VitalReading(id: id, icon: icon, title: title, short: short, metric: metric, raw: v, value: fmt(v), unit: unit,
                                    level: level, chip: chip, when: when, explanation: explanation, detail: detail, limits: limits,
                                    range: range, outer: outer, bad: bad, format: fmt, history: history))
        }
        add("hrv", "waveform.path.ecg", "VFC", "VFC", .hrv, \.hrv, unit: "ms", bad: -1, fmt: { Fmt.int($0) }, base: { $0.lnHRV }, log: true,
            phrase: "VFC",
            explanation: "La variación del tiempo entre latidos. Alta = tu sistema nervioso está relajado y te recuperas bien; baja = fatiga física o mental, deshidratación, alcohol, estrés o enfermedad.")
        add("rhr", "heart", "FC en reposo", "FC en reposo", .rhr, \.rhr, unit: "lpm", bad: 1, fmt: { Fmt.int($0) }, base: { $0.rhr },
            phrase: "FC en reposo",
            explanation: "Las veces que late tu corazón por minuto en tu sueño más tranquilo. Más alta de lo habitual suele indicar entreno duro el día anterior, alcohol, poco sueño o que estás incubando algo.")
        add("resp", "lungs", "Frecuencia respiratoria", "Respiración", .respRate, \.respRate, unit: "rpm", bad: 1, fmt: { Fmt.dec($0) }, base: { $0.resp },
            phrase: "frecuencia respiratoria",
            explanation: "Respiraciones por minuto mientras duermes. Es muy estable de una noche a otra: si sube, suele ser por enfermedad, alcohol o un entreno muy exigente.")
        add("temp", "thermometer.medium", "Temperatura cutánea", "Temperatura", .skinTemp, \.skinTemp, unit: "°C", bad: 0, fmt: { Fmt.dec($0) }, base: { $0.temp },
            phrase: "temperatura de la piel",
            explanation: "La temperatura de la piel durante la noche. Cambia con el ambiente y la ropa de cama; una subida varias noches seguidas puede anunciar fiebre o, en mujeres, la fase lútea.")
        add("spo2", "drop", "Oxígeno en sangre (SpO₂)", "SpO₂", .spo2, \.spo2, unit: "%", bad: -1, fmt: { Fmt.int($0) }, base: { $0.spo2 },
            phrase: "SpO₂",
            explanation: "Cuánto oxígeno llevan los glóbulos rojos. Lectura experimental de la pulsera: úsala solo como tendencia.")
        return out
    }
}

// MARK: - Range bar

/// Where tonight's value sits: your usual range in green, orange just outside it on the bad side, red beyond; a
/// white dot marks the value.
struct VitalRangeBar: View {
    let reading: VitalReading
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            if let r = reading.range, let o = reading.outer {
                let span = o.upperBound - o.lowerBound
                let lo = min(o.lowerBound - span * 0.2, reading.raw), hi = max(o.upperBound + span * 0.2, reading.raw)
                let x = { (v: Double) in CGFloat((v - lo) / max(hi - lo, 0.0001)) * w }
                let lowSide: (VitalReading.Level, VitalReading.Level) = reading.bad == 1 ? (.green, .green) : (.red, .orange)
                let highSide: (VitalReading.Level, VitalReading.Level) = reading.bad == -1 ? (.green, .green) : (.orange, .red)
                let parts: [(Double, Double, VitalReading.Level)] = [
                    (lo, o.lowerBound, lowSide.0), (o.lowerBound, r.lowerBound, lowSide.1), (r.lowerBound, r.upperBound, .green),
                    (r.upperBound, o.upperBound, highSide.0), (o.upperBound, hi, highSide.1),
                ]
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                            Rectangle().fill(VitalReading.color(p.2).opacity(p.2 == .green ? 0.55 : 0.4))
                                .frame(width: max(0, x(p.1) - x(p.0)), height: height)
                                .offset(x: x(p.0))
                        }
                    }
                    .frame(width: w, height: height, alignment: .leading)
                    .clipShape(Capsule())
                    Circle().fill(.white)
                        .overlay(Circle().stroke(reading.color, lineWidth: 2.5))
                        .frame(width: height + 8, height: height + 8)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .offset(x: min(max(x(reading.raw) - (height + 8) / 2, 0), w - height - 8))
                }
                .frame(height: height + 8)
            } else {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: height).frame(maxHeight: .infinity)
            }
        }
        .frame(height: height + 8)
    }
}

// MARK: - Inicio: verdict only

/// Inicio's compact tile: are your vitals fine, so-so or off. Opens the vitals page.
struct HomeVitalsStatusTile: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.vitalsSummary
        NavigationLink { VitalsView() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Caps("Constantes", size: 10.5, weight: .semibold)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.tertiary)
                }
                HStack(spacing: 8) {
                    Image(systemName: s.icon).font(.title3).foregroundStyle(s.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Caps(s.word, size: 15, color: s.color)
                        if !s.count.isEmpty {
                            Text(s.count).scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 4) {
                    ForEach(s.readings) { r in Capsule().fill(r.color).frame(height: 4) }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Inicio's stress tile next to the vitals one: the latest level.
struct HomeStressStatusTile: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.selected ?? model.today
        let hourly = day?.stressHourly ?? []
        let start = day?.cycleStartHour ?? 0
        let lastHour = (0..<24).map { (start + $0) % 24 }.last { $0 < hourly.count && hourly[$0] != nil }
        let current = lastHour.flatMap { hourly[$0] }
        NavigationLink { StressMonitorView() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Caps("Estrés", size: 10.5, weight: .semibold)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.tertiary)
                }
                HStack(spacing: 8) {
                    Text(current.map { Fmt.dec($0) } ?? "–")
                        .scaledFont(15, weight: .bold, relativeTo: .body).monospacedDigit()
                        .foregroundStyle(Theme.stressColor(current))
                        .frame(width: 34, height: 34)
                        .background(Theme.stressColor(current).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 1) {
                        Caps(current == nil ? "Sin lecturas" : Theme.stressLevel(current), size: 15, color: Theme.stressColor(current))
                        Text(lastHour.map { String(format: "a las %02d:00", $0) } ?? "se mide quieto y despierto")
                            .scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: [Theme.stressLow, Theme.stressMid, Theme.stressHigh], startPoint: .leading, endPoint: .trailing))
                            .opacity(0.5)
                        if let c = current {
                            Circle().fill(.white).frame(width: 8, height: 8).offset(x: CGFloat(min(max(c / 3, 0), 1)) * (g.size.width - 8))
                        }
                    }
                }
                .frame(height: 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - En vivo: one visual card

/// «Tus constantes» in one card: the verdict, then each vital with its value and where it sits in your range.
/// Tap for the page with every vital and its last 30 nights.
struct VitalsCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.vitalsSummary
        NavigationLink { VitalsView() } label: {
            PCard {
                HStack(alignment: .center) {
                    Caps("Tus constantes")
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: s.icon)
                        Caps(s.word, size: 12, color: s.color)
                    }
                    .foregroundStyle(s.color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(s.color.opacity(0.14), in: Capsule())
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.tertiary)
                }
                Text(s.sentence).font(.caption).foregroundStyle(Theme.secondary)
                if s.readings.isEmpty {
                    EmptyView()
                } else {
                    VStack(spacing: 14) {
                        ForEach(s.readings) { r in
                            VStack(spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: r.icon).font(.footnote).foregroundStyle(r.color).frame(width: 18)
                                    Text(r.short).font(.subheadline).foregroundStyle(.white)
                                    Spacer()
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(r.value).scaledFont(17, weight: .bold, design: .rounded, relativeTo: .body).monospacedDigit().foregroundStyle(.white)
                                        Text(r.unit).font(.caption2).foregroundStyle(Theme.secondary)
                                    }
                                }
                                VitalRangeBar(reading: r, height: 6)
                            }
                        }
                    }
                    if let when = s.readings.first?.when {
                        Text("\(when) · comparado con tus 30 noches anteriores").font(.caption2).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Page: every vital with its nights

struct VitalsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.vitalsSummary
        DetailScreen(title: "Constantes") {
            PCard {
                HStack(spacing: 12) {
                    Image(systemName: s.icon).font(.system(size: 34)).foregroundStyle(s.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Caps(s.word, size: 22, color: s.color)
                        if !s.count.isEmpty { Text(s.count).font(.subheadline).foregroundStyle(.white) }
                    }
                }
                Text(s.sentence).font(.subheadline).foregroundStyle(Theme.secondary)
                HStack(spacing: 12) {
                    legend(.green, "En tu rango")
                    legend(.orange, "Algo fuera")
                    legend(.red, "Muy fuera")
                }
            }
            ForEach(s.readings) { r in
                NavigationLink { VitalDetailView(id: r.id) } label: { VitalRow(reading: r) }.buttonStyle(.plain)
            }
            Text("Cada constante se compara solo contigo: tu rango son tus 30 noches anteriores. Pulso no es un dispositivo médico.")
                .font(.caption2).foregroundStyle(Theme.tertiary)
        }
    }

    private func legend(_ l: VitalReading.Level, _ t: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(VitalReading.color(l)).frame(width: 7, height: 7)
            Text(t).font(.caption2).foregroundStyle(Theme.secondary)
        }
    }
}

/// A vital on the vitals page: value, verdict, range bar and its last nights.
struct VitalRow: View {
    let reading: VitalReading

    var body: some View {
        PCard {
            HStack(alignment: .top) {
                Image(systemName: reading.icon).foregroundStyle(Theme.secondary)
                Caps(reading.title, size: 11, color: Theme.secondary, weight: .semibold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.tertiary)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(reading.value).scaledFont(34, weight: .bold, design: .rounded, relativeTo: .title1).monospacedDigit().foregroundStyle(.white)
                        Text(reading.unit).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                    VitalChip(reading: reading)
                }
                Spacer(minLength: 12)
                VitalSpark(reading: reading).frame(width: 130, height: 54)
            }
            VitalRangeBar(reading: reading)
        }
    }
}

struct VitalChip: View {
    let reading: VitalReading

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: reading.level == .green || reading.level == .none ? "checkmark" : "exclamationmark").font(.caption2.bold())
            Text(reading.chip).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(reading.color)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(reading.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Last nights as a small line over your green range.
struct VitalSpark: View {
    let reading: VitalReading

    var body: some View {
        let pts = reading.history.compactMap { p in DayKey.date(p.day).map { (date: $0, value: p.value) } }
        Chart {
            if let r = reading.range, let first = pts.first?.date, let last = pts.last?.date {
                RectangleMark(xStart: .value("a", first), xEnd: .value("b", last), yStart: .value("lo", r.lowerBound), yEnd: .value("hi", r.upperBound))
                    .foregroundStyle(Theme.better.opacity(0.14))
            }
            ForEach(pts, id: \.date) { p in
                LineMark(x: .value("Noche", p.date), y: .value("v", p.value))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .interpolationMethod(.monotone)
            }
            if let p = pts.last {
                PointMark(x: .value("Noche", p.date), y: .value("v", p.value)).foregroundStyle(reading.color).symbolSize(40)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

// MARK: - One vital in full

struct VitalDetailView: View {
    @EnvironmentObject var model: AppModel
    let id: String
    @State private var selected: Date?

    var body: some View {
        if let r = model.vitalReadings().first(where: { $0.id == id }) {
            DetailScreen(title: r.short) {
                PCard {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(r.value).scaledFont(52, weight: .bold, design: .rounded, relativeTo: .largeTitle).monospacedDigit().foregroundStyle(.white)
                        Text(r.unit).font(.title3).foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text(r.when).font(.caption).foregroundStyle(Theme.secondary)
                    }
                    VitalChip(reading: r)
                    VitalRangeBar(reading: r, height: 10)
                    if !r.detail.isEmpty { Text(r.detail).font(.subheadline).foregroundStyle(.white) }
                }
                PCard {
                    CardHeader(title: "Últimas 30 noches", subtitle: "Franja verde: tu rango. Desliza el dedo para leer cada noche.")
                    chart(r).frame(height: 200)
                }
                PCard {
                    CardHeader(title: "Qué significa")
                    Text(r.explanation).font(.subheadline).foregroundStyle(.white)
                    if !r.limits.isEmpty {
                        Text("Tus límites, con tus 30 noches anteriores:").font(.caption).foregroundStyle(Theme.secondary)
                        ForEach(Array(r.limits.enumerated()), id: \.offset) { _, l in
                            HStack(spacing: 8) {
                                Circle().fill(VitalReading.color(l.0)).frame(width: 8, height: 8)
                                Text(l.1).font(.subheadline).foregroundStyle(.white)
                            }
                        }
                    }
                }
                NavigationLink { TrendDetailView(metric: r.metric) } label: {
                    HStack {
                        Image(systemName: "chart.xyaxis.line").foregroundStyle(Theme.link)
                        Text("Ver toda la tendencia").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                Text("Pulso no es un dispositivo médico. Consulta a un profesional antes de tomar decisiones de salud.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
        } else {
            DetailScreen(title: "Constantes") {
                EmptyState(icon: "waveform.path.ecg", title: "Sin datos", message: "Aún no hay noches con esta constante.")
            }
        }
    }

    private func chart(_ r: VitalReading) -> some View {
        let pts = r.history.compactMap { p in DayKey.date(p.day).map { (date: $0, value: p.value) } }
        let sel = selected.flatMap { s in pts.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } }
        return Chart {
            if let range = r.range, let first = pts.first?.date, let last = pts.last?.date {
                RectangleMark(xStart: .value("a", first), xEnd: .value("b", last), yStart: .value("lo", range.lowerBound), yEnd: .value("hi", range.upperBound))
                    .foregroundStyle(Theme.better.opacity(0.14))
            }
            ForEach(pts, id: \.date) { p in
                LineMark(x: .value("Noche", p.date), y: .value("v", p.value))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Noche", p.date), y: .value("v", p.value))
                    .foregroundStyle(level(r, p.value))
                    .symbolSize(22)
            }
            if let s = sel {
                RuleMark(x: .value("Noche", s.date))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text("\(r.format(s.value)) \(r.unit)").font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
                            Text(s.date.formatted(.dateTime.day().month(.abbreviated))).font(.caption2).foregroundStyle(Theme.secondary)
                        }
                        .padding(6)
                        .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 6))
                    }
                PointMark(x: .value("Noche", s.date), y: .value("v", s.value)).foregroundStyle(.white).symbolSize(70)
            }
        }
        .chartScrub($selected)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
    }

    /// Colour of one night against the current range.
    private func level(_ r: VitalReading, _ v: Double) -> Color {
        guard let range = r.range, let o = r.outer else { return .white }
        if range.contains(v) { return Theme.better }
        if (r.bad == 1 && v < range.lowerBound) || (r.bad == -1 && v > range.upperBound) { return Theme.better }
        return o.contains(v) ? Theme.worse : Theme.red
    }
}
