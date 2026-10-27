import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// "El sueño de anoche": hours with the night's heart rate, selectable stages, need, regularity, efficiency and the week.
struct SleepDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var stage: SleepStage? = .light
    @State private var editing: SleepSession?
    @State private var adding = false

    var body: some View {
        DetailScreen(title: model.cycleTitle(model.selectedDay)) {
            if let day = model.selected, let s = model.sleep(for: day) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("El sueño de anoche").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                        Text("\(model.cycleTitle(day.day).capitalized) vs. los 30 días anteriores").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button { editing = s } label: {
                        HStack(spacing: 6) { Caps("Editar", size: 11); Image(systemName: "pencil") }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
                hoursCard(day, s)
                needCard(day)
                regularityCard(day)
                efficiencyCard(day, s)
                vitalsCard(s)
                naps
                SectionHeading(text: "Tendencias semanales")
                ForEach([TrendMetric.sleepPerformance, .hoursVsNeed, .restorativeHours, .regularity, .timeInBed, .efficiency, .sleepDebt], id: \.self) { m in
                    WeeklyTrendCard(metric: m)
                }
            } else {
                EmptyState(icon: "moon.zzz", title: "Sin sueño registrado",
                           message: "Duerme con la pulsera y sincroniza por la mañana. Si la detección falla, añádelo a mano.")
                naps
                Button("Añadir sueño manualmente") { adding = true }
                    .buttonStyle(SecondaryCapsuleStyle())
            }
        }
        .sheet(item: $editing) { SleepEditSheet(session: $0) }
        .sheet(isPresented: $adding) { SleepEditSheet(session: nil) }
    }

    private func usual(_ m: TrendMetric, _ d: DaySummary) -> Double? {
        TrendSeries.window(days: model.days.filter { $0.day < d.day }, value: { m.value($0) }, period: .month,
                           today: DayKey.shift(d.day, days: -1)).summary
    }

    // MARK: Hours + stages

    private func hoursCard(_ d: DaySummary, _ s: SleepSession) -> some View {
        let u = usual(.sleepHours, d)
        let total = max(1, s.inBedMinutes)
        let items: [(SleepStage, Double)] = [(.awake, s.minutesAwake), (.light, s.minutesLight), (.deep, s.minutesDeep), (.rem, s.minutesREM)]
        return PCard {
            CardHeader(title: "Horas de sueño")
            HStack(spacing: 6) {
                BigValue(value: Fmt.hmm(d.sleepMinutes), size: 30)
                DeltaMark(delta: Delta(d.sleepMinutes, u, higherIsBetter: true))
            }
            if let u { Text(Fmt.hmm(u)).font(.caption).foregroundStyle(Theme.secondary).padding(.top, -10) }
            NightHRChart(session: s, highlight: stage)
                .frame(height: 170)
            HStack {
                Caps("Rango típico", size: 11, color: Theme.secondary, weight: .semibold)
                Spacer()
                Caps("Duración", size: 11, color: Theme.secondary, weight: .semibold)
                Text(Fmt.hmm(s.inBedMinutes)).font(.headline.monospacedDigit()).foregroundStyle(.white)
            }
            ForEach(items, id: \.0) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { stage = stage == item.0 ? nil : item.0 }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().stroke(Color.white.opacity(0.7), lineWidth: 1.5).frame(width: 24, height: 24)
                                if stage == item.0 { Circle().fill(.white).frame(width: 12, height: 12) }
                            }
                            Caps(stageTitle(item.0), size: 12)
                            Text("\(Int((item.1 / total * 100).rounded())) %")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(stage == item.0 ? Theme.stageColor(item.0) : Theme.secondary)
                            Spacer()
                            Text(Fmt.hmm(item.1)).font(.headline.monospacedDigit()).foregroundStyle(.white)
                        }
                        StageStrip(session: s, stage: item.0, active: stage == item.0)
                            .frame(height: 16)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider().overlay(Theme.hairline)
            HStack {
                RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [Theme.stageColor(.deep), Theme.stageColor(.rem)],
                                                                      startPoint: .top, endPoint: .bottom))
                    .frame(width: 12, height: 12)
                Caps("Sueño reparador", size: 12)
                Spacer()
                Text(Fmt.hmm(s.restorativeMinutes)).font(.headline.monospacedDigit()).foregroundStyle(.white)
                DeltaMark(delta: Delta(s.restorativeMinutes, usual(.restorativeHours, d), higherIsBetter: true))
            }
        }
    }

    private func stageTitle(_ s: SleepStage) -> String {
        switch s {
        case .awake: return "Despierto"
        case .light: return "Ligero"
        case .deep: return "Sueño profundo (SWS)"
        case .rem: return "REM"
        }
    }

    // MARK: Need

    private func needCard(_ d: DaySummary) -> some View {
        let need = d.sleepNeedMinutes ?? model.profile.sleepNeedHours * 60
        let slept = d.sleepMinutes ?? 0
        let base = model.profile.sleepNeedHours * 60
        let debt = min(max(0, need - base), d.sleepDebtMinutes ?? 0)
        let strainPart = max(0, need - base - debt)
        let pct = need > 0 ? slept / need * 100 : 0
        let u = usual(.hoursVsNeed, d)
        return PCard {
            CardHeader(title: "Horas vs. lo necesario")
            HStack(spacing: 6) {
                BigValue(value: "\(Int(pct.rounded()))", unit: "%", size: 30)
                DeltaMark(delta: Delta(pct, u, higherIsBetter: true))
            }
            if let u { Text("\(Int(u.rounded())) %").font(.caption).foregroundStyle(Theme.secondary).padding(.top, -10) }
            GeometryReader { geo in
                let scale = geo.size.width / max(need, slept, 1)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Caps("Horas de sueño", size: 11, color: Theme.secondary, weight: .semibold)
                        Spacer()
                        Text(Fmt.hmm(slept)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(.white)
                    }
                    RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Theme.sleep.opacity(0.4), Theme.sleep], startPoint: .leading, endPoint: .trailing))
                        .frame(width: slept * scale, height: 14)
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(white: 0.35)).frame(width: base * scale)
                        Rectangle().fill(Theme.strain).frame(width: strainPart * scale)
                        Rectangle().fill(Color(white: 0.85)).frame(width: debt * scale)
                    }
                    .frame(height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    HStack {
                        Caps("Sueño necesario", size: 11, color: Theme.secondary, weight: .semibold)
                        Spacer()
                        Text(Fmt.hmm(need)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(.white)
                    }
                }
            }
            .frame(height: 100)
            VStack(spacing: 8) {
                needRow(Color(white: 0.35), "Tu base (perfil)", Fmt.hmm(base))
                needRow(Theme.strain, "Esfuerzo reciente", "+\(Fmt.hmm(strainPart))")
                needRow(Color(white: 0.85), "Deuda de sueño", "+\(Fmt.hmm(debt))")
            }
            .padding(12)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func needRow(_ c: Color, _ k: String, _ v: String) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12)
            Text(k).font(.subheadline).foregroundStyle(.white)
            Spacer()
            Text(v).font(.subheadline.bold().monospacedDigit()).foregroundStyle(.white)
        }
    }

    // MARK: Regularity

    private func regularityCard(_ d: DaySummary) -> some View {
        let nights = (0..<5).map { DayKey.shift(d.day, days: $0 - 4) }.compactMap { k -> (String, Double, Double)? in
            guard let x = model.day(k), let a = x.sleepStart, let b = x.sleepEnd else { return nil }
            return (k, clockHours(a), clockHours(b))
        }
        let u = usual(.regularity, d)
        return PCard {
            CardHeader(title: "Regularidad del sueño")
            HStack(spacing: 6) {
                BigValue(value: d.sleepConsistency.map { "\(Int($0))" } ?? "–", unit: "%", size: 30)
                DeltaMark(delta: Delta(d.sleepConsistency, u, higherIsBetter: true))
            }
            if nights.count >= 2 {
                let bed = nights.map(\.1).reduce(0, +) / Double(nights.count)
                let wake = nights.map(\.2).reduce(0, +) / Double(nights.count)
                Chart {
                    ForEach(nights, id: \.0) { n in
                        BarMark(x: .value("Noche", n.0), yStart: .value("Dormir", n.1), yEnd: .value("Despertar", n.2), width: .ratio(0.3))
                            .foregroundStyle(Color(white: 0.45))
                            .cornerRadius(2)
                    }
                    RuleMark(y: .value("Hora habitual de acostarte", bed)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.white.opacity(0.6))
                    RuleMark(y: .value("Hora habitual de despertar", wake)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.white.opacity(0.6))
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .chartXScale(domain: nights.map(\.0))
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel { Text(clockText(v.as(Double.self) ?? 0)).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    }
                }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel { Text(Fmt.weekdayAndDay(v.as(String.self) ?? "").0 + ".").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                    }
                }
                .frame(height: 180)
                Caps("- - - Tu hora habitual de acostarte y despertar", size: 9, color: Theme.secondary, weight: .semibold)
            }
        }
    }

    /// Hours since 18:00 the day before, so the night draws as one block.
    private func clockHours(_ ts: Int) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        var h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        if h < 18 { h += 24 }
        return h
    }

    private func clockText(_ h: Double) -> String {
        let v = Int(h.rounded()) % 24
        return String(format: "%02d:00", v)
    }

    // MARK: Efficiency

    private func efficiencyCard(_ d: DaySummary, _ s: SleepSession) -> some View {
        let u = usual(.efficiency, d)
        let eff = d.sleepEfficiency.map { $0 * 100 }
        return PCard {
            CardHeader(title: "Eficiencia del sueño")
            HStack(spacing: 6) {
                BigValue(value: eff.map { "\(Int($0.rounded()))" } ?? "–", unit: "%", size: 30)
                DeltaMark(delta: Delta(eff, u, higherIsBetter: true))
            }
            HStack {
                Caps("Dormido", size: 11, color: Theme.secondary, weight: .semibold)
                Spacer()
                Text(Fmt.hmm(s.asleepMinutes)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(.white)
            }
            AsleepStrip(session: s, awake: false).frame(height: 14)
            AsleepStrip(session: s, awake: true).frame(height: 14)
            HStack {
                Caps("Despierto", size: 11, color: Theme.secondary, weight: .semibold)
                Spacer()
                Text(Fmt.hmm(s.minutesAwake)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(.white)
            }
            Divider().overlay(Theme.hairline)
            HStack {
                RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.85)).frame(width: 12, height: 12)
                Caps("Episodios de despertar", size: 12)
                Spacer()
                Text("\(s.disturbances)").font(.headline.monospacedDigit()).foregroundStyle(.white)
            }
        }
    }

    // MARK: Vitals

    private func vitalsCard(_ s: SleepSession) -> some View {
        PCard(padding: 0, spacing: 0) {
            CardHeader(title: "Constantes de la noche").padding(16)
            vital("waveform.path.ecg", "VFC (RMSSD)", Fmt.int(s.hrv), "ms")
            vital("heart", "FC en reposo", Fmt.int(s.rhr), "lpm")
            vital("lungs", "Respiración", Fmt.dec(s.respRate), "rpm")
            vital("drop", "Oxígeno en sangre", Fmt.dec(s.spo2), "%")
            vital("thermometer.medium", "Temp. cutánea", Fmt.dec(s.skinTemp), "°C")
            vital("hourglass", "Latencia", Fmt.int(s.latencyMinutes), "min")
        }
    }

    private func vital(_ icon: String, _ k: String, _ v: String, _ unit: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.secondary).frame(width: 24)
            Caps(k, size: 12, weight: .semibold)
            Spacer()
            Text(v).font(.headline.monospacedDigit()).foregroundStyle(.white)
            Text(unit).font(.caption).foregroundStyle(Theme.secondary).frame(width: 30, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().overlay(Theme.hairline) }
    }

    @ViewBuilder
    private var naps: some View {
        let list = model.naps(on: model.selectedDay)
        if !list.isEmpty {
            PCard {
                CardHeader(title: "Siestas")
                ForEach(list) { n in
                    HStack {
                        Image(systemName: "powersleep").foregroundStyle(Theme.sleep)
                        Text("\(Fmt.time(n.start)) – \(Fmt.time(n.end))").foregroundStyle(.white)
                        Spacer()
                        Text(Fmt.hmm(n.asleepMinutes)).foregroundStyle(Theme.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

// MARK: - Night pieces

/// Heart rate through the night, tinted where the selected stage happens.
struct NightHRChart: View {
    let session: SleepSession
    let highlight: SleepStage?

    var body: some View {
        let pts = session.trend.compactMap { p -> (Date, Double)? in p.hr.map { (Date(timeIntervalSince1970: TimeInterval(p.ts)), $0) } }
        let segs = StageRuns.runs(session).filter { $0.stage == highlight }
        Chart {
            ForEach(segs) { seg in
                RectangleMark(xStart: .value("a", seg.start), xEnd: .value("b", seg.end))
                    .foregroundStyle(Theme.stageColor(seg.stage).opacity(0.22))
            }
            ForEach(pts, id: \.0) { p in
                LineMark(x: .value("Hora", p.0), y: .value("FC", p.1))
                    .foregroundStyle(Color(white: 0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.system(size: 9)).foregroundStyle(Theme.secondary) }
            }
        }
        .chartXAxis {
            AxisMarks(values: [Date(timeIntervalSince1970: TimeInterval(session.start)), Date(timeIntervalSince1970: TimeInterval(session.end))]) { v in
                AxisValueLabel { Text(Fmt.time(Int(v.as(Date.self)?.timeIntervalSince1970 ?? 0))).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white) }
            }
        }
    }
}

/// One stage across the night: filled where it happens, hatched elsewhere.
struct StageStrip: View {
    let session: SleepSession
    let stage: SleepStage
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            let n = max(1, session.stages.count)
            let w = geo.size.width / CGFloat(n)
            ZStack(alignment: .leading) {
                Hatch().fill(Color.white.opacity(0.10))
                ForEach(StageRuns.runs(session).filter { $0.stage == stage }) { r in
                    Rectangle()
                        .fill(active ? Theme.stageColor(stage) : Color(white: 0.55))
                        .frame(width: max(1.5, CGFloat(r.minutes) * w))
                        .offset(x: CGFloat(r.index) * w)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

/// Asleep (or awake) minutes as a strip.
struct AsleepStrip: View {
    let session: SleepSession
    let awake: Bool

    var body: some View {
        GeometryReader { geo in
            let n = max(1, session.stages.count)
            let w = geo.size.width / CGFloat(n)
            ZStack(alignment: .leading) {
                Hatch().fill(Color.white.opacity(0.10))
                ForEach(StageRuns.runs(session).filter { ($0.stage == .awake) == awake }) { r in
                    Rectangle().fill(awake ? Color(white: 0.85) : Theme.sleep)
                        .frame(width: max(1.5, CGFloat(r.minutes) * w))
                        .offset(x: CGFloat(r.index) * w)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

/// Diagonal hatching for the "rest of the night" background.
struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            p.addLine(to: CGPoint(x: x + rect.height + 1.5, y: rect.minY))
            p.addLine(to: CGPoint(x: x + 1.5, y: rect.maxY))
            p.closeSubpath()
            x += 5
        }
        return p
    }
}

/// Consecutive minutes of the same stage.
enum StageRuns {
    struct Run: Identifiable {
        let id: Int
        let index: Int
        let minutes: Int
        let stage: SleepStage
        let start: Date
        let end: Date
    }

    static func runs(_ s: SleepSession) -> [Run] {
        var out: [Run] = []
        var i = 0
        while i < s.stages.count {
            let st = s.stages[i]
            var j = i
            while j + 1 < s.stages.count && s.stages[j + 1] == st { j += 1 }
            out.append(Run(id: i, index: i, minutes: j - i + 1, stage: st,
                           start: Date(timeIntervalSince1970: TimeInterval(s.start + i * 60)),
                           end: Date(timeIntervalSince1970: TimeInterval(s.start + (j + 1) * 60))))
            i = j + 1
        }
        return out
    }
}
