import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoIntelligence

// MARK: - Top of «Inteligencia»

/// Today in one glance: the three numbers and what to do.
struct AnalysisTodayCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let d = model.today ?? model.days.last {
            PCard {
                CardHeader(title: "Hoy, en resumen")
                HStack(spacing: 0) {
                    big(Fmt.int(d.recovery), "%", "Recuperación", Theme.recoveryColor(d.recovery))
                    big(Fmt.one(model.liveDayStrain ?? d.strain), "", "Esfuerzo", Theme.strain)
                    big(Fmt.hmm(d.sleepMinutes), "", "Sueño", Theme.sleep)
                }
                if d.recovery != nil {
                    let a = model.coachAdvice(for: d)
                    Text(a.headline).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("Esfuerzo recomendado hoy: \(Int(a.strainTarget.lowerBound))–\(Int(a.strainTarget.upperBound)).")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func big(_ v: String, _ unit: String, _ k: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(v).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(c)
                Text(unit).font(.caption).foregroundStyle(Theme.secondary)
            }
            Caps(k, size: 10, color: Theme.secondary, weight: .semibold)
        }
        .frame(maxWidth: .infinity)
    }
}

/// «Por qué este %»: the recovery as a waterfall from a normal day for you.
struct WaterfallCard: View {
    let day: DaySummary

    struct Bar: Identifiable {
        let label: String
        let from: Double
        let to: Double
        /// 0 normal day, 1 adds, 2 takes away, 3 result.
        let kind: Int
        var id: String { label }
    }

    static func bars(_ steps: [RecoveryWaterfall.Step]) -> [Bar] {
        var out = [Bar(label: "Día normal", from: 0, to: RecoveryWaterfall.neutral, kind: 0)]
        var prev = RecoveryWaterfall.neutral
        for s in steps {
            out.append(Bar(label: s.label, from: prev, to: s.total, kind: s.points >= 0 ? 1 : 2))
            prev = s.total
        }
        out.append(Bar(label: "Hoy", from: 0, to: prev, kind: 3))
        return out
    }

    var body: some View {
        let steps = RecoveryWaterfall.steps(day.contributors)
        if let score = day.recovery, !steps.isEmpty {
            PCard {
                CardHeader(title: "Por qué este \(Int(score)) %", subtitle: "Desde un día normal para ti (\(Int(RecoveryWaterfall.neutral)) %), factor a factor")
                let bars = Self.bars(steps)
                Chart(bars) { b in
                    BarMark(x: .value("factor", b.label), yStart: .value("de", b.from), yEnd: .value("a", b.to), width: .ratio(0.6))
                        .foregroundStyle(b.kind == 0 ? Color(white: 0.45) : b.kind == 1 ? Theme.better : b.kind == 2 ? Theme.worse : Theme.recoveryColor(score))
                        .cornerRadius(2)
                }
                .chartXScale(domain: bars.map { $0.label })
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel { Text(v.as(String.self) ?? "").font(.system(size: 9)).foregroundStyle(Theme.secondary) }
                    }
                }
                .frame(height: 180)
                ForEach(steps) { s in
                    HStack {
                        Text(s.label).font(.subheadline).foregroundStyle(.white)
                        Spacer()
                        Text((s.points >= 0 ? "+" : "−") + String(format: "%.0f", abs(s.points)))
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(s.points >= 0 ? Theme.better : Theme.worse)
                    }
                }
            }
        }
    }
}

/// Locked metrics and how close each one is.
struct UnlockCard: View {
    let report: IntelligenceReport

