import SwiftUI
import PulsoStore
import PulsoAnalytics

/// Recovery of the selected day: the dial, every vital against your last 30 days, what moved it and the week.
struct RecoveryDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAllChips = false

    var body: some View {
        DetailScreen(title: Fmt.cycleTitle(model.selectedDay)) {
            if let day = model.selected {
                hero(day)
                vitals(day)
                behaviours(day)
                RecoveryBreakdown(day: day)
                SectionHeading(text: "Tendencias semanales")
                ForEach([TrendMetric.recovery, .hrv, .rhr, .respRate, .sleepPerformance], id: \.self) { m in
                    WeeklyTrendCard(metric: m)
                }
                ExplainerCard(title: TrendMetric.recovery.explainer.title, text: TrendMetric.recovery.explainer.text)
            } else {
                EmptyState(icon: "bolt.heart", title: "Sin recuperación", message: "Duerme con la pulsera y sincroniza por la mañana.")
            }
        }
    }

    private func hero(_ d: DaySummary) -> some View {
        let color = Theme.recoveryColor(d.recovery)
        return VStack(spacing: 0) {
            ZStack {
                Dial(progress: (d.recovery ?? 0) / 100, color: color, lineWidth: 22)
                VStack(spacing: 6) {
                    Text("PULSO").font(.system(size: 18, weight: .light)).tracking(4).foregroundStyle(Theme.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(d.recovery.map { "\(Int($0))" } ?? "–").font(.system(size: 64, weight: .heavy)).monospacedDigit()
                        if d.recovery != nil { Text("%").font(.system(size: 30, weight: .heavy)) }
                    }
                    .foregroundStyle(.white)
                    Caps(d.calibrating && d.recovery == nil ? "Calibrando" : "Recuperación", size: 13)
                }
            }
            .frame(width: 270, height: 270)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func vitals(_ d: DaySummary) -> some View {
        let before = model.days.filter { $0.day < d.day }
        func usual(_ m: TrendMetric) -> Double? {
            TrendSeries.window(days: before, value: { m.value($0) }, period: .month, today: DayKey.shift(d.day, days: -1)).summary
        }
        let rows: [TrendMetric] = [.hrv, .rhr, .respRate, .sleepPerformance, .spo2, .skinTemp]
        return PCard(padding: 0, spacing: 0) {
            ForEach(rows) { m in
                NavigationLink {
                    TrendDetailView(metric: m)
                } label: {
                    let v = m.value(d), u = usual(m)
                    HStack(spacing: 12) {
                        Image(systemName: m.icon).foregroundStyle(Theme.secondary).frame(width: 24)
                        Caps(m.title, size: 12, weight: .semibold).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(v.map { m.label($0) } ?? "–")
                                    .font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                                if v != nil { DeltaMark(delta: Delta(v, u, higherIsBetter: m.higherIsBetter)) }
                            }
                            if let u { Text(m.label(u)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.secondary) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                if m != rows.last { Divider().overlay(Theme.hairline).padding(.leading, 52) }
            }
            HStack(spacing: 6) {
                Image(systemName: "arrowtriangle.up.fill").foregroundStyle(Theme.better)
                Image(systemName: "arrowtriangle.down.fill").foregroundStyle(Theme.worse)
                Text("\(Fmt.cycleTitle(d.day).capitalized) vs. los últimos 30 días").font(.caption).foregroundStyle(Theme.secondary)
            }
            .font(.system(size: 8))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.25))
        }
    }

    /// What pushed the score up or down: the recovery contributors and yesterday's journal.
    private func behaviours(_ d: DaySummary) -> some View {
        let fromVitals = d.contributors.sorted { abs($0.impact) > abs($1.impact) }.filter { abs($0.impact) > 0.05 }.map {
            (text: $0.label, up: $0.impact > 0, color: $0.impact > 0 ? Theme.better : Theme.worse)
        }
        let yesterday = DayKey.shift(d.day, days: -1)
        let journal = model.journal(for: yesterday).filter { $0.value > 0 }.map {
            (text: JournalCatalog.label($0.key).replacingOccurrences(of: "whoop:", with: ""), up: Optional<Bool>.none, color: Theme.link)
        }
        let all: [(text: String, up: Bool?, color: Color)] = fromVitals.map { ($0.text, Optional($0.up), $0.color) } + journal
        return Group {
            if !all.isEmpty {
                PCard {
                    HStack {
                        Image(systemName: "lightbulb").foregroundStyle(Theme.secondary)
                        Caps("Información sobre comportamientos", size: 12)
                    }
                    Text("Esto es lo que más ha movido tu recuperación de hoy (y lo que apuntaste ayer en el diario).")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    let shown = showAllChips ? all : Array(all.prefix(2))
                    FlowLayout(spacing: 8) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, c in
                            InsightChip(text: c.text, color: c.color, up: c.up)
                        }
                        if !showAllChips && all.count > 2 {
                            Button {
                                withAnimation { showAllChips = true }
                            } label: {
                                Text("+\(all.count - 2) más").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 8)
                                    .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + spacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(width, widest), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + spacing
                x = bounds.minX
                line = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
