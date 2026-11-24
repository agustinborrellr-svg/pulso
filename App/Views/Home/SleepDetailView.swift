import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// «Anoche» (studio B-sueno 02): bed and wake times, hours with the night's heart rate, selectable stages with their
/// minute strips, restorative sleep, stage confidence, the night's metrics and the daytime sleeps.
struct SleepDetailView: View {
    @EnvironmentObject var model: AppModel
    /// The night to show (day key); nil = the selected day.
    var day: String?
    /// Name of the parent for the back pill (nil = chevron only).
    var back: String?
    @State private var stage: SleepStage? = .light
    @State private var scrub: Date?
    @State private var editing: SleepSession?
    @State private var adding = false

    private var summary: DaySummary? { day.flatMap { model.day($0) } ?? model.selected }

    var body: some View {
        let d = summary
        let detailed = d.flatMap { model.sleep(for: $0) }
        let s = detailed ?? d.flatMap { HistoryMerge.summarySleep($0) }
        DSScreen(title(d), subtitle: d.map { SFmt.nightRange($0.day) }, back: back) {
            if let detailed {
                Button { editing = detailed } label: {
                    Text("Editar").dsFont(16, .semibold).foregroundStyle(DS.t1)
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(DS.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(DS.hair, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        } content: {
            if let d, let s {
                clocks(s)
                hoursCard(d, s, detailed: detailed != nil)
                metrics(d, s, detailed: detailed != nil)
                naps
                RouteLink(.metric(.eficiencia)) {
                    HStack {
                        Text("Qué es el bloque detectado").dsFont(16).foregroundStyle(DS.t1)
                        Spacer()
                        DSChevron()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .dsCard(padding: 0)
                }
            } else {
                DSEmptyState(icon: "moon.zzz", title: "Sin sueño registrado",
                             message: "Duerme con la pulsera y sincroniza por la mañana. Si la detección falla, añádelo a mano.",
                             tint: DS.sueno, actionTitle: "Añadir sueño", action: { adding = true })
                naps
            }
        }
        .sheet(item: $editing) { SleepEditSheet(session: $0).environmentObject(model) }
        .sheet(isPresented: $adding) { SleepEditSheet(session: nil, forDay: summary?.day).environmentObject(model) }
    }

    private func title(_ d: DaySummary?) -> String {
        guard let d, d.day < model.currentDayKey else { return "Anoche" }
        return DSFmt.shortDate(d.day)
    }

    private func usual(_ m: TrendMetric, _ d: DaySummary) -> Double? {
        let from = DayKey.shift(d.day, days: -30)
        let v = model.days.filter { $0.day < d.day && $0.day >= from }.compactMap { m.value($0) }
        return v.count >= 3 ? v.reduce(0, +) / Double(v.count) : nil
    }

    // MARK: Bed and wake

    private func clocks(_ s: SleepSession) -> some View {
        HStack(spacing: 0) {
            clock("moon.fill", DS.sueno, "Te dormiste", s.start)
            Rectangle().fill(DS.sep).frame(width: 0.5, height: 50)
            clock("sun.max", DS.t2, "Te levantaste", s.end)
        }
        .padding(.vertical, 14)
        .dsCard(padding: 0)
    }

    private func clock(_ icon: String, _ color: Color, _ title: String, _ ts: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(color)
                Text(SFmt.clock(ts)).dsFont(28, .semibold).foregroundStyle(DS.t1)
            }
            Text(title).dsFont(14).foregroundStyle(DS.t2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Hours + stages

    private func hoursCard(_ d: DaySummary, _ s: SleepSession, detailed: Bool) -> some View {
        let slept = d.sleepMinutes ?? s.asleepMinutes
        let u = usual(.sleepHours, d)
        let items: [(SleepStage, Double)] = [(.light, s.minutesLight), (.deep, s.minutesDeep), (.rem, s.minutesREM), (.awake, s.minutesAwake)]
        let total = max(1, items.reduce(0) { $0 + $1.1 })
        return VStack(alignment: .leading, spacing: 12) {
            SuenoCardTitle(title: "Horas de sueño", note: u == nil ? nil : "vs. tus 30 días")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let t = scrub, let hr = NightHRChart.hr(s, at: t) {
                    HoyValue(value: "\(Int(hr.rounded()))", unit: "lpm", size: 34)
                    Text(DSFmt.clock(t)).dsFont(14).foregroundStyle(DS.t2)
                } else {
                    let p = DSFmt.durationParts(slept)
                    HoyValue(value: p.0, unit: p.1, size: 34)
                    if let u, abs(slept - u) >= 1 {
                        DSDelta(text: "\(DSFmt.duration(abs(slept - u))) \(slept > u ? "sobre" : "bajo") tu media", up: slept > u,
                                color: slept > u ? DSLevel.buena.ink : DSLevel.justa.ink)
                    }
                }
            }
            if detailed && s.trend.contains(where: { $0.hr != nil }) {
                NightHRChart(session: s, highlight: stage, selected: $scrub).frame(height: 170)
            }
            ForEach(items, id: \.0) { item in
                DSDivider()
                stageRow(item.0, item.1, total: total, s: s, detailed: detailed)
            }
            DSDivider()
            RouteLink(.metric(.reparador)) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(DS.stDeep).frame(width: 10, height: 10)
                    Text("Sueño reparador").dsFont(16).foregroundStyle(DS.t1)
                    Spacer()
                    Text(DSFmt.duration(s.restorativeMinutes)).dsFont(16, .semibold).foregroundStyle(DS.t1)
                    if let ur = usual(.restorativeHours, d), abs(s.restorativeMinutes - ur) >= 1 {
                        Image(systemName: s.restorativeMinutes > ur ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(s.restorativeMinutes > ur ? DSLevel.buena.ink : DSLevel.justa.ink)
                    }
                    DSChevron()
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            if let c = s.stageConfidence {
                DSDivider()
                StageConfidenceRow(confidence: c)
            }
            if !detailed {
                DSDivider()
                Text(d.source == "strap" ? "Esta noche solo tiene el resumen: no hay detalle minuto a minuto para dibujar las fases."
                     : "Noche importada: se ven los totales de cada fase, pero no su detalle minuto a minuto.")
                    .dsFont(13).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .dsCard(padding: 16)
    }

    private func stageRow(_ st: SleepStage, _ minutes: Double, total: Double, s: SleepSession, detailed: Bool) -> some View {
        let on = stage == st
        let color = st == .awake ? DS.t2 : DS.stage(st)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { stage = on ? nil : st }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().strokeBorder(on ? DS.t1 : DS.t3, lineWidth: 1.5).frame(width: 22, height: 22)
                            if on { Circle().fill(DS.t1).frame(width: 10, height: 10) }
                        }
                        Text(Theme.stageName(st)).dsFont(17, .semibold).foregroundStyle(DS.t1)
                        Text("\(Int((minutes / total * 100).rounded())) %").dsFont(15, .semibold).foregroundStyle(on ? color : DS.t3)
                        Spacer()
                        Text(DSFmt.duration(minutes)).dsFont(17, .semibold).foregroundStyle(DS.t1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                RouteLink(.metric(.fase(st))) { DSChevron().frame(width: 22, height: 30).contentShape(Rectangle()) }
                    .accessibilityLabel("Ver \(Theme.stageName(st))")
            }
            if detailed {
                SuenoStageStrip(session: s, filled: { $0 == st }, color: on ? color : DS.fill2, height: 16)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.fill)
                        Capsule().fill(on ? color : DS.fill2).frame(width: geo.size.width * min(1, minutes / total))
                    }
                }
                .frame(height: 8)
            }
        }
    }

    // MARK: Night metrics

    private func metrics(_ d: DaySummary, _ s: SleepSession, detailed: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.stack) {
            DSSectionHeader("Métricas de la noche")
            DSGroup {
                if let v = d.sleepPerformance {
                    metricRow("Calificación", "\(Int((v * 100).rounded()))", "", .calificacion)
                }
                if let v = TrendMetric.hoursVsNeed.value(d) { metricRow("Horas vs. lo necesario", "\(Int(v.rounded()))", "%", .necesidadSueno) }
                if let v = d.sleepConsistency { metricRow("Regularidad", "\(Int(v.rounded()))", "%", .regularidad) }
                if let v = d.sleepEfficiency ?? (s.inBedMinutes > 0 ? s.efficiency : nil) {
                    metricRow("Eficiencia", "\(Int((v * 100).rounded()))", "%", .eficiencia)
                }
                if detailed { metricRow("Latencia", "\(Int(s.latencyMinutes.rounded()))", "min", .latencia) }
                metricRow("Despertares", "\(d.disturbances ?? s.disturbances)", "", .eficiencia)
            }
        }
    }

    private func metricRow(_ label: String, _ value: String, _ unit: String, _ kind: MetricKind) -> some View {
        RouteLink(.metric(kind)) {
            HStack(spacing: 10) {
                Text(label).dsFont(16).foregroundStyle(DS.t1)
                Spacer()
                HoyValue(value: value, unit: unit, size: 17)
                DSChevron()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .dsRowInset(16)
    }

    @ViewBuilder
    private var naps: some View {
        let list = model.daytimeSleeps(on: summary?.day ?? model.selectedDay)
        if !list.isEmpty {
            DSSectionHeader("Sueño durante el día")
            VStack(spacing: 12) {
                ForEach(list) { n in
                    if n.id != list.first?.id { DSDivider() }
                    RouteLink(.sueno(.siestas)) { SuenoNapRow(nap: n) }
                }
            }
            .dsCard(padding: 16)
        }
    }
}

// MARK: - Night pieces

/// Heart rate through the night, with the selected stage shaded behind it.
struct NightHRChart: View {
    let session: SleepSession
    let highlight: SleepStage?
    var selected: Binding<Date?> = .constant(nil)

    /// Heart rate of the 5-minute point nearest to `t`.
    static func hr(_ s: SleepSession, at t: Date) -> Double? {
        let ts = Int(t.timeIntervalSince1970)
        return s.trend.filter { $0.hr != nil }.min { abs($0.ts - ts) < abs($1.ts - ts) }?.hr ?? nil
    }

    var body: some View {
        let pts = session.trend.compactMap { p -> (Date, Double)? in p.hr.map { (Date(timeIntervalSince1970: TimeInterval(p.ts)), $0) } }
        let segs = StageRuns.runs(session).filter { $0.stage == highlight }
        let shade = highlight.map { $0 == .awake ? DS.t2 : DS.stage($0) } ?? DS.sueno
        Chart {
            ForEach(segs) { seg in
                RectangleMark(xStart: .value("a", seg.start), xEnd: .value("b", seg.end))
                    .foregroundStyle(shade.opacity(0.28))
            }
            ForEach(pts, id: \.0) { p in
                LineMark(x: .value("Hora", p.0), y: .value("FC", p.1))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(DS.stLight)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            if let t = selected.wrappedValue, let hr = Self.hr(session, at: t) {
                RuleMark(x: .value("Hora", t))
                    .foregroundStyle(DS.t2.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Hora", t), y: .value("FC", hr))
                    .symbol { Circle().strokeBorder(DS.sueno, lineWidth: 2.5).background(Circle().fill(DS.card)).frame(width: 13, height: 13) }
            }
        }
        .chartScrub(selected)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(DS.sep)
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").dsFont(11, .medium).foregroundStyle(DS.t3) }
            }
        }
        .chartXAxis {
            AxisMarks(values: [Date(timeIntervalSince1970: TimeInterval(session.start)), Date(timeIntervalSince1970: TimeInterval(session.end))]) { v in
                AxisValueLabel {
                    Text(SFmt.clock(Int(v.as(Date.self)?.timeIntervalSince1970 ?? 0))).dsFont(12, .bold).foregroundStyle(DS.t1)
                }
            }
        }
        .accessibilityLabel("Pulso durante la noche")
    }
}

/// One stage across the night: filled where it happens, hatched elsewhere.
struct StageStrip: View {
    let session: SleepSession
    let stage: SleepStage
    let active: Bool

    var body: some View {
        SuenoStageStrip(session: session, filled: { $0 == stage }, color: active ? DS.stage(stage) : DS.fill2)
    }
}

/// Asleep (or awake) minutes as a strip.
struct AsleepStrip: View {
    let session: SleepSession
    let awake: Bool

    var body: some View {
        SuenoStageStrip(session: session, filled: { ($0 == .awake) == awake }, color: awake ? DS.t1 : DS.sueno, height: 14)
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