    var body: some View {
        let locked = report.sections.flatMap(\.metrics).filter { !$0.isAvailable }
        if !locked.isEmpty {
            let sorted = locked.sorted { progress($0) > progress($1) }
            let total = report.sections.flatMap(\.metrics).count
            PCard {
                CardHeader(title: "Por desbloquear", subtitle: "\(total - locked.count) de \(total) análisis listos. Lo que falta, según lo cerca que está:")
                ForEach(sorted.prefix(6)) { m in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(m.name).font(.subheadline).foregroundStyle(.white)
                            Spacer()
                            if let u = m.unlock {
                                Text("\(u.have)/\(u.need)").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                            }
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.08))
                                Capsule().fill(Theme.link).frame(width: max(4, g.size.width * progress(m)))
                            }
                        }
                        .frame(height: 6)
                        if case .insufficient(let need) = m.status {
                            Text("Falta: \(need)").font(.caption2).foregroundStyle(Theme.tertiary)
                        }
                    }
                }
            }
        }
    }

    private func progress(_ m: MetricResult) -> Double {
        guard let u = m.unlock else { return 0.02 }
        return Double(u.have) / Double(u.need)
    }
}

/// «Lo que más te afecta»: habits as diverging bars on next-day recovery.
struct ImpactCard: View {
    let items: [HabitImpact.Item]

    var body: some View {
        let top = Array(items.sorted { abs($0.recoveryDelta) > abs($1.recoveryDelta) }.prefix(8))
        if !top.isEmpty {
            let m = max(5, top.map { max(abs($0.interval.lowerBound), abs($0.interval.upperBound), abs($0.recoveryDelta)) }.max() ?? 5)
            PCard {
                CardHeader(title: "Lo que más te afecta", subtitle: "Recuperación del día siguiente, con vs sin (puntos)")
                ForEach(top) { h in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(h.label.replacingOccurrences(of: "whoop:", with: "")).font(.subheadline).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Text((h.recoveryDelta >= 0 ? "+" : "−") + String(format: "%.0f", abs(h.recoveryDelta)))
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(h.recoveryDelta >= 0 ? Theme.better : Theme.worse)
                        }
                        GeometryReader { g in
                            let mid = g.size.width / 2
                            let scale = mid / m
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Theme.hairline).frame(width: 1).offset(x: mid)
                                // Interval whisker.
                                Capsule().fill(Color.white.opacity(0.18))
                                    .frame(width: max(2, (h.interval.upperBound - h.interval.lowerBound) * scale), height: 2)
                                    .offset(x: mid + h.interval.lowerBound * scale, y: 0)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(h.recoveryDelta >= 0 ? Theme.better : Theme.worse)
                                    .frame(width: max(2, abs(h.recoveryDelta) * scale), height: 10)
                                    .offset(x: h.recoveryDelta >= 0 ? mid : mid + h.recoveryDelta * scale)
                            }
                        }
                        .frame(height: 12)
                    }
                }
                Text("La línea fina es el margen de error (90 %). Si cruza el centro, aún no está claro. Son asociaciones, no causas.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
        }
    }
}

/// Links to the explorer, calendar and monthly report.
struct AnalysisToolsLinks: View {
    var body: some View {
        VStack(spacing: 10) {
            link("Explorador de relaciones", "Cruza dos métricas: ¿duermes mejor cuando…?", "point.3.connected.trianglepath.dotted") { RelationExplorerView() }
            link("Calendario, rachas y récords", "Tus días en color y tus mejores marcas", "calendar") { CalendarRecordsView() }
            link("Informe mensual", "Resumen del mes en PDF para guardar o compartir", "doc.richtext") { MonthlyReportView() }
        }
    }

