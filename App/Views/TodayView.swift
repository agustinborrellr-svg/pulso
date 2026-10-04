import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

struct TodayView: View {
    @EnvironmentObject var model: AppModel
    @State private var showJournal = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DayHeader()
                    if let day = model.selected {
                        rings(day)
                        RecoveryBreakdown(day: day)
                        vitals(day)
                        StrainCard(day: day)
                        if let hourly = nonEmptyHourly(day) { StressCard(day: day, hourly: hourly) }
                        JournalCard(day: model.selectedDay)
                    } else if model.days.isEmpty {
                        emptyState
                    } else {
                        EmptyState(icon: "calendar.badge.exclamationmark", title: "Sin datos este día",
                                   message: "No hay datos de la pulsera para esta fecha.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .refreshable { await pullToRefresh() }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func pullToRefresh() async {
        model.syncNow()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    private func nonEmptyHourly(_ d: DaySummary) -> [Double?]? {
        d.stressHourly.contains { $0 != nil } ? d.stressHourly : nil
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            EmptyState(icon: "sensor.tag.radiowaves.forward",
                       title: model.strapState.isConnected ? "Recopilando datos" : "Conecta tu pulsera",
                       message: model.strapState.isConnected
                           ? "Tu primera recuperación aparece tras la primera noche. Las líneas base se calibran en 4 noches."
                           : "Ve a Más → Pulsera para emparejar tu WHOOP 5.0.")
            if model.rawSampleCount > 0 {
                Button {
                    model.recompute(fromDay: nil)
                } label: {
                    Label("Analizar datos descargados", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.strain)
            }
        }
    }

    private func rings(_ d: DaySummary) -> some View {
        Card {
            HStack(alignment: .top) {
                ScoreRing(progress: (d.recovery ?? 0) / 100, color: Theme.recoveryColor(d.recovery),
                          value: d.recovery.map { "\(Int($0))" } ?? (d.calibrating && d.sleepMinutes != nil ? "…" : "–"),
                          label: "Recuperación", unit: d.recovery == nil ? (d.calibrating ? "calibrando" : "") : "%")
                Spacer(minLength: 4)
                ScoreRing(progress: (d.strain ?? 0) / 21, color: Theme.strain,
                          value: Fmt.one(d.strain), label: "Esfuerzo")
                Spacer(minLength: 4)
                ScoreRing(progress: d.sleepPerformance ?? 0, color: Theme.sleep,
                          value: d.sleepPerformance.map { "\(Int(($0 * 100).rounded()))" } ?? "–",
                          label: "Sueño", unit: d.sleepPerformance == nil ? "" : "%")
            }
            .frame(maxWidth: .infinity)
            if let rec = d.recovery {
                Text(recoveryMessage(rec, strainTarget: strainTarget(rec)))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    private func strainTarget(_ recovery: Double) -> ClosedRange<Double> {
        switch recovery {
        case 67...: return 14...18
        case 34..<67: return 10...14
        default: return 4...10
        }
    }

    private func recoveryMessage(_ rec: Double, strainTarget: ClosedRange<Double>) -> String {
        let target = "Esfuerzo recomendado: \(Int(strainTarget.lowerBound))–\(Int(strainTarget.upperBound))."
        switch Recovery.band(rec) {
        case .green: return "Tu cuerpo está listo para rendir. " + target
        case .yellow: return "Recuperación moderada: mantén un esfuerzo razonable. " + target
        case .red: return "Prioriza descansar y dormir bien hoy. " + target
        }
    }

    private func vitals(_ d: DaySummary) -> some View {
        let b = model.baselines
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricTile(title: "VFC", value: Fmt.int(d.hrv), unit: "ms",
                       detail: delta(d.hrv, b.hrvCenter, unit: "ms", higherIsBetter: true),
                       detailColor: deltaColor(d.hrv, b.hrvCenter, higherIsBetter: true), icon: "waveform.path.ecg", tint: Theme.hrv)
            MetricTile(title: "FC reposo", value: Fmt.int(d.rhr), unit: "lpm",
                       detail: delta(d.rhr, b.rhr?.center, unit: "lpm", higherIsBetter: false),
                       detailColor: deltaColor(d.rhr, b.rhr?.center, higherIsBetter: false), icon: "heart.fill", tint: Theme.red)
            MetricTile(title: "Respiración", value: Fmt.one(d.respRate), unit: "rpm",
                       detail: delta(d.respRate, b.resp?.center, unit: "", higherIsBetter: false), icon: "lungs.fill", tint: Theme.hrv)
            MetricTile(title: "SpO₂", value: Fmt.one(d.spo2), unit: "%", detail: d.spo2 == nil ? "solo durante el sueño" : nil,
                       icon: "drop.fill", tint: Theme.red)
            MetricTile(title: "Temp. piel", value: Fmt.signed(d.skinTempDeviation), unit: "°C",
                       detail: d.skinTemp.map { String(format: "%.1f °C absoluta", $0) },
                       icon: "thermometer.medium", tint: Theme.yellow)
            MetricTile(title: "Calorías", value: Fmt.int(d.kcal), unit: "kcal",
                       detail: d.activeKcal.map { "\(Int($0)) activas" }, icon: "flame.fill", tint: Theme.stress)
            MetricTile(title: "Pasos (est.)", value: d.steps.map { String($0) } ?? "–", icon: "figure.walk", tint: Theme.green)
            MetricTile(title: "VO₂máx (est.)", value: Fmt.one(d.vo2max), unit: "ml/kg/min",
                       detail: d.vo2max.map { "Edad cardio ≈ \(Fitness.fitnessAge(vo2max: $0, sex: model.profile.sex)) años" },
                       icon: "bolt.heart.fill", tint: Theme.strain)
        }
    }

    private func delta(_ v: Double?, _ base: Double?, unit: String, higherIsBetter: Bool) -> String? {
        guard let v, let base else { return nil }
        let d = v - base
        return String(format: "%+.0f %@ vs tu media", d, unit)
    }

    private func deltaColor(_ v: Double?, _ base: Double?, higherIsBetter: Bool) -> Color {
        guard let v, let base, base != 0 else { return Theme.secondary }
        let rel = (v - base) / base * (higherIsBetter ? 1 : -1)
        if rel > 0.05 { return Theme.green }
        if rel < -0.05 { return Theme.red }
        return Theme.secondary
    }
}

/// "Why is my recovery X?" — every contributor with its signed impact.
struct RecoveryBreakdown: View {
    let day: DaySummary

    var body: some View {
        if !day.contributors.isEmpty {
            Card {
                SectionTitle(title: "Por qué", subtitle: day.calibrating ? "Calibrando tus líneas base (4 noches)" : "Comparado con tus últimas 2–4 semanas")
                ForEach(day.contributors) { c in
                    HStack {
                        Text(c.label).font(.subheadline).foregroundStyle(.white)
                        Spacer()
                        Text(valueText(c)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondary)
                        ImpactBar(impact: c.impact).frame(width: 70, height: 8)
                    }
                }
            }
        }
    }

    private func valueText(_ c: Contributor) -> String {
        let v = c.value.map { c.unit == "°C" ? String(format: "%+.2f", $0) : String(format: "%.0f", $0) } ?? "–"
        if let b = c.baseline, c.unit != "°C" {
            return "\(v) / \(String(format: "%.0f", b)) \(c.unit)"
        }
        return "\(v) \(c.unit)"
    }
}

struct ImpactBar: View {
    let impact: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / 2
            let len = min(w, CGFloat(abs(impact)) * w / 1.2)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1).offset(x: w)
                Capsule()
                    .fill(impact >= 0 ? Theme.green : Theme.red)
                    .frame(width: max(2, len))
                    .offset(x: impact >= 0 ? w : w - len)
            }
        }
    }
}

