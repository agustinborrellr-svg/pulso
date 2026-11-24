import SwiftUI
import PulsoStore
import PulsoAnalytics

extension AppModel {
    static let planKey = "weeklyPlan.goals"

    var planGoals: [PlanGoal] { db.get([PlanGoal].self, for: Self.planKey) ?? [] }

    func savePlan(_ goals: [PlanGoal]) {
        try? db.set(goals, for: Self.planKey)
        objectWillChange.send()
    }

    var planProgress: [WeeklyPlan.Progress] { planProgress(for: planGoals) }

    /// Progress of any list of goals (also the suggestions of an empty plan, for their 4-week mean).
    func planProgress(for goals: [PlanGoal]) -> [WeeklyPlan.Progress] {
        let start = DayKey.shift(WeeklyPlan.weekStart(currentDayKey), days: -28)
        let workouts = (try? db.workouts(from: Int((DayKey.date(start) ?? Date()).timeIntervalSince1970),
                                         to: Int(Date().timeIntervalSince1970) + 86400)) ?? []
        let journal = ((try? db.allJournal()) ?? []).filter { $0.day >= start }
        return WeeklyPlan.progress(goals: goals, days: days.filter { $0.day >= start }, workouts: workouts, journal: journal,
                                   today: currentDayKey)
    }
}

enum PlanText {
    static func title(_ g: PlanGoal) -> String {
        switch g.kind {
        case .zonesLight: return "Zonas de FC 1-3"
        case .zonesHard: return "Zonas de FC 4-5"
        case .strengthDays: return "Días de fuerza"
        case .avgStrain: return "Esfuerzo medio"
        case .sleepHours: return "Horas de sueño (media)"
        case .regularity: return "Regularidad del sueño"
        case .bedtimeBefore: return "Dormido antes de las \(clock(g.target))"
        case .steps: return "Pasos al día (media)"
        case .activeDays: return "Días activos (esfuerzo ≥ 10)"
        case .habitYes: return "\(habit(g)): al menos"
        case .habitNo: return "\(habit(g)): como mucho"
        }
    }

    static func icon(_ k: PlanGoal.Kind) -> String {
        switch k {
        case .zonesLight, .zonesHard: return "heart.fill"
        case .strengthDays: return "dumbbell"
        case .avgStrain: return "flame"
        case .sleepHours: return "moon.fill"
        case .regularity: return "clock.arrow.circlepath"
        case .bedtimeBefore: return "bed.double"
        case .steps: return "shoeprints.fill"
        case .activeDays: return "figure.run"
        case .habitYes, .habitNo: return "book.closed"
        }
    }

    static func habit(_ g: PlanGoal) -> String {
        g.habit.map { JournalCatalog.label($0) } ?? "Hábito"
    }

    static func clock(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()) % (24 * 60)
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    static func value(_ k: PlanGoal.Kind, _ v: Double?) -> String {
        guard let v else { return "–" }
        switch k {
        case .zonesLight, .zonesHard, .sleepHours: return Fmt.hmm(v)
        case .strengthDays, .activeDays, .habitYes, .habitNo, .bedtimeBefore: return "\(Int(v.rounded())) d"
        case .avgStrain: return Fmt.dec(v)
        case .regularity: return "\(Int(v.rounded())) %"
        case .steps: return Fmt.thousands(v)
        }
    }

    static func target(_ g: PlanGoal) -> String {
        switch g.kind {
        case .bedtimeBefore: return "5 d"
        default: return value(g.kind, g.target)
        }
    }

    static func step(_ k: PlanGoal.Kind) -> Double {
        switch k {
        case .zonesLight, .zonesHard, .sleepHours, .bedtimeBefore: return 15
        case .avgStrain: return 0.5
        case .regularity: return 5
        case .steps: return 500
        default: return 1
        }
    }