    private func link<D: View>(_ t: String, _ s: String, _ icon: String, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink { dest() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.link).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(s).font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Explorer

struct RelationExplorerView: View {
    @EnvironmentObject var model: AppModel
    @State private var x: TrendMetric = .sleepHours
    @State private var y: TrendMetric = .recovery
    @State private var nextDay = true
    @State private var range = 180

    var body: some View {
        let days = model.days.filter { range == 0 || $0.day >= DayKey.shift(model.currentDayKey, days: -range) }
        let pairs = Relation.pairs(days.map { x.value($0) }, days.map { y.value($0) }, lag: nextDay ? 1 : 0)
        let fit = Relation.fit(pairs)
        ScrollView {
            VStack(spacing: 14) {
                PCard {
                    Picker("Eje X", selection: $x) { ForEach(TrendMetric.allCases) { Text($0.title).tag($0) } }
                    Picker("Eje Y", selection: $y) { ForEach(TrendMetric.allCases) { Text($0.title).tag($0) } }
                    Toggle("Y del día siguiente", isOn: $nextDay)
                    Picker("Periodo", selection: $range) {
                        Text("3 meses").tag(90)
                        Text("6 meses").tag(180)
                        Text("Todo").tag(0)
                    }
                    .pickerStyle(.segmented)
                }
                .tint(.white)
                PCard {
                    if pairs.count >= 3 {
                        let xs = pairs.map(\.x)
                        Chart {
                            ForEach(Array(pairs.enumerated()), id: \.offset) { _, p in
                                PointMark(x: .value(x.title, p.x), y: .value(y.title, p.y))
                                    .symbolSize(22)
                                    .foregroundStyle(Theme.link.opacity(0.7))
                            }
                            if let f = fit, let lo = xs.min(), let hi = xs.max() {
                                LineMark(x: .value(x.title, lo), y: .value(y.title, f.slope * lo + f.intercept), series: .value("s", "fit"))
                                    .foregroundStyle(Theme.yellow)
                                LineMark(x: .value(x.title, hi), y: .value(y.title, f.slope * hi + f.intercept), series: .value("s", "fit"))
                                    .foregroundStyle(Theme.yellow)
                            }
                        }
                        .chartXScale(domain: .automatic(includesZero: false))
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxisLabel(x.title + (x.unit.isEmpty ? "" : " (\(x.unit))"))
                        .chartYAxisLabel(y.title + (nextDay ? " · día siguiente" : ""))
                        .frame(height: 280)
                        if let f = fit {
                            Text("\(f.strength) · r = \(String(format: "%.2f", f.r)) · \(f.n) días").font(.headline).foregroundStyle(.white)
                            Text(sentence(f)).font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                    } else {
                        Text("Aún no hay días con las dos métricas.").font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    Text("Que dos cosas vayan juntas no significa que una cause la otra.").font(.caption2).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(16)
        }
        .background(PulsoBackground())
        .pulsoTitle("Explorador")
    }

    private func sentence(_ f: Relation.Result) -> String {
        guard f.n >= 10, abs(f.r) >= 0.1 else { return "Con estos datos no se ve que una mueva a la otra." }
        let dir = f.slope > 0 ? "sube" : "baja"
        return "Por cada unidad más de \(x.title.lowercased()), \(y.title.lowercased())\(nextDay ? " del día siguiente" : "") \(dir) de media \(String(format: "%.1f", abs(f.slope))) \(y.unit)."
    }
}

// MARK: - Calendar, streaks and records

struct CalendarRecordsView: View {
    @EnvironmentObject var model: AppModel
    @State private var metric: TrendMetric = .recovery
    @State private var month = MonthlyReport.shiftMonth(String(DayKey.string(Date()).prefix(7)), 0)

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PCard {
                    Picker("Métrica", selection: $metric) {
                        Text("Recuperación").tag(TrendMetric.recovery)
                        Text("Esfuerzo").tag(TrendMetric.strain)
                        Text("Sueño").tag(TrendMetric.sleepPerformance)
                        Text("Estrés").tag(TrendMetric.stress)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Button { month = MonthlyReport.shiftMonth(month, -1) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Caps(monthTitle(month), size: 14)
                        Spacer()
                        Button { month = MonthlyReport.shiftMonth(month, 1) } label: { Image(systemName: "chevron.right") }
                            .disabled(month >= String(model.currentDayKey.prefix(7)))
                    }
                    .foregroundStyle(.white)
                    monthGrid
                }
                streaks
                records
            }
            .padding(16)
        }
        .background(PulsoBackground())
        .pulsoTitle("Calendario")
    }

    private func monthTitle(_ m: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: m) else { return m }
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d)
    }

    private var monthGrid: some View {
        let first = month + "-01"
        let cal = Calendar.current
        let firstDate = DayKey.date(first) ?? Date()
        let count = cal.range(of: .day, in: .month, for: firstDate)?.count ?? 30
        let offset = (cal.component(.weekday, from: firstDate) + 5) % 7 // Monday first
        let byDay = Dictionary(model.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return VStack(spacing: 6) {
            HStack {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { Text($0).font(.caption2).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<(offset + count), id: \.self) { i in
                    if i < offset {
                        Color.clear.frame(height: 40)
                    } else {
                        let key = String(format: "%@-%02d", month, i - offset + 1)
                        let v = byDay[key].flatMap { metric.value($0) }
                        VStack(spacing: 1) {
                            Text("\(i - offset + 1)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                            Text(v.map { metric == .stress ? String(format: "%.1f", $0) : "\(Int($0.rounded()))" } ?? "")
                                .font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(color(v).opacity(v == nil ? 0.06 : 0.85), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private func color(_ v: Double?) -> Color {
        guard let v else { return .white }
        switch metric {
        case .recovery: return Theme.recoveryColor(v)
        case .strain: return Theme.strain.opacity(0.35 + 0.65 * min(1, v / 21))
        case .stress: return v < 1 ? Theme.stressLow : v < 2 ? Theme.stressMid : Theme.stressHigh
        default: return v >= 85 ? Theme.green : v >= 70 ? Theme.yellow : Theme.red
        }
    }

    private var streaks: some View {
        let today = model.currentDayKey
        let green = Records.streak(model.days, today: today) { $0.recovery.map { $0 >= 67 } }
        let sleep7 = Records.streak(model.days, today: today) { $0.sleepMinutes.map { $0 >= 420 } }
        let worn = Records.streak(model.days, today: today) { $0.wornMinutes > 600 ? true : ($0.recovery != nil ? true : nil) }
        let active = Records.streak(model.days, today: today) { $0.strain.map { $0 >= 10 } }
        return PCard {
            CardHeader(title: "Rachas", subtitle: "Actual · mejor")
            streakRow("Días en verde (≥ 67 %)", green)
            streakRow("Noches de 7 h o más", sleep7)
            streakRow("Días activos (esfuerzo ≥ 10)", active)
            streakRow("Días con la pulsera", worn)
        }
    }

    private func streakRow(_ t: String, _ s: Records.Streak) -> some View {
        HStack {
            Text(t).font(.subheadline).foregroundStyle(.white)
            Spacer()
            Text("\(s.current)").font(.headline.monospacedDigit()).foregroundStyle(s.current > 0 && s.current == s.best ? Theme.green : .white)
            Text("· \(s.best)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondary)
        }
    }

    private var records: some View {
        PCard {
            CardHeader(title: "Récords personales")
            ForEach(Records.personalBests(model.days)) { r in
                HStack {
                    Text(r.title).font(.subheadline).foregroundStyle(.white)
                    Spacer()
                    Text(value(r)).font(.headline.monospacedDigit()).foregroundStyle(.white)
                    Text(Fmt.shortDay(r.day)).font(.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func value(_ r: Records.Record) -> String {
        switch r.title {
        case "Noche más larga": return Fmt.hmm(r.value)
        case "Mejor recuperación": return "\(Int(r.value)) %"
        case "Día más exigente": return String(format: "%.1f", r.value)
        case "Más pasos": return Fmt.thousands(r.value)
        case "VO₂ máx más alto": return String(format: "%.1f", r.value)
        default: return "\(Int(r.value.rounded()))"
        }
    }
}

// MARK: - Monthly report

struct MonthlyReportView: View {
    @EnvironmentObject var model: AppModel
    @State private var month = MonthlyReport.shiftMonth(String(DayKey.string(Date()).prefix(7)), 0)
    @State private var pdf: URL?

    var body: some View {
        let workouts = model.monthWorkouts(month)
        let report = MonthlyReport.build(month: month, days: model.days, workouts: workouts)
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button { month = MonthlyReport.shiftMonth(month, -1); pdf = nil } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Button { month = MonthlyReport.shiftMonth(month, 1); pdf = nil } label: { Image(systemName: "chevron.right") }
                        .disabled(month >= String(model.currentDayKey.prefix(7)))
                }
                .foregroundStyle(.white)
                MonthlyReportPage(report: report, light: false)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                if let pdf {
                    ShareLink(item: pdf) { Label("Compartir PDF", systemImage: "square.and.arrow.up") }
                        .buttonStyle(PrimaryCapsuleStyle())
                } else {
                    Button("Crear PDF") { pdf = Self.renderPDF(report) }
                        .buttonStyle(PrimaryCapsuleStyle())
                }
            }
            .padding(16)
        }
        .background(PulsoBackground())
        .pulsoTitle("Informe mensual")
    }

    @MainActor
    static func renderPDF(_ r: MonthlyReport.Report) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pulso-informe-\(r.month).pdf")
        let renderer = ImageRenderer(content: MonthlyReportPage(report: r, light: true).frame(width: 595))
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 595, height: max(842, size.height))
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(box)
            ctx.translateBy(x: 0, y: box.height - size.height)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

/// The report itself (on screen in dark, in the PDF on white).
struct MonthlyReportPage: View {
    let report: MonthlyReport.Report
    let light: Bool

    private var fg: Color { light ? .black : .white }
    private var sub: Color { light ? Color(white: 0.4) : Theme.secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PULSO · INFORME MENSUAL").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(sub)
                Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(fg)
                Text("\(report.daysWithData) días con datos").font(.caption).foregroundStyle(sub)
            }
            HStack(spacing: 10) {
                pill("\(report.greenDays)", "días en verde", .green)
                pill("\(report.redDays)", "días en rojo", .red)
                pill("\(report.workouts)", "entrenos", .blue)
                pill(Fmt.hm(report.workoutMinutes), "entrenando", .blue)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("Métrica").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Este mes").frame(width: 80, alignment: .trailing)
                    Text("vs anterior").frame(width: 90, alignment: .trailing)
                }
                .font(.caption.bold()).foregroundStyle(sub).padding(.vertical, 6)
                ForEach(report.lines) { l in
                    HStack {
                        Text(l.title).frame(maxWidth: .infinity, alignment: .leading)
                        Text(fmt(l.value, l.unit)).frame(width: 80, alignment: .trailing).monospacedDigit()
                        Text(delta(l)).frame(width: 90, alignment: .trailing).monospacedDigit().foregroundStyle(deltaColor(l))
                    }
                    .font(.subheadline).foregroundStyle(fg)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(sub.opacity(0.2)).frame(height: 0.5) }
                }
            }
            if !report.topSports.isEmpty {
                Text("Deportes: " + report.topSports.map { "\($0.name) (\($0.count))" }.joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(fg)
            }
            if let b = report.bestDay, let w = report.worstDay {
                Text("Mejor día: \(Fmt.shortDay(b)) · Peor día: \(Fmt.shortDay(w))").font(.subheadline).foregroundStyle(fg)
            }
            Text("Generado por Pulso con tus propios datos. No es un informe médico.").font(.caption2).foregroundStyle(sub)
        }
        .padding(24)
    }

    private var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: report.month) else { return report.month }
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d).capitalized
    }

    private func pill(_ v: String, _ k: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit()).foregroundStyle(fg)
            Text(k).font(.system(size: 9)).foregroundStyle(sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(c.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fmt(_ v: Double?, _ unit: String) -> String {
        guard let v else { return "–" }
        let s = abs(v) >= 1000 ? Fmt.thousands(v) : (abs(v) < 20 && unit != "%" ? String(format: "%.1f", v) : "\(Int(v.rounded()))")
        return unit.isEmpty || unit.hasPrefix("/") ? s : "\(s) \(unit)"
    }

    private func delta(_ l: MonthlyReport.Line) -> String {
        guard let d = l.delta else { return "–" }
        let a = abs(d)
        let s = a >= 100 ? Fmt.thousands(a) : (a < 10 ? String(format: "%.1f", a) : "\(Int(a.rounded()))")
        return (d >= 0 ? "+" : "−") + s
    }

    private func deltaColor(_ l: MonthlyReport.Line) -> Color {
        guard let d = l.delta, abs(d) > 1e-9 else { return sub }
        return (d > 0) == l.higherIsBetter ? .green : .orange
    }
}