struct StrainCard: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary

    var body: some View {
        Card {
            HStack {
                SectionTitle(title: "Esfuerzo", subtitle: cycleText)
                Spacer()
                Text(Fmt.one(day.strain)).font(.title2.bold()).monospacedDigit().foregroundStyle(Theme.strain)
            }
            let zones = day.zoneMinutes
            if zones.reduce(0, +) > 0 {
                StackedBar(parts: zones.enumerated().map { (value: $0.element, color: Theme.zoneColor($0.offset + 1)) })
                HStack {
                    ForEach(0..<5, id: \.self) { i in
                        VStack(spacing: 2) {
                            Text("Z\(i + 1)").font(.caption2.bold()).foregroundStyle(Theme.zoneColor(i + 1))
                            Text(Fmt.hm(zones[i]).replacingOccurrences(of: "0h ", with: "")).font(.caption2).foregroundStyle(Theme.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            HStack {
                Label("FC media \(Fmt.int(day.avgHR))", systemImage: "heart")
                Spacer()
                Label("Máx \(Fmt.int(day.maxHR))", systemImage: "arrow.up.heart")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondary)

            let workouts = model.workouts(for: day)
            if !workouts.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
                ForEach(workouts) { w in
                    NavigationLink {
                        WorkoutDetailView(workout: w)
                    } label: {
                        WorkoutRow(workout: w)
                    }
                }
            }
        }
    }

    private var cycleText: String {
        guard let a = day.cycleStart else { return "" }
        return "Desde las \(Fmt.time(a))"
    }
}

struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: WorkoutDetailView.icon(workout.sport))
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Theme.strain.opacity(0.2), in: Circle())
                .foregroundStyle(Theme.strain)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.sport).font(.subheadline.bold()).foregroundStyle(.white)
                Text("\(Fmt.time(workout.start)) · \(Fmt.hm(workout.durationMinutes)) · \(Int(workout.kcal)) kcal\(workout.source == .auto ? " · auto" : "")")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text(Fmt.one(workout.strain)).font(.headline.monospacedDigit()).foregroundStyle(Theme.strain)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.tertiary)
        }
    }
}

