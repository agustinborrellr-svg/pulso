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
                RouteLink(.metric(.bateria)) {
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
                RouteLink(.metric(.recarga)) { recarga(prev) }
                RouteLink(.sueno(.noche(day: nil))) { sueno(prev) }
                RouteLink(.metric(.esfuerzo)) { esfuerzo(prev) }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 16)
            .padding(.bottom, 14)
            Rectangle().fill(Hoy.sep).frame(height: 1)
            RouteLink(.hoy(.monitor)) { HoyMonitor(day: day) }
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
    var title = "Monitor de salud"
    var chevron = true
    var showStress = true

    static let order = ["hrv", "rhr", "resp", "spo2", "temp"]
    static let icons = ["hrv": "waveform.path.ecg", "rhr": "heart.fill", "resp": "lungs.fill", "spo2": "drop.fill",
                        "temp": "thermometer.medium"]

    var body: some View {
        let all = model.vitalReadings()
        let readings = Self.order.compactMap { id in all.first { $0.id == id } }
        let off = readings.filter { $0.level == .orange || $0.level == .red }
        let stress = day?.stressPoints.last?.v
        let st = status(readings, off: off)
        DSSegmentMonitor(title: title, status: st.0, statusColor: st.1, chevron: chevron,
                         segments: readings.map(segment),
                         extra: showStress ? stress.map(stressSegment) : nil,
                         note: off.max(by: { $0.level < $1.level }).map(reason))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Abre el monitor de salud")
    }

    private func status(_ readings: [VitalReading], off: [VitalReading]) -> (String, Color) {
        if readings.isEmpty { return ("Tras tu primera noche", Hoy.t3) }
        if readings.allSatisfy({ $0.level == .none }) { return ("Calibrando", Hoy.t3) }
        if off.isEmpty { return ("Todo en rango", HoyLevel.buena.ink) }
        if off.count == 1, let r = off.first {
            return ("\(r.short) \(high(r) ? "alta" : "baja")", (HoyLevel(r.level) ?? .justa).ink)
        }
        let worst = off.map(\.level).max() ?? .orange
        return ("\(off.count) fuera de rango", (HoyLevel(worst) ?? .justa).ink)
    }

    private func high(_ r: VitalReading) -> Bool {
        guard let range = r.range else { return false }
        return r.raw > (range.lowerBound + range.upperBound) / 2
    }

    private func reason(_ r: VitalReading) -> String {
        let side = high(r) ? "por encima" : "por debajo"
        return r.personal ? "\(r.short) \(side) de tu normal de 30 noches." : "\(r.short) \(side) del rango saludable."
    }

    private func segment(_ r: VitalReading) -> DSMonitorSegment {
        let lv = HoyLevel(r.level)
        let bad = r.level == .orange || r.level == .red
        return DSMonitorSegment(id: r.id, icon: Self.icons[r.id] ?? r.icon, color: lv?.mark ?? Hoy.fill2,
                                iconColor: bad ? (lv?.ink ?? Hoy.t3) : Hoy.t3,
                                value: bad ? (r.asDeviation ? "\(r.monitorValue)°" : "\(r.value)\(r.unit == "%" ? " %" : "")") : nil,
                                valueColor: lv?.ink ?? Hoy.t2,
                                accessibilityLabel: r.short,
                                accessibilityValue: r.level == .none ? "calibrando" : r.chip)
    }

    private func stressSegment(_ v: Double) -> DSMonitorSegment {
        let lv = HoyLevel(stress: v)
        return DSMonitorSegment(id: "stress", icon: "wind", color: lv.mark, value: Fmt.dec(v), valueColor: lv.ink,
                                accessibilityLabel: "Estrés", accessibilityValue: Fmt.dec(v))
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
                    DSNowCard(hr: hr, live: live, points: points.map { $0.1 }, state: state?.title,
                              since: state.map { Fmt.time($0.since) })
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