    static func range(_ k: PlanGoal.Kind) -> ClosedRange<Double> {
        switch k {
        case .zonesLight: return 15...900
        case .zonesHard: return 5...300
        case .strengthDays, .activeDays, .habitYes: return 1...7
        case .habitNo: return 0...7
        case .avgStrain: return 4...19
        case .sleepHours: return 5 * 60...10 * 60
        case .regularity: return 50...100
        case .bedtimeBefore: return 21 * 60...26 * 60
        case .steps: return 2000...25000
        }
    }
}

/// 40 · Plan semanal (42 when there are no goals): the week with today's place in it, and each goal with its value /
/// target, a bar, today's pace mark (day/7), the 4-week mean and its status. The plan's rules are unchanged: the
/// status is the plan's level (Por detrás < 50 %, Al límite < 100 %, Al ritmo = met).
struct WeeklyPlanView: View {
    @EnvironmentObject var model: AppModel
    /// The empty state even with goals (screenshot run).
    var forceEmpty = false
    @State private var editing = false

    var body: some View {
        let progress = forceEmpty ? [] : model.planProgress
        DSScreen("Plan semanal", back: "Actividad") {
            if !progress.isEmpty {
                Button("Editar") { editing = true }
                    .buttonStyle(DSButtonStyle(size: .small, gray: true))
            }
        } content: {
            if progress.isEmpty {
                empty
            } else {
                weekCard
                ForEach(["Esfuerzo y zonas", "Sueño", "Pasos y actividad", "Hábitos"], id: \.self) { group in
                    let items = progress.filter { $0.goal.kind.group == group }
                    if !items.isEmpty {
                        DSSectionHeader(group, note: "\(items.count)")
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.goal.id) { i, p in
                                if i > 0 { DSDivider() }
                                GoalRow(progress: p, pace: Double(dayIndex) / 7)
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                    }
                }
            }
        }
        .sheet(isPresented: $editing) { PlanEditor(goals: model.planGoals).dsSheet() }
    }

    private var weekStart: String { WeeklyPlan.weekStart(model.currentDayKey) }

    /// 1 = Monday … 7 = Sunday.
    private var dayIndex: Int {
        guard let a = DayKey.date(weekStart), let b = DayKey.date(model.currentDayKey) else { return 1 }
        return min(7, max(1, (Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0) + 1))
    }

