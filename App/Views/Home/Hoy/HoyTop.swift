import SwiftUI
import PulsoStore
import PulsoAnalytics

// MARK: - Header

/// Date on the left, the day pill in the middle (‹ Hoy ›, tap for the calendar) and the band's battery on the right.
struct HoyHeader: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let isToday = model.selectedDay >= model.currentDayKey
        ZStack {
            HStack {
                Text(HoyFmt.shortDate(model.selectedDay))
                    .hoyFont(15, .semibold, relativeTo: .subheadline).foregroundStyle(Hoy.t2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                NavigationLink { DeviceView() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "applewatch").font(.system(size: 14, weight: .semibold))
                        if let b = model.battery {
                            Text("\(Int(b)) %").hoyFont(15, .semibold, relativeTo: .subheadline)
                        }
                    }
                    .foregroundStyle(model.battery.map { $0 < 20 } == true ? HoyLevel.baja.ink : Hoy.t2)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.battery.map { "Pulsera, batería \(Int($0)) %" } ?? "Pulsera")
            }
            HStack(spacing: 0) {
                Button { model.shiftSelectedDay(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 38).contentShape(Rectangle())
                }
                .accessibilityLabel("Día anterior")
                Button {
                    withAnimation(.easeInOut(duration: 0.28)) { model.showDayPicker.toggle() }
                } label: {
                    Text(pillTitle).hoyFont(17, .semibold, relativeTo: .headline)
                        .fixedSize()
                        .frame(minWidth: 56, minHeight: 38)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Elegir día, \(Fmt.dayTitle(model.selectedDay))")
                .accessibilityHint("Abre el calendario")
                Button { model.shiftSelectedDay(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 38).contentShape(Rectangle())
                }
                .accessibilityLabel("Día siguiente")
                .disabled(isToday)
                .foregroundStyle(isToday ? Hoy.t3 : Hoy.t1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Hoy.t1)
            .background(Hoy.card, in: Capsule())
        }
        .padding(.top, 4)
    }

    private var pillTitle: String {
        let k = model.selectedDay
        if k >= model.currentDayKey { return "Hoy" }
        if k == DayKey.shift(model.currentDayKey, days: -1) { return "Ayer" }
        guard let a = DayKey.date(k), let b = DayKey.date(model.currentDayKey) else { return k }
        let n = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
        return "Hace \(n) días"
    }
}

// MARK: - Scores

/// Open arc (270°, gap at the bottom) with the value in the middle; an optional notch marks a target.
struct ScoreArc: View {
    let progress: Double
    let color: Color
    let value: String
    var notch: Double?
    var size: CGFloat = 76
    var line: CGFloat = 7

    private static let sweep = 0.75

    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: Self.sweep)
                .stroke(Hoy.fill, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: Self.sweep * min(max(progress, 0.004), 1))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.6), value: progress)
            if let notch {
                // A short tick across the outer edge of the arc.
                let angle = Angle.degrees(135 + 270 * min(max(notch, 0), 1))
                Capsule().fill(Hoy.t1)
                    .frame(width: line + 7, height: 2.2)
                    .offset(x: size / 2 + 2)
                    .rotationEffect(angle)
            }
            Text(value).hoyFont(size * 0.40, .semibold, relativeTo: .title1, maxScale: 1.2)
                .foregroundStyle(Hoy.t1)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, line + 4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Level word (or target) under a score, with its dot.
private struct ScoreLevel {
    let text: String
    let color: Color
    var dot: Color?

    init(_ text: String, _ color: Color, dot: Color? = nil) {
        self.text = text
        self.color = color
        self.dot = dot
    }

    init(_ l: HoyLevel) { self.init(l.word, l.ink, dot: l.mark) }
}

/// One column of the scores card: arc, name, level (or target) and yesterday's value.
private struct ScoreColumn: View {
    let title: String
    let arc: ScoreArc
    let level: ScoreLevel?
    let yesterday: String?

