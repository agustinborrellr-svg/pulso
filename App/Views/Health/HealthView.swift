import SwiftUI
import PulsoStore
import PulsoAnalytics

/// "SALUD": Edad Pulso, pace of ageing, the vitals monitor, stress and each habit's effect in years.
struct HealthView: View {
    @EnvironmentObject var model: AppModel
    @State private var expanded: Set<String> = []

    var body: some View {
        let result = PulsoAge.compute(days: model.days, profile: model.profile, today: model.currentDayKey)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Caps("Salud", size: 15).frame(maxWidth: .infinity).padding(.top, 8)
                    AgeOrbHero(result: result)
                    paceCard(result)
                    AgeTrendCard()
                    PlanSummaryCard()
                    if let day = model.selected {
                        NavigationLink { RecoveryDetailView() } label: { HealthMonitorCard(day: day) }
                            .buttonStyle(.plain)
                        if day.stressHourly.contains(where: { $0 != nil }) {
                            NavigationLink { StressMonitorView() } label: { stressCard(day) }
                                .buttonStyle(.plain)
                        }
                    }
                    ForEach(["Sueño", "Esfuerzo", "Fitness"], id: \.self) { g in
                        groupSection(g, result.items.filter { $0.group == g })
                    }
                    NavigationLink { VO2MaxView() } label: {
                        ActionRow(icon: "lungs.fill", title: "Tu VO₂ máx y tu nivel cardiovascular")
                    }
                    .buttonStyle(.plain)
                    ExplainerCard(title: "¿Qué es la Edad Pulso?",
                                  text: "Tu edad real ajustada por los hábitos que más se asocian a vivir más y mejor: dormir lo suficiente y con horario regular, moverte a diario, acumular tiempo en zonas de esfuerzo y tener buen VO₂ máx y un pulso en reposo bajo.\n\nCada hábito suma o resta como mucho entre 0,8 y 1,5 años según dónde esté entre un valor deficiente y uno óptimo. El ritmo de envejecimiento compara tu último mes con tus últimos 6 meses: por debajo de 1x, tus hábitos recientes van mejor que tu norma.")
                    Text("La Edad Pulso es una estimación orientativa calculada en tu iPhone, no una medida biológica ni un consejo médico.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(PulsoBackground().overlay(alignment: .top) {
                RadialGradient(colors: [Color.orange.opacity(0.18), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
                    .ignoresSafeArea()
            })
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Pace

    private func paceCard(_ r: PulsoAge.Result) -> some View {
        PCard {
            HStack {
                Caps("Ritmo de envejecimiento", size: 12)
                Spacer()
                if let p = r.pace {
                    DeltaChip(text: p < 0.95 ? "más lento que tu norma" : (p > 1.05 ? "más rápido que tu norma" : "como tu norma"),
                              delta: Delta(p, 1, higherIsBetter: false, tolerance: 0.05))
                }
            }
            HStack {
                Label("Lento", systemImage: "tortoise").font(.subheadline)
                Spacer()
                Text(r.pace.map { "\(Fmt.dec($0))x" } ?? "–").font(.system(size: 24, weight: .bold)).monospacedDigit()
                Spacer()
                Label("Rápido", systemImage: "hare").font(.subheadline).labelStyle(TrailingIconLabelStyle())
            }
            .foregroundStyle(.white)
            PaceRuler(pace: r.pace)
                .frame(height: 46)
            HStack {
                Text("-1,0x"); Spacer(); Text("1,0x"); Spacer(); Text("3,0x")
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondary)
            if r.pace == nil {
                Text("Necesita al menos dos meses de datos para comparar tu último mes con tu norma.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func stressCard(_ d: DaySummary) -> some View {
        PCard {
            CardHeader(title: "Monitor de estrés", chevron: true)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Caps("Estrés alto de hoy", size: 10, color: Theme.secondary, weight: .semibold)
                    BigValue(value: Fmt.hmm(d.stressHighMinutes ?? 0), unit: "hrs", size: 30)
                }
                Spacer()
                StressLine(hourly: d.stressHourly, compact: true)
                    .chartYAxis(.hidden)
                    .chartXAxis(.hidden)
                    .frame(width: 170, height: 70)
            }
        }
    }

    // MARK: Habits

    private func groupSection(_ title: String, _ items: [PulsoAge.Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                legend("arrowtriangle.down.fill", "Prom. de\n30 días")
                legend("arrowtriangle.up", "Prom. de\n6 meses")
            }
            .padding(.top, 10)
            PCard(padding: 0, spacing: 0) {
                ForEach(items) { item in
                    habitRow(item)
                    if item.id != items.last?.id { Divider().overlay(Theme.hairline) }
                }
            }
        }
    }

    private func legend(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(.white)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func habitRow(_ item: PulsoAge.Item) -> some View {
        let open = expanded.contains(item.key)
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if open { expanded.remove(item.key) } else { expanded.insert(item.key) }
                }
            } label: {
                HStack {
                    Caps(item.label, size: 12).multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            HStack(alignment: .center, spacing: 12) {
                HabitRangeBar(item: item, text: format(item, item.recent))
                    .frame(height: 54)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(item.years.map { ($0 > 0 ? "+" : "") + Fmt.dec($0) } ?? "–")
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(item.years.map { $0 > 0.05 ? Theme.worse : ($0 < -0.05 ? Theme.better : Color.white) } ?? Theme.secondary)
                    Text("años").font(.caption).foregroundStyle(Theme.secondary)
                }
                .frame(width: 58, alignment: .trailing)
            }
            if open {
                Text(advice(item)).font(.subheadline).foregroundStyle(Color(white: 0.82)).fixedSize(horizontal: false, vertical: true)
                if let metric = trendMetric(item.key) {
                    NavigationLink { TrendDetailView(metric: metric) } label: {
                        HStack(spacing: 6) {
                            Caps("Ver tendencia", size: 11, color: Theme.link)
                            Image(systemName: "arrow.right").font(.caption.bold()).foregroundStyle(Theme.link)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private func format(_ item: PulsoAge.Item, _ v: Double?) -> String {
        guard let v else { return "sin datos" }
        switch item.unit {
        case "h": return "\(Fmt.hmm(v)) h"
        case "%": return "\(Int(v.rounded())) %"
        case "pasos": return "\(Fmt.thousands(v)) pasos"
        case "lpm": return "\(Int(v.rounded())) lpm"
        default: return "\(Fmt.dec(v)) \(item.unit)"
        }
    }

    private func trendMetric(_ key: String) -> TrendMetric? {
        switch key {
        case "sleepHours": return .sleepHours
        case "regularity": return .regularity
        case "zonesLight": return .zonesLight
        case "zonesHard": return .zonesHard
        case "steps": return .steps
        case "vo2max": return .vo2max
        case "rhr": return .rhr
        default: return nil
        }
    }

    private func advice(_ item: PulsoAge.Item) -> String {
        switch item.key {
        case "sleepHours": return "Dormir 7-9 horas de forma habitual es de lo que más pesa. Por debajo de 6 horas el riesgo sube de forma clara."
        case "regularity": return "Acostarte y levantarte a horas parecidas, también el fin de semana, mejora la calidad del sueño y la recuperación."
        case "zonesLight": return "Acumula unas 3-4 horas por semana en zonas 1-3: caminar rápido, bici suave, nadar tranquilo. Es la base aeróbica."
        case "zonesHard": return "Un rato cada semana en zonas 4-5 (series, subidas, deportes intensos) mejora el VO₂ máx. 30-60 minutos semanales bastan."
        case "steps": return "Más pasos al día se asocian a menos mortalidad, sobre todo hasta los 8.000-12.000."
        case "vo2max": return "Comparado con la media de tu edad y sexo. Sube con entrenos aeróbicos e intervalos; es lo que más predice salud a largo plazo."
        case "rhr": return "Un pulso en reposo más bajo suele indicar mejor forma. Baja con ejercicio aeróbico, buen sueño y menos alcohol."
        default: return ""
        }
    }
}

/// The orb with your Edad Pulso.
struct AgeOrbHero: View {
    let result: PulsoAge.Result

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ParticleOrb()
                    .frame(width: 250, height: 250)
                VStack(spacing: 4) {
                    Text(result.pulsoAge.map { Fmt.dec($0) } ?? "–")
                        .font(.system(size: 50, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Caps("Edad Pulso", size: 13)
                    if let d = result.difference {
                        Text(abs(d) < 0.05 ? "como tu edad real" : "\(Fmt.dec(abs(d))) años \(d > 0 ? "mayor" : "menor")")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(d > 0 ? Theme.worse : Theme.better)
                    } else {
                        Text("Faltan datos").font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            Text("Edad real: \(Int(result.age)) años · \(result.measured) de 7 hábitos medidos")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// Dark sphere with drifting specks and a warm rim.
struct ParticleOrb: View {
    private struct Speck {
        let angle: Double, radius: Double, size: Double, speed: Double, warm: Bool
    }

    private static let specks: [Speck] = {
        var g = SystemRandomNumberGenerator()
        return (0..<140).map { _ in
            let r = sqrt(Double.random(in: 0...1, using: &g))
            return Speck(angle: Double.random(in: 0..<(2 * .pi), using: &g), radius: r, size: Double.random(in: 0.8...2.6, using: &g),
                         speed: Double.random(in: 0.02...0.09, using: &g), warm: r > 0.62 && Bool.random(using: &g))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = min(size.width, size.height) / 2
                let wobble = { (a: Double) -> Double in 1 + 0.035 * sin(a * 3 + t * 0.6) + 0.025 * sin(a * 5 - t * 0.4) }
                var blob = Path()
                for i in 0...120 {
                    let a = Double(i) / 120 * 2 * .pi
                    let p = CGPoint(x: c.x + cos(a) * R * 0.92 * wobble(a), y: c.y + sin(a) * R * 0.92 * wobble(a))
                    if i == 0 { blob.move(to: p) } else { blob.addLine(to: p) }
                }
                blob.closeSubpath()
                gc.fill(blob, with: .radialGradient(Gradient(colors: [Color.black, Color(red: 0.05, green: 0.06, blue: 0.08),
                                                                      Color(red: 0.55, green: 0.33, blue: 0.12), Color(red: 0.95, green: 0.62, blue: 0.30)]),
                                                    center: CGPoint(x: c.x, y: c.y - R * 0.15), startRadius: 0, endRadius: R))
                gc.stroke(blob, with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.70, blue: 0.95).opacity(0.7), Color.orange.opacity(0.8)]),
                                                      startPoint: CGPoint(x: c.x, y: c.y - R), endPoint: CGPoint(x: c.x, y: c.y + R)), lineWidth: 1.5)
                for s in Self.specks {
                    let a = s.angle + t * s.speed
                    let r = s.radius * R * 0.86
                    let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r * 0.96)
                    let rect = CGRect(x: p.x - s.size / 2, y: p.y - s.size / 2, width: s.size, height: s.size)
                    let twinkle = 0.5 + 0.5 * sin(t * 2 + s.angle * 7)
                    gc.fill(Path(ellipseIn: rect), with: .color((s.warm ? Color.orange : Color.white).opacity(0.35 + 0.55 * twinkle)))
                }
            }
        }
        .shadow(color: Color.orange.opacity(0.25), radius: 30)
    }
}

/// Tick ruler from -1x to 3x with the pace marker.
struct PaceRuler: View {
    let pace: Double?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<60, id: \.self) { i in
                        Rectangle().fill(Color.white.opacity(i % 15 == 0 ? 0.6 : 0.28))
                            .frame(width: 1.5, height: i % 15 == 0 ? 30 : 22)
                            .frame(maxWidth: .infinity)
                    }
                }
                if let p = pace {
                    let x = (min(3, max(-1, p)) + 1) / 4 * w
                    Rectangle().fill(.white).frame(width: 3, height: 42).offset(x: x - 1.5)
                }
            }
            .frame(height: geo.size.height)
        }
    }
}

/// Gradient bar from poor (orange) to optimal (green) with ▼ recent and △ six-month markers.
struct HabitRangeBar: View {
    let item: PulsoAge.Item
    let text: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { i in
                        Rectangle().fill(color(Double(i) / 9)).frame(height: 4)
                    }
                }
                .offset(y: 26)
                if let p = item.position(item.recent) {
                    VStack(spacing: 2) {
                        Text(text).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(.white).fixedSize()
                        Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(.white)
                    }
                    .position(x: min(max(p * w, 40), w - 40), y: 12)
                }
                if let p = item.position(item.longTerm) {
                    Image(systemName: "arrowtriangle.up").font(.system(size: 9)).foregroundStyle(Theme.secondary)
                        .position(x: p * w, y: 40)
                }
            }
        }
    }

    private func color(_ t: Double) -> Color {
        t < 0.5 ? Color(red: 0.96, green: 0.65 - 0.25 * (0.5 - t), blue: 0.14 + 0.1 * t)
            : Color(red: 0.96 - 1.7 * (t - 0.5), green: 0.65 + 0.4 * (t - 0.5), blue: 0.14 + 0.9 * (t - 0.5))
    }
}