struct StressCard: View {
    let day: DaySummary
    let hourly: [Double?]

    var body: some View {
        Card {
            HStack {
                SectionTitle(title: "Estrés", subtitle: "0–3 · en reposo y despierto, fuera de entrenos")
                Spacer()
                Text(Fmt.one(day.stressAvg)).font(.title2.bold()).monospacedDigit().foregroundStyle(Theme.stressColor(day.stressAvg))
            }
            Chart {
                ForEach(Array(hourly.enumerated()), id: \.offset) { item in
                    if let v = item.element {
                        BarMark(x: .value("Hora", item.offset), y: .value("Estrés", v))
                            .foregroundStyle(Theme.stressColor(v))
                            .cornerRadius(3)
                    }
                }
            }
            .chartYScale(domain: 0...3)
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisValueLabel { Text(v.as(Int.self).map { "\($0)h" } ?? "") }
                }
            }
            .frame(height: 110)
            if let high = day.stressHighMinutes, high > 0 {
                Text("\(Int(high)) min en estrés alto").font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}

struct JournalCard: View {
    @EnvironmentObject var model: AppModel
    let day: String
    @State private var expanded = false

    var body: some View {
        let entries = model.journal(for: day)
        Card {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack {
                    SectionTitle(title: "Diario", subtitle: entries.isEmpty ? "¿Qué hiciste hoy? Aprende qué te afecta" : "\(entries.count) registrados")
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(Theme.secondary)
                }
            }
            .buttonStyle(.plain)
            if expanded {
                FlowChips(day: day, entries: entries)
            }
        }
    }
}

struct FlowChips: View {
    @EnvironmentObject var model: AppModel
    let day: String
    let entries: [String: Double]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(JournalCatalog.items) { item in
                let on = (entries[item.key] ?? 0) > 0
                Button {
                    model.setJournal(day: day, key: item.key, on: !on)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                        Text(item.label).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .foregroundStyle(on ? Color.black : Color.white)
                    .background(on ? Theme.green : Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
