import SwiftUI
import PulsoStore
import PulsoAnalytics

// MARK: - Calendar, streaks and records

/// Colour scale of the calendar for one metric.
private struct CalendarScale {
    struct Step: Identifiable {
        var id: String { label }
        let label: String
        let color: Color
        let contains: (Double) -> Bool
    }

    let metric: TrendMetric
    let steps: [Step]

    init(_ metric: TrendMetric) {
        self.metric = metric
        switch metric {
        case .recovery:
            steps = [Step(label: "67-99 %", color: Theme.green) { $0 >= 67 },
                     Step(label: "34-66 %", color: Theme.yellow) { $0 >= 34 && $0 < 67 },
                     Step(label: "0-33 %", color: Theme.red) { $0 < 34 }]
        case .strain:
            steps = [Step(label: "< 10", color: Theme.strain.opacity(0.35)) { $0 < 10 },
                     Step(label: "10-14", color: Theme.strain.opacity(0.6)) { $0 >= 10 && $0 < 14 },
                     Step(label: "14-18", color: Theme.strain.opacity(0.8)) { $0 >= 14 && $0 < 18 },
                     Step(label: "> 18", color: Theme.strain) { $0 >= 18 }]
        case .stress:
            steps = [Step(label: "Bajo 0-1", color: Theme.stressLow) { $0 < 1 },
                     Step(label: "Medio 1-2", color: Theme.stressMid) { $0 >= 1 && $0 < 2 },
                     Step(label: "Alto 2-3", color: Theme.stressHigh) { $0 >= 2 }]
        default:
            steps = [Step(label: "≥ 85 %", color: Theme.sleep) { $0 >= 85 },
                     Step(label: "70-84 %", color: Theme.sleep.opacity(0.62)) { $0 >= 70 && $0 < 85 },
                     Step(label: "< 70 %", color: Theme.sleep.opacity(0.32)) { $0 < 70 }]
        }
    }

    func color(_ v: Double) -> Color { steps.first { $0.contains(v) }?.color ?? Theme.secondary }

    /// Solid bright fills read better with dark digits; the translucent blues with light ones.

    /// Words for the lowest/highest day of the month.
    var extremes: (high: String, low: String) {
        switch metric {
        case .stress: return ("Más estrés", "Menos estrés")
        case .strain: return ("Más exigente", "Más suave")
        default: return ("Mejor", "Peor")
        }
    }
}

struct CalendarRecordsView: View {
    @EnvironmentObject var model: AppModel
    @State private var metric: TrendMetric = .recovery
    @State private var month = String(DayKey.string(Date()).prefix(7))
    @State private var forward = true
    @State private var picked: String?
    @State private var open: DayDestination?

    private enum DayDestination: Hashable, Identifiable {
        case recovery, sleep, strain
        var id: Self { self }
    }

    private static let metrics: [(TrendMetric, String)] = [(.recovery, "Recup."), (.strain, "Esfuerzo"), (.sleepPerformance, "Sueño"), (.stress, "Estrés")]