    var body: some View {
        VStack(spacing: 2) {
            arc.padding(.bottom, 4)
            Text(title).hoyFont(17, .semibold, relativeTo: .headline).foregroundStyle(Hoy.t1)
            if let level {
                HStack(spacing: 5) {
                    if let dot = level.dot { HoyDot(color: dot) }
                    Text(level.text).hoyFont(15, .semibold, relativeTo: .subheadline).foregroundStyle(level.color)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            if let yesterday {
                Text("ayer \(yesterday)").hoyFont(15, relativeTo: .subheadline).foregroundStyle(Hoy.t3)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Recarga, Sueño and Esfuerzo with the folded health monitor underneath.
struct HoyScoresCard: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary?

    var body: some View {
        let prev = day.flatMap { model.day(DayKey.shift($0.day, days: -1)) }
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                NavigationLink { RecoveryDetailView() } label: { recarga(prev) }
                NavigationLink { SleepDetailView() } label: { sueno(prev) }
                NavigationLink { StrainDetailView() } label: { esfuerzo(prev) }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 14)
            Rectangle().fill(Hoy.sep).frame(height: 1)
            NavigationLink { HealthMonitorView() } label: { HoyMonitor(day: day) }
                .buttonStyle(.plain)
        }
        .background(Hoy.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func recarga(_ prev: DaySummary?) -> some View {
        let r = day?.recovery
        let lv = r.map(HoyLevel.init(score:))
        return ScoreColumn(title: "Recarga",
                           arc: ScoreArc(progress: (r ?? 0) / 100, color: Hoy.recarga,
                                         value: r.map { "\(Int($0.rounded()))" } ?? (day?.calibrating == true ? "…" : "–")),
                           level: lv.map(ScoreLevel.init) ?? (day?.calibrating == true ? ScoreLevel("Calibrando", Hoy.t3) : nil),
                           yesterday: prev?.recovery.map { "\(Int($0.rounded()))" })
    }

    private func sueno(_ prev: DaySummary?) -> some View {
        let s = day?.sleepPerformance.map { $0 * 100 }
        let lv = s.map(HoyLevel.init(score:))
        return ScoreColumn(title: "Sueño",
                           arc: ScoreArc(progress: (s ?? 0) / 100, color: Hoy.sueno, value: s.map { "\(Int($0.rounded()))" } ?? "–"),
                           level: lv.map(ScoreLevel.init),
                           yesterday: prev?.sleepPerformance.map { "\(Int(($0 * 100).rounded()))" })
    }

    private func esfuerzo(_ prev: DaySummary?) -> some View {
        let s = day?.strain
        // The day's target from the coach (a range on the 0–21 scale), only once there is a recovery to base it on.
        let target = day.flatMap { d in d.recovery == nil ? nil : model.coachAdvice(for: d).strainTarget }
        let text = target.map { "Objetivo \(Int($0.lowerBound))–\(Int($0.upperBound))" }
        return ScoreColumn(title: "Esfuerzo",
                           arc: ScoreArc(progress: (s ?? 0) / 21, color: Hoy.act, value: Fmt.dec(s),
                                         notch: target.map { $0.lowerBound / 21 }),
                           level: text.map { ScoreLevel($0, Hoy.t2) },
                           yesterday: prev?.strain.map { Fmt.dec($0) })
    }
}

// MARK: - Monitor de salud (folded)

/// Five equal segments, one per vital of last night (green in your range, amber/red out of it) and a sixth for the
/// current stress. Out of range, the value goes under its segment and one short line says why.
struct HoyMonitor: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary?

    static let order = ["hrv", "rhr", "resp", "spo2", "temp"]
    static let icons = ["hrv": "waveform.path.ecg", "rhr": "heart.fill", "resp": "lungs.fill", "spo2": "drop.fill",
                        "temp": "thermometer.medium"]

    var body: some View {
        let all = model.vitalReadings()
        let readings = Self.order.compactMap { id in all.first { $0.id == id } }
        let off = readings.filter { $0.level == .orange || $0.level == .red }
        let stress = day?.stressPoints.last?.v
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").font(.system(size: 14)).foregroundStyle(Hoy.cor)
                Text("Monitor de salud").hoyFont(16, .medium, relativeTo: .subheadline).foregroundStyle(Hoy.t2)
                Spacer(minLength: 6)
                status(readings, off: off)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Hoy.t3)
            }
            if !readings.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(readings) { r in segment(r) }
                    if let stress {
                        Rectangle().fill(Hoy.sep).frame(width: 1, height: 30).padding(.horizontal, 2)
                        stressSegment(stress)
                    }
                }
                if let r = off.max(by: { $0.level < $1.level }) {
                    Text(reason(r)).hoyFont(13, relativeTo: .footnote).foregroundStyle(Hoy.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre el monitor de salud")
    }

    @ViewBuilder
    private func status(_ readings: [VitalReading], off: [VitalReading]) -> some View {
        if readings.isEmpty {
            Text("Tras tu primera noche").hoyFont(15, .medium).foregroundStyle(Hoy.t3)
        } else if readings.allSatisfy({ $0.level == .none }) {
            Text("Calibrando").hoyFont(15, .semibold).foregroundStyle(Hoy.t3)
        } else if off.isEmpty {
            Text("Todo en rango").hoyFont(15, .semibold).foregroundStyle(HoyLevel.buena.ink)
        } else if off.count == 1, let r = off.first {
            Text("\(r.short) \(high(r) ? "alta" : "baja")").hoyFont(15, .semibold)
                .foregroundStyle((HoyLevel(r.level) ?? .justa).ink).lineLimit(1).minimumScaleFactor(0.8)
        } else {
            let worst = off.map(\.level).max() ?? .orange
            Text("\(off.count) fuera de rango").hoyFont(15, .semibold).foregroundStyle((HoyLevel(worst) ?? .justa).ink)
        }
    }

    private func high(_ r: VitalReading) -> Bool {
        guard let range = r.range else { return false }
        return r.raw > (range.lowerBound + range.upperBound) / 2
    }

    private func reason(_ r: VitalReading) -> String {
        let side = high(r) ? "por encima" : "por debajo"
        return r.personal ? "\(r.short) \(side) de tu normal de 30 noches." : "\(r.short) \(side) del rango saludable."
    }

    private func segment(_ r: VitalReading) -> some View {
        let lv = HoyLevel(r.level)
        let bad = r.level == .orange || r.level == .red
        return VStack(spacing: 7) {
            Capsule().fill(lv?.mark ?? Hoy.fill2).frame(height: 6)
            Image(systemName: Self.icons[r.id] ?? r.icon).font(.system(size: 12))
                .foregroundStyle(bad ? (lv?.ink ?? Hoy.t3) : Hoy.t3)
                .frame(height: 14)
            if bad {
                Text(r.asDeviation ? "\(r.monitorValue)°" : "\(r.value)\(r.unit == "%" ? " %" : "")")
                    .hoyFont(12, .semibold, relativeTo: .caption1).foregroundStyle(lv?.ink ?? Hoy.t2)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, -3)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(r.short)
        .accessibilityValue(r.level == .none ? "calibrando" : r.chip)
    }

    private func stressSegment(_ v: Double) -> some View {
        let lv = HoyLevel(stress: v)
        return VStack(spacing: 7) {
            Capsule().fill(lv.mark).frame(height: 6)
            HStack(spacing: 4) {
                Image(systemName: "wind").font(.system(size: 12)).foregroundStyle(Hoy.t3)
                Text(Fmt.dec(v)).hoyFont(12.5, .semibold, relativeTo: .caption1).foregroundStyle(lv.ink)
                    .fixedSize()
            }
            .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estrés")
        .accessibilityValue(Fmt.dec(v))
    }
}

// MARK: - Ahora

/// «Ahora»: your pulse now (live, or the last minutes downloaded), a small curve of the last minutes and what you are
/// doing, when the app knows it.
struct HoyAhora: View {
    @EnvironmentObject var model: AppModel
    /// The last minutes of downloaded pulse (loaded by Hoy, see `AppModel.recentPulse`).
    let recent: [(ts: Int, hr: Int)]

    var body: some View {
        let live = isLive
        let points: [(Double, Double)] = live ? livePoints : recent.map { (Double($0.ts), Double($0.hr)) }
        let hr: Int? = live ? model.liveHR : recent.last?.hr
        let synced = model.lastSync.map { Int($0.timeIntervalSince1970) } ?? model.lastSampleTs
        VStack(spacing: 0) {
            if let hr {
                VStack(spacing: 10) {
                    HoySectionTitle(title: "Ahora") {
                        if let synced { Text("sync \(Fmt.time(synced))").hoyFont(15).foregroundStyle(Hoy.t3) }
                    }
                    HStack(spacing: 12) {
                        PulsingDot(active: live)
                        HoyValue(value: "\(hr)", unit: "lpm", size: 26)
                        if points.count >= 3 {
                            Sparkline(points: points.map { $0.1 }, color: Hoy.cor)
                                .frame(width: state == nil ? nil : 84, height: 24)
                                .frame(maxWidth: state == nil ? .infinity : nil)
                        }
                        if let state {
                            Rectangle().fill(Hoy.sep).frame(width: 1, height: 26)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(state.title).hoyFont(17, .semibold).foregroundStyle(Hoy.t1)
                                Text("desde \(Fmt.time(state.since))").hoyFont(15).foregroundStyle(Hoy.t2)
                            }
                            .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .background(Hoy.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var isLive: Bool {
        guard model.liveHR != nil, let at = model.lastLiveAt else { return false }
        return Date().timeIntervalSince(at) < 15
    }

    private var livePoints: [(Double, Double)] {
        let from = Date().addingTimeInterval(-600)
        return model.livePoints.filter { $0.date >= from }.map { ($0.date.timeIntervalSince1970, Double($0.hr)) }
    }

    /// What you are doing now, only when the app knows it.
    private var state: (title: String, since: Int)? {
        if let w = model.liveWorkout { return (w.sport, Int(w.start.timeIntervalSince1970)) }
        if let off = model.offWristSince { return ("Sin pulsera", Int(off.timeIntervalSince1970)) }
        return nil
    }

}

/// Small pink line of the last minutes, ending in a dot.
struct Sparkline: View {
    let points: [Double]
    var color: Color = Hoy.cor

    var body: some View {
        GeometryReader { g in
            let lo = (points.min() ?? 0) - 1, hi = (points.max() ?? 1) + 1
            let pts = points.enumerated().map { i, v in
                CGPoint(x: 3 + (g.size.width - 8) * CGFloat(i) / CGFloat(max(points.count - 1, 1)),
                        y: g.size.height - 2 - (g.size.height - 4) * CGFloat((v - lo) / max(hi - lo, 0.001)))
            }
            ZStack {
                SmoothPath(points: pts)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(color.opacity(0.22)).frame(width: 10, height: 10).position(last)
                    Circle().fill(color).frame(width: 5, height: 5).position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Catmull-Rom curve through points (smooth, passes through every point).
struct SmoothPath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        guard points.count > 1 else { return p }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }
}

/// Pink dot that breathes while the pulse is live.
struct PulsingDot: View {
    let active: Bool
    @State private var on = false

    var body: some View {
        ZStack {
            if active {
                Circle().fill(Hoy.cor.opacity(0.28)).frame(width: 16, height: 16)
                    .scaleEffect(on ? 1.15 : 0.6).opacity(on ? 0 : 1)
            }
            Circle().fill(active ? Hoy.cor : Hoy.cor.opacity(0.55)).frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            guard active else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
        }
        .accessibilityHidden(true)
    }
}

extension AppModel {
    /// The last 15 minutes of downloaded pulse, as 30-second means (for «Ahora» when there is no live pulse).
    func recentPulse() -> [(ts: Int, hr: Int)] {
        let now = Date()
        var buckets: [Int: (Int, Int)] = [:]
        for s in samples(from: now.addingTimeInterval(-15 * 60), to: now) {
            guard let hr = s.hr, hr > 25, !s.off else { continue }
            let b = s.ts / 30
            let v = buckets[b] ?? (0, 0)
            buckets[b] = (v.0 + hr, v.1 + 1)
        }
        return buckets.keys.sorted().map { (ts: $0 * 30, hr: buckets[$0]!.0 / max(buckets[$0]!.1, 1)) }
    }
}

/// A one-line notice in Hoy's style (the alarm that is set, bedtime in the evening).
struct HoyNotice: View {
    let icon: String
    let title: String
    let subtitle: String
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Hoy.sueno).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).hoyFont(17, .semibold).foregroundStyle(Hoy.t1)
                Text(subtitle).hoyFont(14).foregroundStyle(Hoy.t2).lineLimit(2)
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Hoy.t3)
            }
        }
        .hoyCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}
