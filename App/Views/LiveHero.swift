import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

// MARK: - Hero: live heart rate like a bedside monitor

/// Big number, beating heart, zone, and the last 90 s drawn as a line that scrolls continuously (every frame,
/// not every second) on a monitor grid, ending in a glowing dot.
struct LiveHeroMonitor: View {
    @EnvironmentObject var model: AppModel
    static let window: TimeInterval = 90

    var body: some View {
        let hr = model.liveToolBlocker == nil ? model.liveHR : nil
        let zone = hr.map { model.heartRateModel.zone(Double($0)) } ?? 0
        ZStack(alignment: .topLeading) {
            MonitorGrid()
            TimelineView(.animation(minimumInterval: 1 / 60, paused: hr == nil)) { ctx in
                Canvas { g, size in
                    draw(&g, size: size, now: ctx.date, color: Theme.zoneColor(max(zone, 1)))
                }
            }
            .padding(.leading, 120)
            VStack(alignment: .leading, spacing: 6) {
                Caps("Frecuencia cardíaca", size: 12, color: .white)
                BeatingHeart(bpm: hr, color: hr == nil ? Theme.secondary : Theme.red)
                    .frame(width: 28, height: 28)
                Text(hr.map(String.init) ?? "--")
                    .scaledFont(56, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(hr ?? 0)))
                    .animation(.snappy, value: hr)
                Caps("lpm", size: 11, color: Theme.secondary)
                Text(hr == nil ? statusText : (zone == 0 ? "Zona 0 · reposo" : "Zona \(zone)"))
                    .font(.subheadline).foregroundStyle(hr == nil ? Theme.yellow : .white)
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { z in
                        Capsule().fill(z <= zone ? Theme.zoneColor(z) : Color.white.opacity(0.15)).frame(width: 18, height: 4)
                    }
                }
            }
            .padding(16)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline))
    }

    private var statusText: String {
        if let why = model.liveToolBlocker { return why }
        return model.strapState.isConnected ? "Esperando latidos…" : "Conecta la pulsera"
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, now: Date, color: Color) {
        let from = now.addingTimeInterval(-Self.window)
        let pts = model.livePoints.filter { $0.date >= from.addingTimeInterval(-3) }
        guard pts.count >= 2 else {
            var flat = Path()
            flat.move(to: CGPoint(x: 0, y: size.height * 0.55))
            flat.addLine(to: CGPoint(x: size.width - 16, y: size.height * 0.55))
            g.stroke(flat, with: .color(Color.white.opacity(0.15)), lineWidth: 2)
            return
        }
        let values = pts.map { Double($0.hr) }
        let lo = (values.min() ?? 60) - 8, hi = (values.max() ?? 100) + 8
        let right = size.width - 16
        func p(_ point: LivePoint) -> CGPoint {
            let x = CGFloat(point.date.timeIntervalSince(from) / Self.window) * right
            let y = size.height * (0.15 + 0.7 * CGFloat(1 - (Double(point.hr) - lo) / max(hi - lo, 1)))
            return CGPoint(x: x, y: y)
        }
        // The newest reading slides to the right edge as time passes, so the line never jumps.
        var cg = pts.map(p)
        if let last = cg.last { cg.append(CGPoint(x: min(right, last.x + 2), y: last.y)) }
        var path = Path()
        path.move(to: cg[0])
        for i in 1..<cg.count {
            let mid = CGPoint(x: (cg[i - 1].x + cg[i].x) / 2, y: (cg[i - 1].y + cg[i].y) / 2)
            path.addQuadCurve(to: mid, control: cg[i - 1])
        }
        path.addLine(to: cg.last!)
        var glow = g
        glow.addFilter(.blur(radius: 6))
        glow.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 6)
        g.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0), color]), startPoint: .zero,
                                            endPoint: CGPoint(x: right, y: 0)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let end = cg.last!
        var dash = Path()
        dash.move(to: CGPoint(x: end.x, y: 8))
        dash.addLine(to: CGPoint(x: end.x, y: size.height - 8))
        g.stroke(dash, with: .color(Color.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        g.fill(Path(ellipseIn: CGRect(x: end.x - 9, y: end.y - 9, width: 18, height: 18)), with: .color(color.opacity(0.35)))
        g.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)), with: .color(.white))
    }
}