    private var weekCard: some View {
        let end = DayKey.shift(weekStart, days: 6)
        let letters = ["L", "M", "X", "J", "V", "S", "D"]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(DSFmt.dayMonth(weekStart).split(separator: " ").first ?? "") – \(DSFmt.dayMonth(end))")
                        .dsFont(20, .semibold).foregroundStyle(DS.t1)
                    Text("día \(dayIndex) de 7").dsFont(15).foregroundStyle(DS.t2)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(letters[i]).dsFont(14, .semibold)
                            .foregroundStyle(i + 1 == dayIndex ? DS.bg : (i + 1 < dayIndex ? DS.t2 : DS.t3))
                            .frame(width: 27, height: 34)
                            .background(i + 1 == dayIndex ? DS.t1 : DS.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { l in
                    HStack(spacing: 5) {
                        DSDot(color: ActPlan.level(l).mark)
                        Text(ActPlan.word(l))
                    }
                }
                HStack(spacing: 5) {
                    Capsule().fill(DS.t1).frame(width: 2.5, height: 13)
                    Text("ritmo de hoy")
                }
            }
            .dsFont(13).foregroundStyle(DS.t2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .dsCard(padding: 14)
    }

    /// 42: no goals yet, «Crear mi plan» and three starting goals with your own 4-week mean.
    private var empty: some View {
        let suggestions = [PlanGoal(kind: .steps, target: PlanGoal.defaultTarget(.steps)),
                           PlanGoal(kind: .zonesLight, target: PlanGoal.defaultTarget(.zonesLight)),
                           PlanGoal(kind: .sleepHours, target: PlanGoal.defaultTarget(.sleepHours))]
        let progress = model.planProgress(for: suggestions)
        return Group {
            VStack(spacing: 10) {
                Image(systemName: "target").font(.system(size: 34, weight: .regular)).foregroundStyle(DS.t2)
                Text("Sin metas todavía").dsFont(24, .bold, relativeTo: .title2).foregroundStyle(DS.t1)
                Text("Elige qué mejorar esta semana: esfuerzo, sueño, pasos o hábitos.")
                    .dsFont(16).foregroundStyle(DS.t2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
            .padding(.bottom, 18)
            Button { editing = true } label: {
                Label("Crear mi plan", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(DSButtonStyle(tint: DS.act, size: .xl, fullWidth: true))
            DSSectionHeader("Para empezar", note: "según tus 4 semanas")
            VStack(spacing: 0) {
                ForEach(Array(progress.enumerated()), id: \.offset) { i, p in
                    if i > 0 { DSDivider(inset: 36) }
                    HStack(spacing: 12) {
                        Image(systemName: PlanText.icon(p.goal.kind)).font(.system(size: 15)).foregroundStyle(DS.t2).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(PlanText.title(p.goal).replacingOccurrences(of: " (media)", with: "")).dsFont(17, .semibold).foregroundStyle(DS.t1)
                            if let prev = p.previous {
                                Text("tu media \(PlanText.value(p.goal.kind, prev))").dsFont(15).foregroundStyle(DS.t2)
                            }
                        }
                        Spacer(minLength: 6)
                        Text(PlanText.target(p.goal) + (p.goal.kind == .zonesLight ? " / sem." : "")).dsFont(17).foregroundStyle(DS.t2)
                        Button { model.savePlan(model.planGoals + [p.goal]) } label: {
                            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(DS.t1)
                                .frame(width: 30, height: 30).background(DSLevel.buena.mark, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Añadir \(PlanText.title(p.goal))")
                    }
                    .frame(minHeight: 62)
                }
            }
            .padding(.horizontal, 14)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        }
    }
}

/// One goal: icon, name, value / target, the bar with today's pace mark, the 4-week mean and the status word.
private struct GoalRow: View {
    let progress: WeeklyPlan.Progress
    let pace: Double

    var body: some View {
        let g = progress.goal
        let lv = ActPlan.level(progress.level)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: PlanText.icon(g.kind)).font(.system(size: 14)).foregroundStyle(DS.t2).frame(width: 22)
                Text(PlanText.title(g)).dsFont(17, .semibold).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 6)
                Text(PlanText.value(g.kind, progress.value)).dsFont(20, .semibold).foregroundStyle(DS.t1)
                Text("/ \(g.kind == .bedtimeBefore ? "5 noches" : PlanText.target(g))").dsFont(15).foregroundStyle(DS.t3)
                    .lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill)
                    Capsule().fill(lv.mark).frame(width: progress.fraction > 0 ? max(6, geo.size.width * progress.fraction) : 0)
                    if g.kind != .habitNo {
                        Capsule().fill(DS.t1).frame(width: 2.5, height: 16).offset(x: geo.size.width * pace - 1.25)
                    }
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 16)
            HStack {
                if let p = progress.previous {
                    Text("media 4 semanas \(PlanText.value(g.kind, p))").dsFont(15).foregroundStyle(DS.t3)
                }
                Spacer()
                Text(ActPlan.word(progress.level)).dsFont(15, .semibold).foregroundStyle(lv.ink)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// 41 · Editar plan (sheet): a stepper per goal, «Añadir meta» with the plan's goal types and the journal habits;
/// swipe a goal left to remove it.
struct PlanEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var goals: [PlanGoal]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Editar plan").dsFont(17, .semibold, relativeTo: .headline).foregroundStyle(DS.t1)
                HStack {
                    Button("Cancelar") { dismiss() }.foregroundStyle(DS.t1)
                    Spacer()
                    Button("Guardar") {
                        model.savePlan(goals)
                        dismiss()
                    }
                    .fontWeight(.semibold).foregroundStyle(DS.act)
                }
                .dsFont(17)
                .buttonStyle(.plain)
            }
            .frame(height: 50)
            .padding(.top, 14)
            .padding(.horizontal, DS.gutter)
            List {
                Section {
                    ForEach($goals) { $g in
                        HStack(spacing: 12) {
                            Image(systemName: PlanText.icon(g.kind)).font(.system(size: 15)).foregroundStyle(DS.t2).frame(width: 24)
                            Text(g.kind == .bedtimeBefore ? "Dormido antes de…" : PlanText.title(g)).dsFont(17).foregroundStyle(DS.t1)
                                .lineLimit(2).minimumScaleFactor(0.85)
                            Spacer(minLength: 6)
                            stepper($g)
                        }
                        .listRowBackground(DS.fill)
                    }
                    .onDelete { goals.remove(atOffsets: $0) }
                } header: {
                    Text("Tus metas").dsFont(14, .semibold).foregroundStyle(DS.t2).textCase(nil)
                }
                Section {
                    ForEach(PlanGoal.Kind.allCases.filter { $0 != .habitYes && $0 != .habitNo && !goals.map(\.kind).contains($0) }, id: \.self) { k in
                        Button { goals.append(PlanGoal(kind: k, target: PlanGoal.defaultTarget(k))) } label: {
                            addLabel(PlanText.title(PlanGoal(kind: k, target: PlanGoal.defaultTarget(k))))
                        }
                        .listRowBackground(DS.fill)
                    }
                    Menu {
                        ForEach(JournalCatalog.items) { item in
                            Button("\(item.label): al menos N días") { goals.append(PlanGoal(kind: .habitYes, target: 5, habit: item.key)) }
                            Button("\(item.label): como mucho N días") { goals.append(PlanGoal(kind: .habitNo, target: 1, habit: item.key)) }
                        }
                    } label: {
                        addLabel("Hábito del diario…")
                    }
                    .listRowBackground(DS.fill)
                } header: {
                    Text("Añadir meta").dsFont(14, .semibold).foregroundStyle(DS.t2).textCase(nil)
                } footer: {
                    Text("Desliza una meta a la izquierda para quitarla.").dsFont(13).foregroundStyle(DS.t3)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .background(DS.card.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func addLabel(_ t: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(DS.t1)
                .frame(width: 26, height: 26).background(DSLevel.buena.mark, in: Circle())
            Text(t).dsFont(17).foregroundStyle(DS.t1)
        }
        .frame(minHeight: 44)
    }

    private func stepper(_ g: Binding<PlanGoal>) -> some View {
        let k = g.wrappedValue.kind
        let r = PlanText.range(k), step = PlanText.step(k)
        return HStack(spacing: 0) {
            Button { g.wrappedValue.target = max(r.lowerBound, g.wrappedValue.target - step) } label: {
                Image(systemName: "minus").frame(width: 40, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Menos")
            Text(k == .bedtimeBefore ? PlanText.clock(g.wrappedValue.target) : PlanText.value(k, g.wrappedValue.target))
                .dsFont(16, .semibold).frame(minWidth: 58)
                .lineLimit(1).minimumScaleFactor(0.7)
            Button { g.wrappedValue.target = min(r.upperBound, g.wrappedValue.target + step) } label: {
                Image(systemName: "plus").frame(width: 40, height: 36).contentShape(Rectangle())
            }
            .accessibilityLabel("Más")
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(DS.t1)
        .buttonStyle(.borderless)
        .background(DS.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Small summary on Inicio.
struct PlanSummaryCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let p = model.planProgress
        NavigationLink { WeeklyPlanView() } label: {
            PCard {
                CardHeader(title: "Plan semanal", chevron: true)
                if p.isEmpty {
                    Text("Ponte metas para esta semana: esfuerzo, sueño, pasos o hábitos.").font(.subheadline).foregroundStyle(Theme.secondary)
                } else {
                    let met = p.filter(\.met).count
                    Text("\(met) de \(p.count) metas cumplidas").font(.headline).foregroundStyle(.white)
                    HStack(spacing: 4) {
                        ForEach(p, id: \.goal.id) { g in
                            Capsule().fill([Theme.worse, Color(white: 0.7), Theme.better][g.level]).frame(height: 5)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
