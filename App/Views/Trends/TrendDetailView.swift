import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// "VISTA DE TENDENCIAS": one metric over a week, a month or six months.
struct TrendDetailView: View {
    @EnvironmentObject var model: AppModel
    @State var metric: TrendMetric
    @State private var period: TrendPeriod = .week
    @State private var offset = 0

    private var today: String { DayKey.string(Date()) }

    private var window: TrendWindow {
        TrendSeries.window(days: model.days, value: { metric.value($0) }, period: period, offset: offset,
                           today: today, aggregate: metric.aggregate)
    }

    var body: some View {
        let w = window
        DetailScreen(title: "Vista de tendencias") {
            MetricPicker(metric: $metric)
                .onChange(of: metric) { _, _ in offset = 0 }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Caps(metric.summaryLabel(period), size: 11, color: Theme.secondary, weight: .semibold)
                    BigValue(value: metric.format(w.summary), unit: metric.unit, size: 38)
                    if let now = w.summary, let before = w.previous {
                        DeltaChip(text: metric.deltaText(now, before, period: period),
                                  delta: Delta(now, before, higherIsBetter: metric.higherIsBetter))
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 10) {
                    PeriodPicker(period: $period)
                        .onChange(of: period) { _, _ in offset = 0 }
                    HStack(spacing: 10) {
                        Button { offset += 1 } label: { Image(systemName: "chevron.left").font(.headline) }
                        Caps(rangeText(w), size: 11)
                            .multilineTextAlignment(.center)
                            .frame(minWidth: 96)
                        Button { offset = max(0, offset - 1) } label: { Image(systemName: "chevron.right").font(.headline) }
                            .disabled(offset == 0)
                            .opacity(offset == 0 ? 0.3 : 1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }
            }

            Text(metric.narrative(w, period: period))
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            TrendChart(metric: metric, points: w.points, period: period, highlightLast: offset == 0)
                .frame(height: 280)
                .padding(.top, 6)

            if metric.aggregate == .total {
                Label("El tiempo en zonas sale de tu pulso a lo largo del día y de tus entrenos.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            if let b = metric.breakdown(w, days: model.days), b.buckets.contains(where: { $0.value > 0 }) {
                BreakdownView(title: b.title, buckets: b.buckets)
                    .padding(.top, 8)
            }

            ExplainerCard(title: metric.explainer.title, text: metric.explainer.text)
                .padding(.top, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: period)
        .animation(.easeInOut(duration: 0.25), value: offset)
    }

    private func rangeText(_ w: TrendWindow) -> String {
        "\(Fmt.shortDay(w.from)) -\n\(Fmt.shortDay(w.to)), \(w.to.prefix(4).suffix(2))"
    }
}

/// Dropdown with every metric, grouped.
struct MetricPicker: View {
    @Binding var metric: TrendMetric

    var body: some View {
        Menu {
            ForEach(TrendMetric.Group.allCases, id: \.self) { g in
                Section(g.rawValue) {
                    ForEach(TrendMetric.allCases.filter { $0.group == g }) { m in
                        Button {
                            metric = m
                        } label: {
                            Label(m.title, systemImage: m.icon)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: metric.icon).font(.system(size: 18)).foregroundStyle(Theme.secondary).frame(width: 24)
                Caps(metric.title, size: 13)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Image(systemName: "chevron.down").font(.subheadline.weight(.bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// S / M / 6 M.
struct PeriodPicker: View {
    @Binding var period: TrendPeriod
    var options: [TrendPeriod] = TrendPeriod.allCases

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { p in
                Button {
                    period = p
                } label: {
                    Caps(p.label, size: 11, color: period == p ? .white : Theme.secondary, weight: .semibold)
                        .frame(width: 52, height: 34)
                        .background(period == p ? Theme.cardHighlight : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Bars or line with the value on each point, today's column highlighted, tap to read any day.
struct TrendChart: View {
    let metric: TrendMetric
    let points: [TrendSample]
    let period: TrendPeriod
    var highlightLast = true
    var compact = false
    @State private var selected: String?

    private var values: [Double] { points.compactMap(\.value) }

    var body: some View {
        let domain = metric.domain(values)
        let showLabels = period == .week
        Chart {
            if highlightLast, period != .halfYear, let last = points.last {
                RectangleMark(x: .value("Día", last.day), yStart: .value("min", domain.lowerBound), yEnd: .value("max", domain.upperBound),
                              width: .ratio(0.95))
                    .foregroundStyle(Color.white.opacity(0.07))
                    .cornerRadius(4)
            }
            ForEach(points, id: \.day) { p in
                if let v = p.value {
                    switch metric.kind {
                    case .bar:
                        BarMark(x: .value("Día", p.day), y: .value(metric.title, v), width: .ratio(period == .week ? 0.34 : 0.62))
                            .foregroundStyle(metric.color(v))
                            .cornerRadius(1.5)
                            .annotation(position: .top, spacing: 4) {
                                if showLabels {
                                    Text(metric.label(v))
                                        .font(.system(size: compact ? 10 : 12, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundStyle(metric.color(v))
                                        .fixedSize()
                                }
                            }
                    case .line:
                        AreaMark(x: .value("Día", p.day), yStart: .value("base", domain.lowerBound), yEnd: .value(metric.title, v))
                            .foregroundStyle(LinearGradient(colors: [metric.color(v).opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.linear)
                        LineMark(x: .value("Día", p.day), y: .value(metric.title, v))
                            .foregroundStyle(metric.color(v))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Día", p.day), y: .value(metric.title, v))
                            .symbol {
                                Circle().strokeBorder(metric.color(v), lineWidth: 2)
                                    .background(Circle().fill(Theme.card))
                                    .frame(width: 10, height: 10)
                            }
                            .annotation(position: .top, spacing: 6) {
                                if showLabels {
                                    Text(metric.label(v))
                                        .font(.system(size: compact ? 10 : 12, weight: .bold))
                                        .monospacedDigit()
                                        .foregroundStyle(metric.color(v))
                                        .fixedSize()
                                }
                            }
                    }
                }
            }
            if let s = selected, let sv = points.first(where: { $0.day == s })?.value {
                RuleMark(x: .value("Día", s))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(metric.label(sv)).font(.headline.monospacedDigit())
                            Text(Fmt.dayTitle(s)).font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: compact ? 3 : 5)) { v in
                AxisGridLine().foregroundStyle(Theme.hairline)
                if !compact {
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(metric.isDuration ? Fmt.hmm(d) : axisNumber(d)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: axisDays) { v in
                AxisValueLabel(centered: true) {
                    if let key = v.as(String.self) {
                        let (wd, d) = Fmt.weekdayAndDay(key)
                        let isLast = highlightLast && key == points.last?.day
                        if period == .halfYear {
                            Text(monthLabel(key)).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        } else {
                            VStack(spacing: 1) {
                                if period == .week { Text(wd) }
                                Text(d)
                            }
                            .font(.system(size: 11, weight: isLast ? .bold : .regular))
                            .foregroundStyle(isLast ? Color.white : Theme.secondary)
                        }
                    }
                }
            }
        }
    }

    private var axisDays: [String] {
        switch period {
        case .week: return points.map(\.day)
        case .month: return points.enumerated().filter { $0.offset % 5 == 4 || $0.offset == points.count - 1 }.map(\.element.day)
        case .halfYear: return points.enumerated().filter { $0.offset % 4 == 0 }.map(\.element.day)
        }
    }

    private func axisNumber(_ d: Double) -> String {
        if metric.unit == "%" { return "\(Int(d)) %" }
        if abs(d) >= 1000 { return Fmt.thousands(d) }
        return d == d.rounded() ? "\(Int(d))" : Fmt.dec(d)
    }

    private func monthLabel(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }
}

/// "DESGLOSE DE …": proportional bar and legend.
struct BreakdownView: View {
    let title: String
    let buckets: [TrendMetric.Bucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Caps(title, size: 12)
            GeometryReader { geo in
                let total = max(buckets.reduce(0) { $0 + $1.value }, 0.0001)
                HStack(spacing: 2) {
                    ForEach(buckets) { b in
                        if b.value > 0 {
                            Rectangle().fill(b.color).frame(width: max(3, (geo.size.width - 6) * b.value / total))
                        }
                    }
                }
            }
            .frame(height: 12)
            ForEach(buckets) { b in
                HStack(spacing: 10) {
                    Rectangle().fill(b.color).frame(width: 9, height: 9)
                    Text(b.text).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                        .frame(minWidth: 34, alignment: .leading)
                    Text(b.label).font(.system(size: 15)).foregroundStyle(.white)
                }
            }
        }
    }
}

/// Weekly mini-chart card that opens the full trend ("Tendencias semanales").
struct WeeklyTrendCard: View {
    @EnvironmentObject var model: AppModel
    let metric: TrendMetric

    var body: some View {
        let w = TrendSeries.window(days: model.days, value: { metric.value($0) }, period: .week,
                                   today: DayKey.string(Date()), aggregate: metric.aggregate)
        NavigationLink {
            TrendDetailView(metric: metric)
        } label: {
            PCard {
                CardHeader(title: metric.title, chevron: true)
                TrendChart(metric: metric, points: w.points, period: .week, compact: true)
                    .frame(height: 190)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
    }
}
