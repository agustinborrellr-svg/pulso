import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// One line of the Inicio grid: a large card, or one or two small tiles.
struct HomeWidgetLine: View {
    let items: [HomeWidget]
    let day: DaySummary

    var body: some View {
        if items.count == 1, items[0].size == .large {
            HomeWidgetView(widget: items[0], day: day)
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(items) { HomeWidgetView(widget: $0, day: day).frame(maxWidth: .infinity, maxHeight: .infinity) }
                if items.count == 1 { Color.clear.frame(maxWidth: .infinity) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HomeWidgetView: View {
    @EnvironmentObject var model: AppModel
    let widget: HomeWidget
    let day: DaySummary

    var body: some View {
        switch widget.kind {
        case .hero:
            PillarHero(day: day)
        case .sleep:
            NavigationLink { SleepDetailView() } label: { HomeSleepCard(day: day) }.buttonStyle(.plain)
        case .strainRecovery:
            StrainRecoveryWeekCard()
        case .plan:
            PlanSummaryCard()
        case .stress:
            if day.stressHourly.contains(where: { $0 != nil }) {
                NavigationLink { StressMonitorView() } label: { StressPreviewCard(day: day) }.buttonStyle(.plain)
            } else {
                PCard {
                    CardHeader(title: "Monitor de estrés")
                    let calibrated = model.days.filter { $0.source == "strap" && $0.calmHR != nil && $0.day < day.day }.count
                    Text(calibrated < Stress.minBaselineDays
                         ? "Calibrando: el estrés se compara con tu calma de varios días; empieza a medirse tras \(Stress.minBaselineDays) días con la pulsera (llevas \(calibrated))."
                         : "Sin lecturas este día: se mide en los ratos quieto y despierto, fuera de entrenos y paseos.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        case .vitals:
            NavigationLink { RecoveryDetailView() } label: { HomeVitalsCard(day: day, period: widget.period) }.buttonStyle(.plain)
        case .activity:
            NavigationLink { StrainDetailView() } label: { HomeActivityCard(day: day, widget: widget) }.buttonStyle(.plain)
        case .pulsoAge:
            NavigationLink { PulsoAgeDetailView() } label: { HomePulsoAgeCard(small: widget.size == .small) }.buttonStyle(.plain)
        case .journal:
            JournalCard(day: model.selectedDay)
        case .metric, .hrv, .respiration, .skinTemp, .spo2:
            if let m = widget.trendMetric {
                NavigationLink { TrendDetailView(metric: m) } label: {
                    if widget.kind == .metric {
                        if widget.size == .small {
                            HomeMetricTile(metric: m, day: day, period: widget.period)
                        } else {
                            DashboardRow(metric: m, day: day, period: widget.period)
                        }
                    } else {
                        HomeSparkCard(metric: m, day: day, widget: widget)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Comparison text shared by tiles

/// Value, arrow and caption for one metric, honest about the open cycle.
struct HomeComparison {
    let value: String
    let delta: Delta?
    let caption: String?

    @MainActor
    init(_ m: TrendMetric, day: DaySummary, period: Int, model: AppModel) {
        let v = m.value(day)
        value = m.format(v)
        if m.accumulatesDuringDay, let running = model.inProgressText(day) {
            delta = nil
            caption = running
            return
        }
        let u = model.usual(m, before: day, period: period)
        delta = v == nil ? nil : Delta(v, u, higherIsBetter: m.higherIsBetter)
        caption = u.map { "\(m.format($0)) · \(period) d" }
    }
}

/// Half-width metric tile.
struct HomeMetricTile: View {
    @EnvironmentObject var model: AppModel
    let metric: TrendMetric
    let day: DaySummary
    let period: Int

    var body: some View {
        let c = HomeComparison(metric, day: day, period: period, model: model)
        HomeTileFrame(icon: metric.icon, title: HomeLayout.title(metric)) {
            HStack(spacing: 5) {
                Text(c.value).scaledFont(24, weight: .bold, relativeTo: .title1).monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let d = c.delta { DeltaMark(delta: d) }
            }
            if let cap = c.caption {
                Text(cap).scaledFont(11, weight: .medium, relativeTo: .caption1).monospacedDigit().foregroundStyle(Theme.secondary).lineLimit(1)
            }
        }
    }
}

/// Shared chrome of the small tiles, so every half-width card lines up.
struct HomeTileFrame<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: icon).scaledFont(13, relativeTo: .caption1).foregroundStyle(Theme.secondary)
                Caps(title, size: 10.5, weight: .semibold).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Sleep

/// Last night at a glance: asleep vs the detected block, the stages and what shaped them.
struct HomeSleepCard: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary

    var body: some View {
        let session = model.sleep(for: day)
        let naps = model.daytimeSleeps(on: day.day).filter(\.isNap).count
        PCard {
            CardHeader(title: "Sueño", subtitle: "Noche que acaba el \(Fmt.shortDay(day.day).lowercased())", chevron: true)
            if day.sleepMinutes == nil {
                Text(model.isOpenCycle(day) && model.nightStatus != .ok
                     ? "Tu noche aún no está aquí. Toca para añadirla o revisar las siestas."
                     : "Sin sueño registrado en este ciclo. Toca para añadirlo a mano.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            } else {
                HStack(alignment: .top) {
                    big("Dormido", Fmt.hmm(day.sleepMinutes), Theme.sleep)
                    Spacer()
                    big("Bloque detectado", Fmt.hmm(TrendMetric.timeInBed.value(day)), .white)
                    Spacer()
                    big("Necesitabas", Fmt.hmm(day.sleepNeedMinutes), .white)
                }
                let stages: [(SleepStage, Double?)] = [(.deep, day.deepMinutes), (.rem, day.remMinutes), (.light, day.lightMinutes), (.awake, day.awakeMinutes)]
                if stages.contains(where: { ($0.1 ?? 0) > 0 }) {
                    StackedBar(parts: stages.map { (value: $0.1 ?? 0, color: Theme.stageColor($0.0)) }, height: 10)
                    HStack(spacing: 10) {
                        ForEach(stages, id: \.0) { s in
                            HStack(spacing: 4) {
                                Circle().fill(Theme.stageColor(s.0)).frame(width: 7, height: 7)
                                Text("\(Theme.stageName(s.0)) \(Fmt.hmm(s.1))").scaledFont(11, relativeTo: .caption1).monospacedDigit()
                                    .foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                            }
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                    stat("Eficiencia*", day.sleepEfficiency.map { "\(Int(($0 * 100).rounded())) %" } ?? "–")
                    stat("Latencia*", session.map { "\(Int($0.latencyMinutes.rounded())) min" } ?? "–")
                    stat("Despertares", day.disturbances.map(String.init) ?? "–")
                    stat("Regularidad", day.sleepConsistency.map { "\(Int($0)) %" } ?? "–")
                    stat("Deuda", Fmt.hmm(day.sleepDebtMinutes))
                    stat("Siestas", "\(naps)")
                }
                Text("* Estimadas: el bloque empieza cuando te quedaste quieto, no cuando te acostaste.")
                    .scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func big(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v).scaledFont(24, weight: .bold, relativeTo: .title1).monospacedDigit().foregroundStyle(c)
            Caps(k, size: 9.5, color: Theme.secondary, weight: .semibold)
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).scaledFont(15, weight: .semibold, relativeTo: .body).monospacedDigit().foregroundStyle(.white)
            Caps(k, size: 9, color: Theme.secondary, weight: .semibold)
        }
    }
}

// MARK: - Vitals, activity, Edad Pulso, mini charts

/// HRV, resting HR, breathing and skin temperature as a 2×2 group.
struct HomeVitalsCard: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary
    let period: Int

    var body: some View {
        PCard {
            CardHeader(title: "Constantes", subtitle: "Esta noche vs. tus \(period) días anteriores", chevron: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach([TrendMetric.hrv, .rhr, .respRate, .skinTemp]) { m in
                    let c = HomeComparison(m, day: day, period: period, model: model)
                    VStack(alignment: .leading, spacing: 4) {
                        Caps(short(m), size: 9.5, color: Theme.secondary, weight: .semibold)
                        HStack(spacing: 4) {
                            Text(c.value).scaledFont(20, weight: .bold, relativeTo: .body).monospacedDigit().foregroundStyle(.white)
                            Text(m.unit).font(.caption2).foregroundStyle(Theme.secondary)
                            if let d = c.delta { DeltaMark(delta: d) }
                        }
                        Text(c.caption ?? " ").scaledFont(11, relativeTo: .caption1).monospacedDigit().foregroundStyle(Theme.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func short(_ m: TrendMetric) -> String {
        switch m {
        case .hrv: return "VFC"
        case .rhr: return "FC reposo"
        case .respRate: return "Respiración"
        default: return "Temp. piel"
        }
    }
}

/// Steps and calories; while the cycle runs it says so instead of judging a half day.
struct HomeActivityCard: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary
    let widget: HomeWidget

    var body: some View {
        let steps = HomeComparison(.steps, day: day, period: widget.period, model: model)
        let kcal = HomeComparison(.calories, day: day, period: widget.period, model: model)
        if widget.size == .small {
            HomeTileFrame(icon: "shoeprints.fill", title: "Pasos") {
                HStack(spacing: 5) {
                    Text(steps.value).scaledFont(24, weight: .bold, relativeTo: .title1).monospacedDigit().foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let d = steps.delta { DeltaMark(delta: d) }
                }
                Text("\(kcal.value) kcal").scaledFont(11, weight: .medium, relativeTo: .caption1).monospacedDigit().foregroundStyle(Theme.secondary)
                if let cap = steps.caption {
                    Text(cap).scaledFont(11, relativeTo: .caption1).monospacedDigit().foregroundStyle(Theme.tertiary).lineLimit(1)
                }
            }
        } else {
            PCard {
                CardHeader(title: "Pasos y calorías", subtitle: model.inProgressText(day), chevron: true)
                HStack(alignment: .top) {
                    column("Pasos", steps)
                    Spacer()
                    column("Calorías", kcal)
                }
            }
        }
    }

    private func column(_ k: String, _ c: HomeComparison) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(c.value).scaledFont(26, weight: .bold, relativeTo: .title1).monospacedDigit().foregroundStyle(.white)
                if let d = c.delta { DeltaMark(delta: d) }
            }
            Caps(k, size: 10, color: Theme.secondary, weight: .semibold)
            if c.delta != nil, let cap = c.caption {
                Text(cap).scaledFont(11, relativeTo: .caption1).monospacedDigit().foregroundStyle(Theme.tertiary)
            }
        }
    }
}

struct HomePulsoAgeCard: View {
    @EnvironmentObject var model: AppModel
    let small: Bool

    var body: some View {
        let r = model.pulsoAge ?? PulsoAge.compute(days: model.days, profile: model.profile, today: model.currentDayKey)
        let diff = r.difference.map { abs($0) < 0.05 ? "Como tu edad real" : "\(Fmt.dec(abs($0))) años \($0 > 0 ? "mayor" : "menor")" }
        let color = r.difference.map { $0 > 0 ? Theme.worse : Theme.better } ?? Theme.secondary
        if small {
            HomeTileFrame(icon: "hourglass", title: "Edad Pulso") {
                Text(r.pulsoAge.map { Fmt.dec($0) } ?? "–").scaledFont(24, weight: .bold, relativeTo: .title1).monospacedDigit().foregroundStyle(.white)
                Text(diff ?? "Faltan datos").scaledFont(11, weight: .medium, relativeTo: .caption1).foregroundStyle(color).lineLimit(1)
            }
        } else {
            PCard {
                CardHeader(title: "Edad Pulso", subtitle: "Estimación · \(r.measured) de 7 hábitos medidos", chevron: true)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BigValue(value: r.pulsoAge.map { Fmt.dec($0) } ?? "–", unit: "años", size: 32)
                    Text(diff ?? "Faltan datos").font(.subheadline.weight(.semibold)).foregroundStyle(color)
                }
            }
        }
    }
}

struct PulsoAgeDetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        DetailScreen(title: "Edad Pulso") {
            AgeOrbHero(result: model.pulsoAge ?? PulsoAge.compute(days: model.days, profile: model.profile, today: model.currentDayKey))
            AgeTrendCard()
            Text("Estimación orientativa calculada en tu iPhone, no una medida biológica. El detalle de cada hábito está en Salud.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}

/// A vital with its last 7 or 30 nights drawn underneath.
struct HomeSparkCard: View {
    @EnvironmentObject var model: AppModel
    let metric: TrendMetric
    let day: DaySummary
    let widget: HomeWidget

    var body: some View {
        let c = HomeComparison(metric, day: day, period: widget.period, model: model)
        let pts = model.recentValues(metric, through: day, period: widget.period)
        let small = widget.size == .small
        let content = VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(c.value).font(.system(size: small ? 22 : 28, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(metric.unit).font(.caption2).foregroundStyle(Theme.secondary)
                if let d = c.delta { DeltaMark(delta: d) }
            }
            if pts.count >= 2 {
                spark(pts).frame(height: small ? 34 : 70)
            } else {
                Text("Pocas noches para dibujar").scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.tertiary)
            }
            if let cap = c.caption {
                Text("Media: \(cap)").scaledFont(11, relativeTo: .caption1).monospacedDigit().foregroundStyle(Theme.tertiary).lineLimit(1)
            }
        }
        if small {
            HomeTileFrame(icon: metric.icon, title: shortTitle) { content }
        } else {
            PCard {
                CardHeader(title: metric.title, subtitle: "Últimos \(widget.period) días", chevron: true)
                content
            }
        }
    }

    private var shortTitle: String {
        switch metric {
        case .hrv: return "VFC"
        case .respRate: return "Respiración"
        case .skinTemp: return "Temperatura"
        case .spo2: return "SpO₂ (exp.)"
        default: return metric.title
        }
    }

    private func spark(_ pts: [(day: String, value: Double)]) -> some View {
        let values = pts.map(\.value)
        return Chart {
            ForEach(pts, id: \.day) { p in
                LineMark(x: .value("Día", p.day), y: .value("Valor", p.value))
                    .foregroundStyle(Theme.hrv)
                    .interpolationMethod(.monotone)
            }
            if let last = pts.last {
                PointMark(x: .value("Día", last.day), y: .value("Valor", last.value)).foregroundStyle(.white).symbolSize(20)
            }
        }
        .chartXScale(domain: pts.map(\.day))
        .chartYScale(domain: metric.domain(values))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

// MARK: - Editor

/// Add, remove, reorder and size the cards of Inicio.
struct HomeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var raw: String
    @State private var items: [HomeWidget] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($items) { $w in
                        HStack(spacing: 10) {
                            Label(w.title, systemImage: w.icon).lineLimit(1)
                            Spacer(minLength: 4)
                            if w.allowsSmall || w.allowsPeriod {
                                Menu {
                                    if w.allowsSmall {
                                        Picker("Tamaño", selection: $w.size) {
                                            Text("Grande").tag(HomeWidget.Size.large)
                                            Text("Pequeño (media fila)").tag(HomeWidget.Size.small)
                                        }
                                    }
                                    if w.allowsPeriod {
                                        Picker("Comparar con", selection: $w.period) {
                                            Text("Últimos 7 días").tag(7)
                                            Text("Últimos 30 días").tag(30)
                                        }
                                    }
                                } label: {
                                    Text(optionsText(w)).font(.caption).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { items.remove(atOffsets: $0) }
                } header: {
                    Text("En Inicio")
                } footer: {
                    Text("Arrastra para ordenar, desliza para quitar y toca las opciones para cambiar tamaño o periodo. Los avisos (noche pendiente, siestas, alarma) salen solos cuando hace falta.")
                }
                let addable = HomeLayout.addable(to: items)
                let full = items.count >= HomeLayout.maxItems
                if !addable.isEmpty {
                    Section {
                        ForEach(addable) { w in
                            Button {
                                withAnimation { items.append(w) }
                            } label: {
                                HStack {
                                    Label(w.title, systemImage: w.icon)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(full ? Theme.secondary : Theme.green)
                                }
                            }
                            .foregroundStyle(.white)
                            .disabled(full)
                        }
                    } header: {
                        Text("Añadir")
                    } footer: {
                        if full { Text("Máximo \(HomeLayout.maxItems) tarjetas: quita alguna para añadir otra.") }
                    }
                }
                Section {
                    Button("Restablecer Inicio") { items = HomeLayout.defaults() }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Personalizar Inicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        raw = HomeLayout.encode(items)
                        dismiss()
                    }
                }
            }
            .onAppear { items = HomeLayout.decode(raw) }
        }
        .preferredColorScheme(.dark)
    }

    private func optionsText(_ w: HomeWidget) -> String {
        var parts: [String] = []
        if w.allowsSmall { parts.append(w.size == .small ? "Pequeño" : "Grande") }
        if w.allowsPeriod { parts.append("\(w.period) d") }
        return parts.joined(separator: " · ")
    }
}