    private var byDay: [String: DaySummary] {
        Dictionary(model.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var currentMonth: String { String(model.currentDayKey.prefix(7)) }
    private var firstMonth: String? { model.days.map(\.day).min().map { String($0.prefix(7)) } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                PCard {
                    Picker("Métrica", selection: $metric.animation(.easeInOut(duration: 0.3))) {
                        ForEach(Self.metrics, id: \.0) { m, name in Text(name).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    monthHeader
                    calendar
                    legend
                }
                if let picked { dayDetail(picked).transition(.opacity.combined(with: .move(edge: .top))) }
                monthStats
                streaks
                records
            }
            .padding(16)
            .animation(.easeInOut(duration: 0.25), value: picked)
        }
        .background(PulsoBackground())
        .pulsoTitle("Calendario")
        .navigationDestination(item: $open) { d in
            switch d {
            case .recovery: RecoveryDetailView()
            case .sleep: SleepDetailView()
            case .strain: StrainDetailView()
            }
        }
    }

    // MARK: Month

    private func monthTitle(_ m: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: m) else { return m }
        f.dateFormat = "LLLL yyyy"
        return f.string(from: d)
    }

    private var canGoBack: Bool { firstMonth.map { month > $0 } ?? false }
    private var canGoForward: Bool { month < currentMonth }

    private func go(_ by: Int) {
        guard by < 0 ? canGoBack : canGoForward else { return }
        forward = by > 0
        withAnimation(.easeInOut(duration: 0.3)) {
            picked = nil
            month = MonthlyReport.shiftMonth(month, by)
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { go(-1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(!canGoBack)
            .opacity(canGoBack ? 1 : 0.3)
            .accessibilityLabel("Mes anterior")
            Spacer()
            Caps(monthTitle(month), size: 14)
                .id(month)
                .transition(.opacity)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { go(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
            }
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1 : 0.3)
            .accessibilityLabel("Mes siguiente")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var calendar: some View {
        let layout = CalendarMonth.layout(month)
        let keys = CalendarMonth.dayKeys(month)
        let scale = CalendarScale(metric)
        let data = byDay
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(["L", "M", "X", "J", "V", "S", "D"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.caption2.weight(.semibold)).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<(layout.leading + keys.count), id: \.self) { i in
                    if i < layout.leading {
                        Color.clear.frame(minHeight: 44).accessibilityHidden(true)
                    } else {
                        dayCell(keys[i - layout.leading], data: data, scale: scale)
                    }
                }
            }
            .id(month)
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { g in
                    guard abs(g.translation.width) > abs(g.translation.height), abs(g.translation.width) > 50 else { return }
                    go(g.translation.width < 0 ? 1 : -1)
                }
        )
        .accessibilityAction(named: "Mes anterior") { go(-1) }
        .accessibilityAction(named: "Mes siguiente") { go(1) }
    }

    private func dayCell(_ key: String, data: [String: DaySummary], scale: CalendarScale) -> some View {
        let d = data[key]
        let v = d.flatMap { metric.value($0) }
        let imported = d.map { $0.source != "strap" } ?? false
        let future = key > model.currentDayKey
        let isToday = key == model.currentDayKey
        let selected = picked == key
        let number = Int(key.suffix(2)) ?? 0
        return Button {
            guard !future else { return }
            withAnimation(.easeInOut(duration: 0.25)) { picked = selected ? nil : key }
        } label: {
            ZStack(alignment: .topTrailing) {
                // Tinted fill + full-colour edge: the level reads at a glance without a wall of neon.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(v.map { scale.color($0).opacity(0.26) } ?? Color.clear)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(v.map { scale.color($0).opacity(0.9) } ?? Color.white.opacity(future ? 0.04 : 0.12),
                                  style: StrokeStyle(lineWidth: v == nil ? 1 : 1.5, dash: v == nil ? [3, 3] : []))
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white, lineWidth: 2)
                }
                Text("\(number)")
                    .font(.caption.weight(isToday ? .heavy : .medium))
                    .monospacedDigit()
                    .foregroundStyle(v == nil ? (future ? Theme.tertiary.opacity(0.5) : Theme.tertiary) : Color.white)
                    .underline(isToday)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if imported && v != nil {
                    Circle().fill(Color.white.opacity(0.6)).frame(width: 5, height: 5).padding(5)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(Fmt.dayTitle(key) + (isToday ? ", hoy" : ""))
        .accessibilityValue(future ? "futuro" : (v.map { "\(metric.title): \(metric.spoken($0))" + (imported ? ", importado" : "") } ?? "sin datos"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var legend: some View {
        let scale = CalendarScale(metric)
        return VStack(alignment: .leading, spacing: 8) {
            Text(metric.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            FlowLayout(spacing: 10) {
                ForEach(scale.steps) { s in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).fill(s.color.opacity(0.26)).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(s.color, lineWidth: 1.5)).frame(width: 12, height: 12)
                        Text(s.label).font(.caption2).foregroundStyle(Theme.secondary)
                    }
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: 12, height: 12)
                    Text("Sin datos").font(.caption2).foregroundStyle(Theme.secondary)
                }
                HStack(spacing: 5) {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.secondary).frame(width: 12, height: 12)
                        Circle().fill(Color.black.opacity(0.5)).frame(width: 4, height: 4).padding(1.5)
                    }
                    Text("Importado").font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Day

    private func dayDetail(_ key: String) -> some View {
        let d = byDay[key]
        let rows: [(String, String)] = d.map { d in
            [("Recuperación", TrendMetric.recovery.value(d).map { "\(Int($0.rounded())) %" }),
             ("VFC", d.hrv.map { "\(Int($0.rounded())) ms" }),
             ("FC en reposo", d.rhr.map { "\(Int($0.rounded())) lpm" }),
             ("Sueño", d.sleepMinutes.map { "\(Fmt.hmm($0)) h" }),
             ("Calificación del sueño", TrendMetric.sleepPerformance.value(d).map { "\(Int($0.rounded())) %" }),
             ("Esfuerzo", d.strain.map { Fmt.dec($0) }),
             ("Estrés", d.stressAvg.map { "\(Fmt.dec($0)) de 3" })]
                .compactMap { t, v in v.map { (t, $0) } }
        } ?? []
        return PCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt.dayTitle(key)).font(.headline).foregroundStyle(.white)
                    if let d {
                        Label(d.source == "strap" ? "Medido con la pulsera" : "Importado", systemImage: d.source == "strap" ? "sensor.tag.radiowaves.forward" : "square.and.arrow.down")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                Button {
                    withAnimation { picked = nil }
                } label: {
                    Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, -12)
                .padding(.trailing, -12)
                .accessibilityLabel("Cerrar")
            }
            if rows.isEmpty {
                Text("Sin datos este día.").font(.subheadline).foregroundStyle(Theme.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                    ForEach(rows, id: \.0) { t, v in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t).font(.caption).foregroundStyle(Theme.secondary)
                            Text(v).font(.headline).monospacedDigit().foregroundStyle(.white)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                HStack(spacing: 8) {
                    openButton("Recuperación", .recovery, key)
                    openButton("Sueño", .sleep, key)
                    openButton("Esfuerzo", .strain, key)
                }
            }
        }
    }

    private func openButton(_ title: String, _ dest: DayDestination, _ key: String) -> some View {
        Button {
            if let from = DayKey.date(model.selectedDay), let to = DayKey.date(key),
               let n = Calendar.current.dateComponents([.day], from: from, to: to).day {
                if n != 0 { model.shiftSelectedDay(n) }
                open = dest
            }
        } label: {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre el detalle de ese día")
    }

    // MARK: Month stats

    private var monthStats: some View {
        let s = CalendarMonth.summary(month: month, days: model.days, today: model.currentDayKey, value: { metric.value($0) })
        let scale = CalendarScale(metric)
        let names = scale.extremes
        return PCard {
            CardHeader(title: "Resumen del mes", subtitle: metric.title)
            if s.daysWithData == 0 {
                Text(s.elapsedDays == 0 ? "Este mes aún no ha empezado." : "Sin datos de \(metric.title.lowercased()) este mes.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    stat("Media", metric.spoken(s.average), nil)
                    if let hi = s.highest, s.daysWithData > 1 { stat(names.high, metric.spoken(hi.value), hi.day) }
                    if let lo = s.lowest, s.daysWithData > 1 { stat(names.low, metric.spoken(lo.value), lo.day) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        let total = max(1, s.elapsedDays)
                        HStack(spacing: 2) {
                            if s.measuredDays > 0 {
                                Rectangle().fill(Color.white.opacity(0.8)).frame(width: geo.size.width * CGFloat(s.measuredDays) / CGFloat(total))
                            }
                            if s.importedDays > 0 {
                                Rectangle().fill(Color.white.opacity(0.4)).frame(width: geo.size.width * CGFloat(s.importedDays) / CGFloat(total))
                            }
                            Spacer(minLength: 0)
                        }
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .frame(height: 6)
                    .accessibilityHidden(true)
                    Text(coverage(s)).font(.caption).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: month)
    }

    private func coverage(_ s: CalendarMonth.Summary) -> String {
        var t = "\(s.daysWithData) de \(s.elapsedDays) días con datos"
        if s.importedDays > 0 { t += " (\(s.measuredDays) medidos, \(s.importedDays) importados)" }
        if s.daysWithoutData > 0 { t += " · \(s.daysWithoutData) sin datos" }
        return t
    }

    private func stat(_ title: String, _ value: String, _ day: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(.white).minimumScaleFactor(0.8)
            if let day {
                Button {
                    withAnimation { picked = day }
                } label: {
                    Text(Fmt.shortDay(day).lowercased()).font(.caption2).foregroundStyle(Theme.link)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ver \(Fmt.dayTitle(day))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Streaks

    private var streaks: some View {
        let today = model.currentDayKey
        let rows: [(String, String, Records.Streak)] = [
            ("Días con la pulsera", "sensor.tag.radiowaves.forward", Records.streak(model.days, today: today, rule: Records.wornWithStrap)),
            ("Días en verde (≥ 67 %)", "bolt.heart", Records.streak(model.days, today: today) { $0.recovery.map { $0 >= 67 } }),
            ("Noches de 7 h o más", "moon.zzz", Records.streak(model.days, today: today) { $0.sleepMinutes.map { $0 >= 420 } }),
            ("Días activos (esfuerzo ≥ 10)", "flame", Records.streak(model.days, today: today) { $0.strain.map { $0 >= 10 } }),
        ]
        return PCard {
            CardHeader(title: "Rachas", subtitle: "Días seguidos cumpliendo cada objetivo")
            ForEach(rows, id: \.0) { t, icon, s in
                streakRow(t, icon, s)
            }
            Text("Un día sin datos corta la racha; hoy no la corta mientras no tenga datos. Los días importados no cuentan como días con la pulsera.")
                .font(.caption2).foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func streakRow(_ title: String, _ icon: String, _ s: Records.Streak) -> some View {
        let next = Records.nextMilestone(after: s.current)
        let atBest = s.current > 0 && s.current == s.best
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(Theme.secondary).frame(width: 22)
                Text(title).font(.subheadline).foregroundStyle(.white)
                Spacer(minLength: 8)
                Text("\(s.current)").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(.white)
                Text(s.current == 1 ? "día" : "días").font(.caption).foregroundStyle(Theme.secondary)
            }
            if let next {
                ProgressView(value: Double(s.current), total: Double(next))
                    .tint(Color.white.opacity(0.7))
                    .accessibilityHidden(true)
            }
            HStack {
                Text(best(s, atBest: atBest)).font(.caption).foregroundStyle(atBest ? Theme.better : Theme.secondary)
                Spacer()
                if let next { Text("Siguiente hito: \(next)").font(.caption).foregroundStyle(Theme.tertiary) }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("Actual \(s.current) días. \(best(s, atBest: atBest))" + (next.map { ". Siguiente hito \($0) días" } ?? ""))
    }

    private func best(_ s: Records.Streak, atBest: Bool) -> String {
        if s.best == 0 { return "Aún sin racha" }
        if atBest { return "Tu mejor racha (\(s.best))" }
        let end = s.bestEnd.map { ", hasta el \(Fmt.shortDay($0).lowercased())" } ?? ""
        return "Mejor: \(s.best) \(s.best == 1 ? "día" : "días")\(end)"
    }

    // MARK: Records

    private var records: some View {
        let list = Records.personalBests(model.days)
        let data = byDay
        return PCard {
            CardHeader(title: "Récords personales", subtitle: "Tu mejor día en cada métrica")
            if list.isEmpty {
                Text("Aún no hay días con datos.").font(.subheadline).foregroundStyle(Theme.secondary)
            }
            ForEach(list) { r in
                let imported = data[r.day].map { $0.source != "strap" } ?? false
                Button {
                    month = String(r.day.prefix(7))
                    withAnimation { picked = r.day }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.subheadline).foregroundStyle(.white)
                            Text(Fmt.dayTitle(r.day) + (imported ? " · importado" : ""))
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(value(r)).font(.headline).monospacedDigit().foregroundStyle(.white)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(r.title): \(value(r)), \(Fmt.dayTitle(r.day))\(imported ? ", importado" : "")")
                .accessibilityHint("Muestra ese día en el calendario")
            }
        }
    }

    private func value(_ r: Records.Record) -> String {
        if r.title.hasPrefix("VO₂") { return "\(Fmt.dec(r.value)) mL/kg/min" }
        switch r.title {
        case "Noche más larga": return "\(Fmt.hmm(r.value)) h"
        case "Mejor recuperación": return "\(Int(r.value.rounded())) %"
        case "VFC más alta": return "\(Int(r.value.rounded())) ms"
        case "FC en reposo más baja": return "\(Int(r.value.rounded())) lpm"
        case "Día más exigente": return Fmt.dec(r.value)
        case "Más pasos": return Fmt.thousands(r.value)
        default: return "\(Int(r.value.rounded()))"
        }
    }
}
