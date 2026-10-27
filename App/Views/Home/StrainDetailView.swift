import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// Strain of the selected day: dial, target, energy, heart-rate zones, activities and the week.
struct StrainDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var adding = false

    var body: some View {
        DetailScreen(title: model.cycleTitle(model.selectedDay)) {
            if let day = model.selected {
                hero(day)
                stats(day)
                zones(day)
                activities(day)
                SectionHeading(text: "Tendencias semanales")
                ForEach([TrendMetric.strain, .zonesLight, .zonesHard, .calories, .steps, .avgHR], id: \.self) { m in
                    WeeklyTrendCard(metric: m)
                }
                ExplainerCard(title: TrendMetric.strain.explainer.title, text: TrendMetric.strain.explainer.text)
            } else {
                EmptyState(icon: "flame", title: "Sin esfuerzo", message: "Todavía no hay datos de este día.")
            }
        }
        .sheet(isPresented: $adding) { AddActivitySheet() }
    }

    private func hero(_ d: DaySummary) -> some View {
        let advice = model.coachAdvice(for: d)
        return VStack(spacing: 14) {
            ZStack {
                Dial(progress: (d.strain ?? 0) / 21, color: Theme.strain, lineWidth: 22)
                // Target band on the dial.
                Circle()
                    .trim(from: advice.strainTarget.lowerBound / 21, to: min(1, advice.strainTarget.upperBound / 21))
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-17)
                VStack(spacing: 6) {
                    Text(Fmt.dec(d.strain)).font(.system(size: 64, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
                    Caps("Esfuerzo del día", size: 13)
                }
            }
            .frame(width: 250, height: 250)
            .padding(.vertical, 18)
            Text("Objetivo de hoy según tu recuperación: \(Int(advice.strainTarget.lowerBound))–\(Int(advice.strainTarget.upperBound))")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func stats(_ d: DaySummary) -> some View {
        VStack(spacing: 8) {
            MetricRow(icon: "flame", title: "Calorías", value: Fmt.thousands(d.kcal),
                      baseline: d.activeKcal.map { "\(Fmt.thousands($0)) activas" })
            MetricRow(icon: "heart.text.square", title: "FC promedio", value: Fmt.int(d.avgHR), baseline: "lpm")
            MetricRow(icon: "arrow.up.heart", title: "FC máxima", value: Fmt.int(d.maxHR), baseline: "lpm")
            MetricRow(icon: "shoeprints.fill", title: "Pasos", value: d.steps.map { Fmt.thousands(Double($0)) } ?? "–", baseline: "estimados")
        }
    }

    private func zones(_ d: DaySummary) -> some View {
        let z = d.zoneMinutes
        let total = z.reduce(0, +)
        return Group {
            if total > 0 {
                PCard {
                    CardHeader(title: "Zonas de frecuencia cardíaca", subtitle: "Tiempo de hoy en cada zona")
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { i in
                                if z[i] > 0 {
                                    Rectangle().fill(Theme.zoneColor(i + 1)).frame(width: max(3, (geo.size.width - 8) * z[i] / total))
                                }
                            }
                        }
                    }
                    .frame(height: 12)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                        ForEach(0..<5, id: \.self) { i in
                            HStack(spacing: 8) {
                                Rectangle().fill(Theme.zoneColor(i + 1)).frame(width: 9, height: 9)
                                Text(Fmt.hmm(z[i])).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                                Text("Zona \(i + 1)").font(.system(size: 15)).foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
        }
    }

    private func activities(_ d: DaySummary) -> some View {
        let list = model.workouts(for: d)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "Actividades")
            if list.isEmpty {
                Text("Hoy no hay actividades. Los entrenos se detectan solos; también puedes grabar uno en En vivo.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
            Button { adding = true } label: {
                ActionRow(icon: "plus", title: "Agregar actividad")
            }
            .buttonStyle(.plain)
            ForEach(list) { w in
                NavigationLink {
                    WorkoutDetailView(workout: w)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Dial(progress: w.strain / 21, color: Theme.strain, lineWidth: 4)
                            Text(Fmt.dec(w.strain)).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Caps(w.sport, size: 13)
                            Text("\(Fmt.time(w.start)) – \(Fmt.time(w.end)) · \(Fmt.hmm(w.durationMinutes)) · \(Int(w.kcal)) kcal")
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        if w.source == .auto || w.source == .whoop {
                            Caps(w.source == .auto ? "Auto" : "WHOOP", size: 9, color: Theme.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 4))
                        }
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// "MONITOR DE ESTRÉS": gauge, the day's curve and time per level against a usual day.
struct StressMonitorView: View {
    @EnvironmentObject var model: AppModel
    @State private var showInfo = false

    var body: some View {
        DetailScreen(title: "Monitor de estrés", subtitle: model.cycleTitle(model.selectedDay)) {
            if let day = model.selected {
                gauge(day)
                PCard {
                    StressLine(hourly: day.stressHourly, sleep: sleepHours(day))
                        .frame(height: 220)
                }
                levels(day)
                SectionHeading(text: "Tendencias")
                WeeklyTrendCard(metric: .stress)
                WeeklyTrendCard(metric: .stressHigh)
                ExplainerCard(title: TrendMetric.stress.explainer.title, text: TrendMetric.stress.explainer.text)
            }
        }
    }

    private func current(_ d: DaySummary) -> Double? {
        d.stressHourly.last { $0 != nil } ?? nil
    }

    private func gauge(_ d: DaySummary) -> some View {
        let v = current(d)
        return ZStack {
            // Top half, low (blue) on the left to high (orange) on the right.
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(AngularGradient(colors: [Theme.stressLow, Theme.stressMid, Theme.stressHigh], center: .center,
                                        startAngle: .degrees(180), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
            if let v {
                // Marker on the arc.
                Circle().fill(.white).frame(width: 18, height: 18)
                    .offset(x: -125)
                    .rotationEffect(.degrees(min(3, max(0, v)) / 3 * 180))
            }
            VStack(spacing: 4) {
                Caps(v == nil ? "Calculando" : Theme.stressLevel(v), size: 15, color: v == nil ? .white : Theme.stressColor(v))
                if let v { Text(Fmt.dec(v)).font(.system(size: 44, weight: .bold)).monospacedDigit().foregroundStyle(.white) }
            }
            .offset(y: -20)
            HStack {
                Text("0,0"); Spacer(); Text("3,0")
            }
            .font(.caption).foregroundStyle(Theme.secondary)
            .offset(y: 22)
        }
        .frame(width: 250, height: 250)
        .frame(maxWidth: .infinity)
        .padding(.bottom, -100)
    }

    private func sleepHours(_ d: DaySummary) -> ClosedRange<Int>? {
        guard let a = d.sleepStart, let b = d.sleepEnd else { return nil }
        let cal = Calendar.current
        let ha = cal.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(a)))
        let hb = cal.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(b)))
        return ha <= hb ? ha...hb : 0...hb
    }

    /// Hours of the day at each level, against the average of the same weekday in previous weeks.
    private func levels(_ d: DaySummary) -> some View {
        func split(_ h: [Double?]) -> [Double] {
            let v = h.compactMap { $0 }
            return [Double(v.filter { $0 < 1 }.count), Double(v.filter { $0 >= 1 && $0 < 2 }.count), Double(v.filter { $0 >= 2 }.count)]
        }
        let now = split(d.stressHourly)
        let usualDays = (1...4).compactMap { model.day(DayKey.shift(d.day, days: -7 * $0)) }.filter { $0.stressHourly.contains { $0 != nil } }
        let usual: [Double]? = usualDays.isEmpty ? nil : (0..<3).map { i in usualDays.map { split($0.stressHourly)[i] }.reduce(0, +) / Double(usualDays.count) }
        let colors = [Theme.stressLow, Theme.stressMid, Theme.stressHigh]
        let names = ["Bajo", "Medio", "Alto"]
        return PCard {
            HStack {
                Image(systemName: "gauge.with.dots.needle.33percent").foregroundStyle(Theme.secondary)
                Caps("Día total", size: 12)
            }
            Caps("\(Fmt.dayTitle(d.day)): horas por nivel\(usual == nil ? "" : " vs. un día habitual")", size: 10, color: Theme.secondary, weight: .semibold)
            levelBar(now, colors)
            if let usual { levelBar(usual, colors.map { $0.opacity(0.45) }).frame(height: 6) }
            HStack(alignment: .top) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(Int(now[i])) h").font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                        if let usual, usual[i] > 0 {
                            DeltaChip(text: "\(Int(abs(now[i] - usual[i]) / usual[i] * 100)) %",
                                      delta: Delta(now[i], usual[i], higherIsBetter: i == 0 ? true : false))
                        }
                        HStack(spacing: 4) {
                            Rectangle().fill(colors[i]).frame(width: 8, height: 8)
                            Caps(names[i], size: 10, color: Theme.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("El estrés medido a lo largo del día, cuando estás quieto y despierto, fuera de entrenos.")
                .font(.subheadline).foregroundStyle(Theme.secondary)
        }
    }

    private func levelBar(_ parts: [Double], _ colors: [Color]) -> some View {
        GeometryReader { geo in
            let total = max(parts.reduce(0, +), 0.0001)
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    if parts[i] > 0 {
                        Rectangle().fill(colors[i]).frame(width: max(3, (geo.size.width - 4) * parts[i] / total))
                    }
                }
            }
        }
        .frame(height: 10)
    }
}
