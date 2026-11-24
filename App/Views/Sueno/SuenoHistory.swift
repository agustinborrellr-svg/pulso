import SwiftUI
import PulsoStore
import PulsoAnalytics

/// «Tus noches» (studio B-sueno 19): 7 / 30 nights as stage ribbons on a clock axis (or 6 months by week), with the
/// mean, the best night and how many fell in your normal; below, the weekly trends of the sleep metrics.
struct SuenoHistoryView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var span = 7

    private var end: String { model.selectedDay }

    var body: some View {
        let keys = (0..<span).map { DayKey.shift(end, days: -$0) }
        let nights = keys.compactMap { k in model.day(k).flatMap { d in d.sleepMinutes != nil ? d : nil } }
        DSScreen("Tus noches", subtitle: subtitle, back: "Sueño") {
            DSSegmented(options: [(7, "7 noches"), (30, "30 noches"), (182, "6 meses")], selection: $span, height: 34)
            if nights.isEmpty {
                DSEmptyState(icon: "moon.zzz", title: "Sin noches en este periodo", tint: DS.sueno)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    DSStatStrip(stats: stats(nights))
                    if span <= 30 {
                        ribbons(nights)
                    } else {
                        weeks(nights)
                    }
                }
                .dsCard(padding: 16)
            }
            trends
        }
    }

    private var subtitle: String {
        let first = DayKey.shift(end, days: -(span - 1))
        return "\(DSFmt.dayMonth(first)) – \(DSFmt.dayMonth(end))"
    }

    private func stats(_ nights: [DaySummary]) -> [DSStat] {
        let mins = nights.compactMap(\.sleepMinutes)
        var out = [DSStat(label: "Media", value: DSFmt.duration(mins.reduce(0, +) / Double(max(mins.count, 1))))]
        if let best = nights.filter({ $0.sleepPerformance != nil }).max(by: { ($0.sleepPerformance ?? 0) < ($1.sleepPerformance ?? 0) }) {
            out.append(DSStat(label: "Mejor noche", value: dayLabel(best.day).lowercased()))
        }
        let first = DayKey.shift(end, days: -(span - 1))
        if let n = SuenoSpec.normal(model, before: first, { $0.sleepMinutes }) {
            out.append(DSStat(label: "En tu normal", value: "\(mins.filter { n.contains($0) }.count)", unit: "de \(mins.count)"))
        }
        return out
    }

    /// "Lun 16".
    private func dayLabel(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE d"
        let s = f.string(from: d).replacingOccurrences(of: ".", with: "")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // MARK: Ribbons

    private func ribbons(_ nights: [DaySummary]) -> some View {
        // Clock axis that holds every night: bedtimes from 12:00 (23:30 < 00:30), wake times the next morning.
        let starts = nights.compactMap(\.sleepStart).map { SuenoClock.minutes($0, evening: true) }
        let ends = nights.compactMap { d -> Double? in
            guard let a = d.sleepStart, let b = d.sleepEnd else { return nil }
            return SuenoClock.minutes(a, evening: true) + Double(b - a) / 60
        }
        let lo = ((starts.min() ?? 1320) / 60).rounded(.down) * 60
        let hi = max(((ends.max() ?? 1950) / 60).rounded(.up) * 60, lo + 120)
        return VStack(spacing: 0) {
            GeometryReader { g in
                ForEach(axisMarks(lo, hi), id: \.self) { m in
                    Text(SuenoClock.text(m).prefix(2)).dsFont(12, .medium).foregroundStyle(DS.t3).fixedSize()
                        .position(x: g.size.width * CGFloat((m - lo) / (hi - lo)), y: 8)
                }
            }
            .frame(height: 16)
            .padding(.leading, 74).padding(.trailing, 116)
            ForEach(nights, id: \.day) { d in
                if d.day != nights.first?.day { DSDivider() }
                Button {
                    model.selectDay(d.day)
                    router.open(.sueno(.noche(day: d.day)))
                } label: {
                    HStack(spacing: 8) {
                        Text(dayLabel(d.day)).dsFont(15, d.day == end ? .semibold : .regular)
                            .foregroundStyle(d.day == end ? DS.t1 : DS.t2)
                            .frame(width: 66, alignment: .leading)
                        NightRibbon(session: model.sleep(for: d), day: d, lo: lo, hi: hi).frame(height: 18)
                        Text(DSFmt.duration(d.sleepMinutes)).dsFont(15, .semibold).foregroundStyle(DS.t1)
                            .frame(width: 58, alignment: .trailing)
                        HStack(spacing: 4) {
                            if let p = d.sleepPerformance {
                                HoyDot(color: DSLevel(score: p * 100).mark, size: 6)
                                Text("\(Int((p * 100).rounded()))").dsFont(14).foregroundStyle(DS.t2)
                            }
                        }
                        .frame(width: 36, alignment: .trailing)
                        DSChevron()
                    }
                    .frame(minHeight: span == 7 ? 50 : 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 14) {
                ForEach([SleepStage.deep, .rem, .light, .awake], id: \.self) { st in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(DS.stage(st)).frame(width: 9, height: 9)
                        Text(Theme.stageName(st)).dsFont(13).foregroundStyle(DS.t2)
                    }
                }
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func axisMarks(_ lo: Double, _ hi: Double) -> [Double] {
        stride(from: lo + 60, to: hi, by: 60).filter { (Int($0) / 60) % 2 == 0 }
    }

    // MARK: 6 months by week

    private func weeks(_ nights: [DaySummary]) -> some View {
        var groups: [String: [DaySummary]] = [:]
        for d in nights {
            guard let date = DayKey.date(d.day), let w = Calendar(identifier: .iso8601).dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            groups[DayKey.string(w), default: []].append(d)
        }
        let keys = groups.keys.sorted(by: >)
        let maxM = max(nights.compactMap(\.sleepMinutes).max() ?? 1, 1)
        return VStack(spacing: 0) {
            ForEach(keys, id: \.self) { k in
                let list = groups[k] ?? []
                let mins = list.compactMap(\.sleepMinutes)
                let mean = mins.reduce(0, +) / Double(max(mins.count, 1))
                let perf = list.compactMap(\.sleepPerformance)
                if k != keys.first { DSDivider() }
                HStack(spacing: 10) {
                    Text("sem. \(DSFmt.dayMonth(k))").dsFont(14).foregroundStyle(DS.t2).frame(width: 86, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(DS.sueno.opacity(0.75)).frame(width: max(6, g.size.width * CGFloat(mean / maxM)), height: 8)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    Text(DSFmt.duration(mean)).dsFont(14, .semibold).foregroundStyle(DS.t1).frame(width: 56, alignment: .trailing)
                    Text(perf.isEmpty ? "" : "\(Int((perf.reduce(0, +) / Double(perf.count) * 100).rounded()))")
                        .dsFont(14).foregroundStyle(DS.t2).frame(width: 28, alignment: .trailing)
                }
                .frame(minHeight: 36)
            }
        }
    }

    // MARK: Weekly trends

    private var trends: some View {
        let rows: [(TrendMetric, String, MetricKind)] = [
            (.sleepPerformance, "Calificación", .calificacion), (.hoursVsNeed, "Horas vs. lo necesario", .necesidadSueno),
            (.restorativeHours, "Sueño reparador", .reparador), (.regularity, "Regularidad", .regularidad),
            (.timeInBed, "Bloque detectado", .eficiencia), (.efficiency, "Eficiencia", .eficiencia), (.sleepDebt, "Deuda de sueño", .necesidadSueno),
        ]
        let keys = (0..<7).map { DayKey.shift(end, days: $0 - 6) }
        return VStack(alignment: .leading, spacing: DS.stack) {
            DSSectionHeader("Tendencias semanales")
            DSGroup {
                ForEach(rows, id: \.1) { m, title, kind in
                    let vals = keys.map { k in model.day(k).flatMap { m.value($0) } }
                    let have = vals.compactMap { $0 }
                    if !have.isEmpty {
                        RouteLink(.metric(kind)) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title).dsFont(16).foregroundStyle(DS.t1)
                                    Text(m == .sleepDebt ? "ahora \(fmt(m, vals.last.flatMap { $0 } ?? have.last ?? 0))"
                                                         : "media \(fmt(m, have.reduce(0, +) / Double(have.count)))")
                                        .dsFont(13).foregroundStyle(DS.t2)
                                }
                                Spacer()
                                MiniBars(values: vals)
                                DSChevron()
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .dsRowInset(16)
                    }
                }
            }
        }
    }

    private func fmt(_ m: TrendMetric, _ v: Double) -> String {
        if m.isDuration { return DSFmt.duration(v) }
        switch m {
        case .hoursVsNeed, .regularity, .efficiency: return "\(Int(v.rounded())) %"
        default: return "\(Int(v.rounded()))"
        }
    }
}

/// Seven small bars, the last in violet (Tendencias semanales).
private struct MiniBars: View {
    let values: [Double?]

    var body: some View {
        let have = values.compactMap { $0 }
        let lo = (have.min() ?? 0) * 0.9, hi = max(have.max() ?? 1, lo + 0.0001)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(values.indices, id: \.self) { i in
                let v = values[i]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i == values.count - 1 ? DS.sueno : DS.fill2)
                    .frame(width: 5, height: v.map { max(4, 22 * CGFloat(($0 - lo) / (hi - lo))) } ?? 2)
            }
        }
        .frame(height: 24, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// One night on the clock axis: its stages minute by minute, or a plain violet bar without detail.
private struct NightRibbon: View {
    let session: SleepSession?
    let day: DaySummary
    let lo: Double
    let hi: Double

    var body: some View {
        Canvas { ctx, size in
            guard let a = day.sleepStart, let b = day.sleepEnd else { return }
            let x0 = CGFloat((SuenoClock.minutes(a, evening: true) - lo) / (hi - lo)) * size.width
            let perMin = size.width / CGFloat(hi - lo)
            let clip = Path(roundedRect: CGRect(x: x0, y: 0, width: CGFloat(b - a) / 60 * perMin, height: size.height), cornerRadius: 4)
            ctx.clip(to: clip)
            if let s = session, !s.stages.isEmpty {
                let sx = x0 + CGFloat(s.start - a) / 60 * perMin
                for r in StageRuns.runs(s) {
                    let rect = CGRect(x: sx + CGFloat(r.index) * perMin, y: 0, width: max(1, CGFloat(r.minutes) * perMin), height: size.height)
                    ctx.fill(Path(rect), with: .color(DS.stage(r.stage)))
                }
            } else {
                ctx.fill(clip, with: .color(DS.sueno.opacity(0.7)))
            }
        }
        .accessibilityHidden(true)
    }
}