/// Five vitals against your normal range.
struct HealthMonitorCard: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary

    var body: some View {
        let b = Baselines.from(history: model.days.filter { $0.day < day.day })
        let checks: [(String, String, Bool?)] = [
            ("lungs", "FR", z(day.respRate, b.resp)),
            ("drop", "SPO₂", z(day.spo2, b.spo2)),
            ("heart", "FCR", z(day.rhr, b.rhr)),
            ("waveform.path.ecg", "VFC", z(day.hrv.flatMap { $0 > 0 ? log($0) : nil }, b.lnHRV)),
            ("thermometer.medium", "TEMP", z(day.skinTemp, b.temp)),
        ]
        let measured = checks.compactMap(\.2)
        PCard {
            CardHeader(title: "Monitor de salud", chevron: true)
            HStack {
                ForEach(Array(checks.enumerated()), id: \.offset) { i, c in
                    VStack(spacing: 8) {
                        Image(systemName: c.0).font(.title3).foregroundStyle(.white)
                        Caps(c.1, size: 10)
                        Image(systemName: c.2 == nil ? "minus" : (c.2! ? "checkmark" : "exclamationmark"))
                            .font(.caption.bold())
                            .foregroundStyle(c.2 == nil ? Theme.secondary : (c.2! ? Color.black : Color.black))
                            .frame(width: 22, height: 22)
                            .background(c.2 == nil ? Theme.cardHighlight : (c.2! ? Theme.better : Theme.worse), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .frame(maxWidth: .infinity)
                    if i < checks.count - 1 { Divider().overlay(Theme.hairline).frame(height: 70) }
                }
            }
            HStack(spacing: 10) {
                let ok = measured.filter { $0 }.count
                Image(systemName: ok == measured.count ? "checkmark.square.fill" : "exclamationmark.square.fill")
                    .foregroundStyle(ok == measured.count ? Theme.better : Theme.worse)
                Text(measured.isEmpty ? "Calibrando tus rangos normales" : "\(ok)/\(measured.count) métricas dentro de tu rango")
                    .font(.subheadline).foregroundStyle(.white)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// In range = within 2 spreads of your usual.
    private func z(_ v: Double?, _ base: Baseline?) -> Bool? {
        guard let v, let base, base.isUsable else { return nil }
        return abs(base.z(v)) < 2
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}
