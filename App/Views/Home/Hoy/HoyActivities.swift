import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoIntegrations

/// «Actividades»: steps and calories in the header, a row per sleep, nap, workout or breathing session, the 24-hour
/// strip and the two ways to add more.
struct HoyActivitiesBlock: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    let day: DaySummary
    /// Off inside «Actividades del día», where the totals sit above.
    var showHeader = true

    var body: some View {
        let items = model.activities(on: day)
        VStack(alignment: .leading, spacing: 0) {
            if showHeader {
                RouteLink(.hoy(.actividadesDia(day: day.day))) { header.contentShape(Rectangle()) }
                    .padding(.bottom, 6)
            }
            if items.isEmpty {
                Text("El sueño y los entrenos aparecen solos.")
                    .hoyFont(15).foregroundStyle(Hoy.t2).padding(.vertical, 10)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, a in
                if i > 0 { Rectangle().fill(Hoy.sep).frame(height: 1) }
                RouteLink(a.route) { HoyActivityRow(activity: a, model: model).contentShape(Rectangle()) }
            }
            DayStrip(day: day, items: items).padding(.top, 14)
            HStack(spacing: 10) {
                Button { router.open(.hoy(.anadirActividad)) } label: {
                    Label("Agregar actividad", systemImage: "plus")
                        .hoyFont(15, .semibold).foregroundStyle(Hoy.t1)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Hoy.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button { router.open(.hoy(.iniciarActividad)) } label: {
                    Label("Iniciar actividad", systemImage: "timer")
                        .hoyFont(15, .semibold).foregroundStyle(Hoy.act)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Hoy.act.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .hoyCard(padding: 16)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Actividades").hoyFont(20, .semibold, relativeTo: .title3).foregroundStyle(Hoy.t1)
                .accessibilityAddTraits(.isHeader)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Hoy.t3)
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let steps = day.steps, steps > 0 {
                    Image(systemName: "shoeprints.fill").font(.system(size: 12)).foregroundStyle(Hoy.act)
                    Text(HoyFmt.thousands(Double(steps))).hoyFont(15, .semibold).foregroundStyle(Hoy.t1)
                    Text("pasos").hoyFont(15).foregroundStyle(Hoy.t2)
                }
                if (day.steps ?? 0) > 0, day.kcal != nil {
                    Text("·").hoyFont(15).foregroundStyle(Hoy.t3)
                }
                if let kcal = day.kcal {
                    Image(systemName: "flame.fill").font(.system(size: 12)).foregroundStyle(Hoy.act)
                    Text(HoyFmt.thousands(kcal)).hoyFont(15, .semibold).foregroundStyle(Hoy.t1)
                    Text("kcal").hoyFont(15).foregroundStyle(Hoy.t2)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

extension DayActivity {
    var isBreathing: Bool {
        if case .workout(let w) = kind { return Breathwork.activityNames.contains(w.sport) }
        return false
    }

    /// Identity colour of the chip and of its stretch on the 24-hour strip.
    var hoyColor: Color {
        switch kind {
        case .sleep, .nap: return Hoy.sueno
        case .workout: return isBreathing ? Hoy.recarga : Hoy.act
        }
    }
}

/// Coloured chip with icon and duration, name and subtitle, start and end times.
struct HoyActivityRow: View {
    let activity: DayActivity
    let model: AppModel

    var body: some View {
        DSActivityRow(icon: icon, color: activity.hoyColor, duration: Fmt.hmm(Double(activity.end - activity.start) / 60),
                      title: title, subtitle: subtitle, start: Fmt.time(activity.start), end: Fmt.time(activity.end))
    }

    private var icon: String {
        switch activity.kind {
        case .sleep, .nap: return "moon.fill"
        case .workout: return activity.isBreathing ? "wind" : activity.icon
        }
    }

    private var title: String {
        if activity.isBreathing { return "Recuperación" }
        return activity.title
    }

    private var subtitle: String? {
        switch activity.kind {
        case .sleep:
            return "noche principal"
        case .nap:
            let s = model.daytimeSleeps(on: model.selectedDay).first { $0.start == activity.start }
            guard let s else { return nil }
            let parts: [(SleepStage, Double)] = [(.light, s.minutesLight), (.deep, s.minutesDeep), (.rem, s.minutesREM)]
            guard let top = parts.max(by: { $0.1 < $1.1 }), top.1 > 0 else { return nil }
            return "sobre todo \(Theme.stageName(top.0).lowercased())"
        case .workout(let w):
            if activity.isBreathing { return "respiración guiada" }
            if let m = w.distanceMeters, m > 50 {
                let km = m / 1000
                let minutes = Double(w.end - w.start) / 60
                let pace = minutes / km
                let paceText = pace.isFinite && pace < 20 ? String(format: " · %d:%02d /km", Int(pace), Int((pace - floor(pace)) * 60)) : ""
                return "\(Fmt.dec(km)) km\(paceText)"
            }
            return w.strain > 0 ? "esfuerzo \(Fmt.dec(w.strain))" : nil
        }
    }
}

/// The 24 hours on one strip: sleep by stage, the rest of the activities in their colour, and a marker at now.
struct DayStrip: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary
    let items: [DayActivity]

    /// 24 hours from 22:00 the evening before (or the hour you fell asleep, if earlier); if the day runs past
    /// that (an open cycle late at night), the window slides so it ends at the next hour.
    private var window: (start: Int, end: Int) {
        let cal = Calendar.current
        let base = DayKey.date(day.day).map { cal.startOfDay(for: $0) } ?? Date()
        var start = Int(base.timeIntervalSince1970) - 2 * 3600
        if let s = day.sleepStart, s < start { start = s - s % 3600 }
        let last = model.isOpenCycle(day) ? Int(Date().timeIntervalSince1970) : (day.cycleEnd ?? start)
        let end = max(start + 86_400, last - last % 3600 + 3600)
        return (end - 86_400, end)
    }

    var body: some View {
        let w = window
        DSDayStrip(start: w.start, end: w.end, segments: segments(w))
    }

    private typealias Segment = DSDayStrip.Segment

    private func segments(_ w: (start: Int, end: Int)) -> [Segment] {
        var out: [Segment] = []
        // The night by stage.
        if let s = model.sleep(for: day), !s.stages.isEmpty {
            var i = 0
            while i < s.stages.count {
                let st = s.stages[i]
                var j = i
                while j + 1 < s.stages.count && s.stages[j + 1] == st { j += 1 }
                out.append(Segment(id: "n\(i)", start: s.start + i * 60, end: s.start + (j + 1) * 60, color: Hoy.stage(st)))
                i = j + 1
            }
        }
        for a in items {
            if case .sleep = a.kind, !out.isEmpty { continue }
            let thin: Bool = { if case .workout = a.kind { return true } else { return false } }()
            out.append(Segment(id: a.id, start: max(a.start, w.start), end: min(a.end, w.end), color: a.hoyColor, thin: thin))
        }
        return out.filter { $0.end > w.start && $0.start < w.end }
    }
}
