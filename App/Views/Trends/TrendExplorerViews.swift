import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

extension TrendMetric {
    /// The trends shown before the user adds any.
    static let main: [TrendMetric] = [.recovery, .hrv, .rhr, .sleepHours, .strain]

    /// "12 % vs. los 30 días anteriores".
    func deltaText(_ now: Double, _ before: Double, range: TrendRange) -> String {
        let previous = "los \(range.rawValue) días anteriores"
        let d = now - before
        switch self {
        case .strain, .respRate, .stress: return "\(Fmt.dec(abs(d))) vs. \(previous)"
        case .skinTemp: return "\(Fmt.dec(abs(d), 2)) °C vs. \(previous)"
        default:
            guard before != 0 else { return "vs. \(previous)" }
            return "\(Int(abs(d / before * 100).rounded())) % vs. \(previous)"
        }
    }

    /// Value with its unit, for sentences and accessibility.
    func spoken(_ v: Double?) -> String {
        guard let v else { return "sin datos" }
        if isDuration { return "\(Fmt.hmm(v)) h" }
        let u = unit == "Calorías" ? "kcal" : unit
        return u.isEmpty ? label(v) : (label(v).hasSuffix("%") ? label(v) : "\(format(v)) \(u)")
    }
}

/// 7 / 30 / 90 / 365 days.
struct RangePicker: View {
    @Binding var range: TrendRange

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TrendRange.allCases, id: \.self) { r in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { range = r }
                } label: {
                    Text(r.label)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(range == r ? .white : Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(range == r ? Theme.cardHighlight : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Últimos \(r.rawValue) días")
                .accessibilityAddTraits(range == r ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Dropdown with every metric grouped; ticks the ones on screen.
struct MetricsMenu: View {
    @Binding var extra: [TrendMetric]

    var body: some View {
        Menu {
            ForEach(TrendMetric.Group.allCases, id: \.self) { g in
                Section(g.rawValue) {
                    ForEach(TrendMetric.allCases.filter { $0.group == g }) { m in
                        let main = TrendMetric.main.contains(m)
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                if let i = extra.firstIndex(of: m) { extra.remove(at: i) } else { extra.append(m) }
                            }
                        } label: {
                            Label(m.title, systemImage: main || extra.contains(m) ? "checkmark" : m.icon)
                        }
                        .disabled(main)
                    }
                }
            }
            if !extra.isEmpty {
                Button(role: .destructive) {
                    withAnimation { extra.removeAll() }
                } label: { Label("Volver a las principales", systemImage: "arrow.uturn.backward") }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle").font(.title3).foregroundStyle(Theme.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Más métricas").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text(extra.isEmpty ? "Recuperación, sueño, esfuerzo y estrés" : "\(extra.count) añadida\(extra.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down").font(.subheadline.weight(.bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("Añadir o quitar métricas")
    }
}

/// One metric over the chosen range: average, change vs the previous range, chart; opens the full trend.
struct RangeTrendCard: View {
    @EnvironmentObject var model: AppModel
    let metric: TrendMetric
    let range: TrendRange
    var onRemove: (() -> Void)?

    var body: some View {
        let w = TrendExplorer.window(days: model.days, value: { metric.value($0) }, range: range,
                                     today: model.currentDayKey, aggregate: metric.aggregate)
        PCard {
            HStack(alignment: .top) {
                NavigationLink {
                    TrendDetailView(metric: metric)
                } label: {
                    HStack(alignment: .top) {
                        Image(systemName: metric.icon).foregroundStyle(metric.color(w.summary)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Caps(metric.title, size: 12)
                                .multilineTextAlignment(.leading)
                            Text("\(metric.summaryLabel(.month)) · \(range.title)").font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, -12)
                    .padding(.trailing, -12)
                    .accessibilityLabel("Quitar \(metric.title)")
                }
            }
            if w.values.isEmpty {
                Text("Sin datos de \(metric.title.lowercased()) en los \(range.title).")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    BigValue(value: metric.format(w.summary), unit: metric.unit, size: 30)
                    if let now = w.summary, let before = w.previous {
                        DeltaChip(text: metric.deltaText(now, before, range: range),
                                  delta: Delta(now, before, higherIsBetter: metric.higherIsBetter))
                    }
                }
                RangeChart(metric: metric, points: w.points, range: range)
                    .frame(height: 150)
                Text(footer(w)).font(.caption2).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func footer(_ w: TrendWindow) -> String {
        let per = range == .year ? "Cada punto es la media de una semana. " : ""
        return "\(per)\(w.values.count) de \(range.rawValue) días con datos. Toca el gráfico para leer un día."
    }
}

/// Bars or line over dates, with the period average and tap-to-read.
struct RangeChart: View {
    let metric: TrendMetric
    let points: [TrendSample]
    let range: TrendRange
    var color: Color?
    @State private var selected: Date?

    private struct P: Identifiable {
        var id: String { day }
        let day: String
        let date: Date
        let value: Double
    }

    private var data: [P] {
        points.compactMap { s in
            guard let v = s.value, let d = DayKey.date(s.day) else { return nil }
            return P(day: s.day, date: d, value: v)
        }
    }

    private var unit: Calendar.Component { range == .year ? .weekOfYear : .day }

    var body: some View {
        let pts = data
        let avg = Stats.mean(pts.map(\.value))
        let pick = selected.flatMap { s in pts.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } }
        Chart {
            ForEach(pts) { p in
                switch metric.kind {
                case .bar:
                    BarMark(x: .value("Día", p.date, unit: unit), y: .value(metric.title, p.value))
                        .foregroundStyle(color ?? metric.color(p.value))
                        .opacity(pick == nil || pick?.day == p.day ? 1 : 0.45)
                        .cornerRadius(2)
                        .accessibilityLabel(Fmt.dayTitle(p.day))
                        .accessibilityValue(metric.spoken(p.value))
                case .line:
                    LineMark(x: .value("Día", p.date, unit: unit), y: .value(metric.title, p.value))
                        .foregroundStyle(color ?? metric.color(p.value))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .accessibilityLabel(Fmt.dayTitle(p.day))
                        .accessibilityValue(metric.spoken(p.value))
                    if pts.count <= 31 {
                        PointMark(x: .value("Día", p.date, unit: unit), y: .value(metric.title, p.value))
                            .foregroundStyle(color ?? metric.color(p.value))
                            .symbolSize(18)
                    }
                }
            }
            if let avg {
                RuleMark(y: .value("Media", avg))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityLabel("Media del periodo")
                    .accessibilityValue(metric.spoken(avg))
            }
            if let pick {
                RuleMark(x: .value("Día", pick.date, unit: unit))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(metric.label(pick.value)).font(.subheadline.weight(.bold)).monospacedDigit()
                            Text(range == .year ? "Semana del \(Fmt.shortDay(pick.day).lowercased())" : Fmt.dayTitle(pick.day))
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartYScale(domain: metric.domain(pts.map(\.value)))
        .chartXScale(domain: xDomain)
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(metric.isDuration ? Fmt.hmm(d) : (abs(d) >= 1000 ? Fmt.thousands(d) : Fmt.dec(d, d == d.rounded() ? 0 : 1)))
                            .font(.caption2).foregroundStyle(Theme.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: range == .year ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityLabel("\(metric.title), \(range.title)")
    }

    private var xDomain: ClosedRange<Date> {
        let first = points.first.flatMap { DayKey.date($0.day) } ?? Date()
        let last = points.last.flatMap { DayKey.date($0.day) } ?? Date()
        let end = Calendar.current.date(byAdding: .day, value: range == .year ? 7 : 1, to: last) ?? last
        return first...end
    }
}

/// Metrics whose last 7 days moved beyond their normal swing vs the 28 days before.
struct NotableChangesCard: View {
    @EnvironmentObject var model: AppModel

    private struct Row: Identifiable {
        var id: String { metric.rawValue }
        let metric: TrendMetric
        let change: RecentChange
    }

    var body: some View {
        let candidates = TrendMetric.allCases.filter { $0.aggregate == .average && $0 != .spo2 }
        let all = candidates.compactMap { m in
            TrendExplorer.recentChange(days: model.days, value: { m.value($0) }, today: model.currentDayKey).map { Row(metric: m, change: $0) }
        }
        let notable = all.filter(\.change.isNotable)
            .sorted { abs($0.change.delta) / $0.change.threshold > abs($1.change.delta) / $1.change.threshold }
        PCard {
            CardHeader(title: "Cambios destacados", subtitle: "Últimos 7 días frente a los 28 anteriores")
            if all.isEmpty {
                Text("Aún no hay datos suficientes: hacen falta al menos 4 de los últimos 7 días y 14 de los 28 anteriores.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if notable.isEmpty {
                Label("Nada fuera de tu variación normal", systemImage: "equal.circle")
                    .font(.subheadline).foregroundStyle(.white)
            } else {
                ForEach(notable) { r in
                    let delta = Delta(r.change.recent, r.change.baseline, higherIsBetter: r.metric.higherIsBetter, tolerance: 0)
                    NavigationLink {
                        TrendDetailView(metric: r.metric)
                    } label: {
                        HStack(spacing: 10) {
                            DeltaMark(delta: delta, size: 11)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.metric.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Text("\(r.metric.spoken(r.change.recent)) frente a \(r.metric.spoken(r.change.baseline))")
                                    .font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.tertiary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(r.metric.title): \(delta.trend == .up ? "sube" : "baja") a \(r.metric.spoken(r.change.recent)) frente a \(r.metric.spoken(r.change.baseline))")
                }
            }
            Text("Solo se marca un cambio cuando la media de 7 días se sale de lo que suele moverse en tus 4 semanas anteriores.")
                .font(.caption2).foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Two metrics on one chart (normalized) or one above the other.
struct CompareTrendsCard: View {
    @EnvironmentObject var model: AppModel
    let range: TrendRange
    @AppStorage("trends.compareA") private var rawA = TrendMetric.recovery.rawValue
    @AppStorage("trends.compareB") private var rawB = TrendMetric.sleepHours.rawValue
    @State private var overlay = true

    private var a: TrendMetric { TrendMetric(rawValue: rawA) ?? .recovery }
    private var b: TrendMetric { TrendMetric(rawValue: rawB) ?? .sleepHours }
    private let colorA = Theme.hrv
    private let colorB = Theme.stress

    var body: some View {
        let today = model.currentDayKey
        let wa = TrendExplorer.window(days: model.days, value: { a.value($0) }, range: range, today: today, aggregate: a.aggregate)
        let wb = TrendExplorer.window(days: model.days, value: { b.value($0) }, range: range, today: today, aggregate: b.aggregate)
        PCard {
            CardHeader(title: "Comparar dos métricas", subtitle: range.title.prefix(1).uppercased() + range.title.dropFirst())
            HStack(spacing: 8) {
                picker($rawA, current: a, color: colorA)
                picker($rawB, current: b, color: colorB)
            }
            Picker("Vista", selection: $overlay) {
                Text("Superpuestas").tag(true)
                Text("Por separado").tag(false)
            }
            .pickerStyle(.segmented)
            if a == b {
                Text("Elige dos métricas distintas.").font(.subheadline).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else if wa.values.count < 2 || wb.values.count < 2 {
                Text("Hacen falta al menos 2 días con datos de cada métrica en este periodo.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            } else if overlay {
                overlayChart(TrendExplorer.standardized(wa.points), TrendExplorer.standardized(wb.points))
                    .frame(height: 170)
                Text("Cada línea en desviaciones respecto a su propia media del periodo (0 = su media), para poder comparar unidades distintas.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                relation
            } else {
                separate(a, wa, colorA)
                separate(b, wb, colorB)
                relation
            }
        }
        .animation(.easeInOut(duration: 0.25), value: overlay)
    }

    private func picker(_ raw: Binding<String>, current: TrendMetric, color: Color) -> some View {
        Menu {
            ForEach(TrendMetric.Group.allCases, id: \.self) { g in
                Section(g.rawValue) {
                    ForEach(TrendMetric.allCases.filter { $0.group == g }) { m in
                        Button { raw.wrappedValue = m.rawValue } label: { Label(m.title, systemImage: m == current ? "checkmark" : m.icon) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(current.title).font(.footnote.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 2)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel("Métrica: \(current.title)")
    }

    private func overlayChart(_ pa: [TrendSample], _ pb: [TrendSample]) -> some View {
        Chart {
            series(pa, a, colorA)
            series(pb, b, colorB)
            RuleMark(y: .value("Media", 0))
                .foregroundStyle(Color.white.opacity(0.25))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartForegroundStyleScale([a.title: colorA, b.title: colorB])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading, values: [-2, -1, 0, 1, 2]) { v in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(d == 0 ? "media" : String(format: "%+.0f", d)).font(.caption2).foregroundStyle(Theme.secondary) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel(format: range == .year ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityLabel("\(a.title) y \(b.title) superpuestas, \(range.title)")
    }

    @ChartContentBuilder
    private func series(_ pts: [TrendSample], _ m: TrendMetric, _ color: Color) -> some ChartContent {
        ForEach(pts.compactMap { s in s.value.flatMap { v in DayKey.date(s.day).map { (s.day, $0, v) } } }, id: \.0) { p in
            LineMark(x: .value("Día", p.1, unit: range == .year ? .weekOfYear : .day), y: .value("Desviación", p.2),
                     series: .value("Métrica", m.title))
                .foregroundStyle(by: .value("Métrica", m.title))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .accessibilityLabel("\(m.title), \(Fmt.dayTitle(p.0))")
                .accessibilityValue(String(format: "%+.1f desviaciones", p.2))
        }
    }

    private func separate(_ m: TrendMetric, _ w: TrendWindow, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(m.title).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                Spacer()
                Text("Media \(m.spoken(w.summary))").font(.caption).foregroundStyle(Theme.secondary)
            }
            RangeChart(metric: m, points: w.points, range: range, color: color)
                .frame(height: 110)
        }
    }

    @ViewBuilder
    private var relation: some View {
        let from = DayKey.shift(model.currentDayKey, days: -(range.rawValue - 1))
        let ds = model.days.filter { $0.day >= from }
        let pairs = Relation.pairs(days: ds.map(\.day), ds.map { a.value($0) }, ds.map { b.value($0) }, lagDays: 0)
        if a != b, let fit = Relation.fit(pairs), fit.n >= 10 {
            Text("\(fit.strength) el mismo día (r = \(Fmt.dec(fit.r, 2)), \(fit.n) días). Ir juntas no significa que una cause la otra.")
                .font(.caption).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