/// Faint monitor grid behind the live line.
struct MonitorGrid: View {
    var body: some View {
        Canvas { g, size in
            let step: CGFloat = 22
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            g.stroke(path, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
        }
        .background(LinearGradient(colors: [Theme.card, Theme.card.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Vitals against your normal range

/// The night's vitals, each against your own last-30-nights range: green inside it, orange a bit outside on the
/// bad side, red well outside. Tap one for what it means and the exact limits.
struct VitalsGrid: View {
    @EnvironmentObject var model: AppModel
    @State private var open: Vital?

    enum Level { case green, orange, red, none }

    struct Vital: Identifiable {
        let id: String
        let icon: String
        let title: String
        let value: String
        let unit: String
        let level: Level
        let chip: String
        let when: String
        let explanation: String
        let detail: String
        let limits: [(Level, String)]
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(vitals) { v in
                Button { open = v } label: { card(v) }.buttonStyle(.plain)
            }
        }
        .sheet(item: $open) { v in VitalSheet(vital: v).presentationDetents([.medium, .large]).preferredColorScheme(.dark) }
    }

    static func color(_ l: Level) -> Color {
        switch l {
        case .green: return Theme.better
        case .orange: return Theme.worse
        case .red: return Theme.red
        case .none: return Theme.secondary
        }
    }

    private var vitals: [Vital] {
        var out: [Vital] = []
        /// `bad`: +1 when high is bad, −1 when low is bad, 0 both ways.
        func add(_ id: String, _ icon: String, _ title: String, _ key: KeyPath<DaySummary, Double?>, unit: String, bad: Int,
                 fmt: @escaping (Double) -> String, base: (Baselines) -> Baseline?, log: Bool = false, explanation: String) {
            guard let (v, d) = model.latestDay(with: key) else { return }
            let b = Baselines.from(history: model.days.filter { $0.day < d.day && $0.day >= DayKey.shift(d.day, days: -30) })
            let toUser: (Double) -> Double = log ? { exp($0) } : { $0 }
            let x = log ? Foundation.log(max(v, 1)) : v
            var level = Level.none, chip = "calibrando tu rango", limits: [(Level, String)] = [], detail = ""
            if let bl = base(b), bl.isUsable {
                let z = bl.z(x) * Double(bad == 0 ? 1 : bad)
                let a = bad == 0 ? abs(z) : z
                level = a < 1.5 ? .green : (a < 2.5 ? .orange : .red)
                let lo = toUser(bl.center - 1.5 * bl.spread), hi = toUser(bl.center + 1.5 * bl.spread)
                let lo2 = toUser(bl.center - 2.5 * bl.spread), hi2 = toUser(bl.center + 2.5 * bl.spread)
                chip = level == .green ? "cerca de \(fmt(toUser(bl.center)))"
                    : ((bad >= 0 && x > bl.center) ? (level == .red ? "muy alta" : "alta") : (level == .red ? "muy baja" : "baja")) + " para ti"
                detail = "Tu \(title.lowercased()) de \(fmt(v)) \(unit) \(level == .green ? "está dentro de" : "está fuera de") tu rango típico de \(fmt(lo)) a \(fmt(hi)) \(unit)."
                switch bad {
                case 1: limits = [(.green, "Verde = \(fmt(hi)) \(unit) e inferior"), (.orange, "Naranja = \(fmt(hi)) a \(fmt(hi2)) \(unit)"), (.red, "Rojo = \(fmt(hi2)) \(unit) y superior")]
                case -1: limits = [(.green, "Verde = \(fmt(lo)) \(unit) y superior"), (.orange, "Naranja = \(fmt(lo2)) a \(fmt(lo)) \(unit)"), (.red, "Rojo = \(fmt(lo2)) \(unit) e inferior")]
                default: limits = [(.green, "Verde = \(fmt(lo)) a \(fmt(hi)) \(unit)"), (.orange, "Naranja = fuera, hasta \(fmt(lo2)) / \(fmt(hi2)) \(unit)"), (.red, "Rojo = más allá")]
                }
            }
            let when = d.day == model.currentDayKey ? "Anoche" : Fmt.dayTitle(d.day)
            out.append(Vital(id: id, icon: icon, title: title, value: fmt(v), unit: unit, level: level, chip: chip, when: when,
                             explanation: explanation, detail: detail, limits: limits))
        }
        add("resp", "lungs", "Frecuencia respiratoria", \.respRate, unit: "rpm", bad: 1, fmt: { Fmt.dec($0) }, base: { $0.resp },
            explanation: "Respiraciones por minuto mientras duermes. Es muy estable de una noche a otra: si sube, suele ser por enfermedad, alcohol o un entreno muy exigente.")
        add("spo2", "drop", "Oxígeno en sangre (SpO₂)", \.spo2, unit: "%", bad: -1, fmt: { Fmt.int($0) }, base: { $0.spo2 },
            explanation: "Cuánto oxígeno llevan los glóbulos rojos. Lectura experimental de la pulsera: úsala solo como tendencia.")
        add("rhr", "heart", "FC en reposo", \.rhr, unit: "lpm", bad: 1, fmt: { Fmt.int($0) }, base: { $0.rhr },
            explanation: "Las veces que late tu corazón por minuto en tu sueño más tranquilo. Más alta de lo habitual suele indicar entreno duro el día anterior, alcohol, poco sueño o que estás incubando algo.")
        add("hrv", "waveform.path.ecg", "VFC", \.hrv, unit: "ms", bad: -1, fmt: { Fmt.int($0) }, base: { $0.lnHRV }, log: true,
            explanation: "La variación del tiempo entre latidos. Alta = tu sistema nervioso está relajado y te recuperas bien; baja = fatiga física o mental, deshidratación, alcohol, estrés o enfermedad.")
        add("temp", "thermometer.medium", "Temperatura cutánea", \.skinTemp, unit: "°C", bad: 0, fmt: { Fmt.dec($0) }, base: { $0.temp },
            explanation: "La temperatura de la piel durante la noche. Cambia con el ambiente y la ropa de cama; una subida varias noches seguidas puede anunciar fiebre o, en mujeres, la fase lútea.")
        return out
    }

    private func card(_ v: Vital) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: v.icon).foregroundStyle(Theme.secondary)
                Caps(v.title, size: 10, color: Theme.secondary, weight: .semibold).lineLimit(2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(v.value).scaledFont(40, weight: .bold, design: .rounded).monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(v.unit).font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
            HStack(spacing: 5) {
                Image(systemName: v.level == .green || v.level == .none ? "checkmark" : "exclamationmark").font(.caption2.bold())
                Text(v.chip).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Self.color(v.level))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Self.color(v.level).opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            Text(v.when).font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
    }
}

/// What a vital means, where yours sits and the green / orange / red limits.
struct VitalSheet: View {
    let vital: VitalsGrid.Vital
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: vital.icon).font(.title2).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).foregroundStyle(.white) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Caps(vital.title, size: 14)
                    Caps(vital.chip, size: 12, color: VitalsGrid.color(vital.level))
                }
                Text(vital.explanation).font(.body).foregroundStyle(.white)
                if !vital.detail.isEmpty { Text(vital.detail).font(.body).foregroundStyle(.white) }
                if !vital.limits.isEmpty {
                    Text("Los rangos se calculan con tus datos de los últimos 30 días:").font(.subheadline).foregroundStyle(Theme.secondary)
                    ForEach(Array(vital.limits.enumerated()), id: \.offset) { _, l in
                        HStack(spacing: 8) {
                            Circle().fill(VitalsGrid.color(l.0)).frame(width: 8, height: 8)
                            Text(l.1).font(.subheadline).foregroundStyle(.white)
                        }
                    }
                }
                Text("Pulso no es un dispositivo médico. Consulta a un profesional antes de tomar decisiones de salud.")
                    .font(.caption).foregroundStyle(Theme.tertiary)
            }
            .padding(22)
        }
        .background(Theme.card.ignoresSafeArea())
    }
}

