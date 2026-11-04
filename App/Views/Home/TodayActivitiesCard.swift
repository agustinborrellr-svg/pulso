import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoIntegrations

/// One thing you did in the day: the night, a nap or daytime sleep, or any activity (a run, the gym, intimacy…).
struct DayActivity: Identifiable {
    enum Kind {
        case sleep
        case nap
        case workout(Workout)
    }

    let id: String
    let kind: Kind
    let start: Int
    let end: Int
    let title: String
    let icon: String
    /// Minutes asleep for a sleep, minutes long for an activity.
    let minutes: Double
    /// Sleep shows its hours asleep ("6:37"); an activity its strain ("8,4"), as on the strain scale.
    let badge: String
    let color: Color
}

extension AppModel {
    /// The day's sleep, naps and activities, in the order they happened.
    func activities(on day: DaySummary) -> [DayActivity] {
        var out: [DayActivity] = []
        if let a = day.sleepStart, let b = day.sleepEnd {
            let asleep = day.sleepMinutes ?? Double(b - a) / 60
            out.append(DayActivity(id: "sleep-\(a)", kind: .sleep, start: a, end: b, title: "Sueño", icon: "moon.fill",
                                   minutes: asleep, badge: Fmt.hmm(asleep), color: Theme.sleep))
        }
        for s in daytimeSleeps(on: day.day) where s.start != day.sleepStart {
            let asleep = s.minutesLight + s.minutesDeep + s.minutesREM
            out.append(DayActivity(id: "nap-\(s.start)", kind: .nap, start: s.start, end: s.end, title: s.isNap ? "Siesta" : "Sueño de día",
                                   icon: "moon.zzz.fill", minutes: asleep, badge: Fmt.hmm(asleep), color: Theme.sleep))
        }
        for w in workouts(for: day) {
            // A breathing session shows how long it lasted, like the sleeps; everything else its strain.
            let breathing = Breathwork.activityNames.contains(w.sport)
            let minutes = Double(w.end - w.start) / 60
            out.append(DayActivity(id: "workout-\(w.start)", kind: .workout(w), start: w.start, end: w.end, title: w.sport,
                                   icon: SportCatalog.named(w.sport).symbol, minutes: minutes,
                                   badge: breathing ? Fmt.hmm(minutes) : Fmt.dec(w.strain), color: breathing ? Theme.link : Theme.strain))
        }
        return out.sorted { $0.start < $1.start }
    }
}

/// «Actividades de hoy»: what the day held so far, and the two ways to add more.
struct TodayActivitiesCard: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary
    @State private var adding = false
    @State private var starting = false

    var body: some View {
        let items = model.activities(on: day)
        PCard {
            HStack {
                Caps(day.day == model.currentDayKey ? "Actividades de hoy" : "Actividades · \(Fmt.dayTitle(day.day))")
                Spacer()
                NavigationLink { DayActivitiesView(day: day) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3.weight(.semibold)).foregroundStyle(Theme.secondary)
                }
                .accessibilityLabel("Ver todas")
            }
            if items.isEmpty {
                Text("Aún no hay nada: el sueño y los entrenos aparecen solos, y lo demás puedes añadirlo.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            ForEach(items) { a in
                NavigationLink { DayActivityDestination(activity: a) } label: { DayActivityRow(activity: a) }
                    .buttonStyle(.plain)
            }
            DayActivityButtons(adding: $adding, starting: $starting)
                .padding(.top, items.isEmpty ? 0 : 8)
        }
        .sheet(isPresented: $adding) { AddActivitySheet() }
        .sheet(isPresented: $starting) { StartActivitySheet(isPresented: $starting) }
    }
}

struct DayActivityButtons: View {
    @Binding var adding: Bool
    @Binding var starting: Bool

    var body: some View {
        HStack(spacing: 10) {
            button("Agregar actividad", icon: "plus") { adding = true }
            button("Iniciar actividad", icon: "stopwatch") { starting = true }
        }
    }

    private func button(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.headline)
                Caps(title, size: 12).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Coloured badge with the icon and the hours or strain, the name, and when it started and ended.
struct DayActivityRow: View {
    let activity: DayActivity

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: activity.icon).font(.title2)
                Text(activity.badge).scaledFont(24, weight: .bold, relativeTo: .title2).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(.white)
            .frame(width: 124, height: 60)
            .background(activity.color.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Caps(activity.title, size: 14).lineLimit(2).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 14) {
                Text(Fmt.time(activity.start))
                Text(Fmt.time(activity.end))
            }
            .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.secondary)
            VStack(spacing: 0) {
                Circle().fill(.white).frame(width: 5, height: 5)
                Capsule().fill(activity.color).frame(width: 3)
                Circle().fill(.white).frame(width: 5, height: 5)
            }
            .frame(height: 46)
        }
        .padding(10)
        .padding(.trailing, 4)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct DayActivityDestination: View {
    @EnvironmentObject var model: AppModel
    let activity: DayActivity

    var body: some View {
        switch activity.kind {
        case .sleep, .nap: SleepDetailView()
        case .workout(let w):
            if let r = model.breathworkRecord(for: w) {
                BreathworkResultView(record: r)
            } else {
                WorkoutDetailView(workout: w)
            }
        }
    }
}

/// The card opened up: totals of the day, every activity and the same two buttons.
struct DayActivitiesView: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary
    @State private var adding = false
    @State private var starting = false

    var body: some View {
        let items = model.activities(on: day)
        let slept = items.filter { if case .workout = $0.kind { return false } else { return true } }
        let active = items.filter { if case .workout = $0.kind { return true } else { return false } }
        DetailScreen(title: "Actividades", subtitle: Fmt.dayTitle(day.day)) {
            PCard {
                HStack(alignment: .top) {
                    total("Dormido", Fmt.hmm(slept.isEmpty ? nil : slept.reduce(0) { $0 + $1.minutes }))
                    total("Actividades", "\(active.count)")
                    total("Activo", Fmt.hmm(active.isEmpty ? nil : active.reduce(0) { $0 + $1.minutes }))
                    total("Esfuerzo", Fmt.dec(day.strain))
                }
            }
            if items.isEmpty {
                EmptyState(icon: "figure.walk", title: "Sin actividades",
                           message: "El sueño y los entrenos aparecen solos. Lo demás puedes añadirlo o empezarlo aquí.")
            }
            ForEach(items) { a in
                NavigationLink { DayActivityDestination(activity: a) } label: { DayActivityRow(activity: a) }
                    .buttonStyle(.plain)
            }
            DayActivityButtons(adding: $adding, starting: $starting)
        }
        .sheet(isPresented: $adding) { AddActivitySheet() }
        .sheet(isPresented: $starting) { StartActivitySheet(isPresented: $starting) }
    }

    private func total(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Caps(title, size: 9.5, color: Theme.secondary, weight: .semibold).lineLimit(1).minimumScaleFactor(0.7)
            Text(value).scaledFont(20, weight: .bold, relativeTo: .body).monospacedDigit().foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