// MARK: - Heart-rate history

struct LiveHRHistoryCard: View {
    @EnvironmentObject var model: AppModel
    @State private var period: HRPeriod = .hour
    @State private var series: HRHistory.Series?

    var body: some View {
        PCard {
            CardHeader(title: "Historial de pulso")
            Picker("Periodo", selection: $period) {
                ForEach(HRPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if let s = series {
                if s.points.isEmpty {
                    Text("Sin datos en este periodo todavía.").font(.footnote).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    HRHistoryChart(series: s).frame(height: 180)
                    HStack {
                        Text("Media \(s.enoughData ? Fmt.int(s.average) : "–")")
                        Spacer()
                        Text("Mín \(s.enoughData ? s.min.map(String.init) ?? "–" : "–") · Máx \(s.enoughData ? s.max.map(String.init) ?? "–" : "–")")
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                }
            } else {
                PulseLoader(phase: .running(progress: nil), style: .compact).frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: period) {
            let every: UInt64 = period.seconds <= 7200 ? 15 : 120
            series = nil
            while !Task.isCancelled {
                let s = await model.hrHistory(period)
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.4)) { series = s }
                try? await Task.sleep(nanoseconds: every * 1_000_000_000)
            }
        }
    }
}

// MARK: - Compact actions

/// A small round tool button (icon + one word).
struct ToolChip<Destination: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(color)
                    .frame(width: 52, height: 52)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.hairline))
                Text(title).font(.caption2).foregroundStyle(.white).lineLimit(1)
            }
            .frame(width: 70)
        }
        .buttonStyle(.plain)
    }
}
