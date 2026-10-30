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

    var planProgress: [WeeklyPlan.Progress] {
        let start = DayKey.shift(WeeklyPlan.weekStart(currentDayKey), days: -28)
        let workouts = (try? db.workouts(from: Int((DayKey.date(start) ?? Date()).timeIntervalSince1970),
                                         to: Int(Date().timeIntervalSince1970) + 86400)) ?? []
        let journal = ((try? db.allJournal()) ?? []).filter { $0.day >= start }
        return WeeklyPlan.progress(goals: planGoals, days: days.filter { $0.day >= start }, workouts: workouts, journal: journal,
                                   today: currentDayKey)
    }
}

enum PlanText {
    static func title(_ g: PlanGoal) -> String {
        switch g.kind {
        case .zonesLight: return "Tiempo en zonas de FC 1-3"
        case .zonesHard: return "Tiempo en zonas de FC 4-5"
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
        case .zonesLight, .zonesHard: return "heart.circle"
        case .strengthDays: return "dumbbell"
        case .avgStrain: return "flame"
        case .sleepHours: return "moon.zzz"
        case .regularity: return "clock.arrow.circlepath"
        case .bedtimeBefore: return "bed.double"
        case .steps: return "shoeprints.fill"
        case .activeDays: return "figure.run"
        case .habitYes, .habitNo: return "book.closed"
        }
    }

    static func habit(_ g: PlanGoal) -> String {
        (g.habit.map { JournalCatalog.label($0) } ?? "Hábito").replacingOccurrences(of: "whoop:", with: "")
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

/// "Plan semanal": goals for this week with their progress.
struct WeeklyPlanView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing = false

    var body: some View {
        let progress = model.planProgress
        DetailScreen(title: "Detalles del plan") {
            Caps("Plan actual", size: 11, color: Theme.secondary, weight: .semibold)
            Text("Tu semana").scaledFont(28, weight: .bold, relativeTo: .title1).foregroundStyle(.white)
            Text("Metas de lunes a domingo, comparadas con tu media de las 4 semanas anteriores. Ajústalas para que te supongan un reto razonable.")
                .font(.subheadline).foregroundStyle(Color(white: 0.82))
            HStack(spacing: 14) {
                legend(Theme.worse, "Deficiente")
                legend(Color(white: 0.7), "Suficiente")
                legend(Theme.better, "Óptimo")
            }
            if progress.isEmpty {
                EmptyState(icon: "target", title: "Sin metas todavía", message: "Elige qué quieres mejorar esta semana: esfuerzo, sueño, pasos o hábitos.")
            }
            ForEach(["Esfuerzo y zonas", "Sueño", "Pasos y actividad", "Hábitos"], id: \.self) { group in
                let items = progress.filter { $0.goal.kind.group == group }
                if !items.isEmpty {
                    SectionHeading(text: "\(group) (\(items.count))", trailing: "Editar") { editing = true }
                    ForEach(items, id: \.goal.id) { GoalCard(progress: $0) }
                }
            }
            Button(progress.isEmpty ? "Crear mi plan" : "Editar el plan") { editing = true }
                .buttonStyle(progress.isEmpty ? AnyButtonStyle(PrimaryCapsuleStyle()) : AnyButtonStyle(SecondaryCapsuleStyle()))
                .padding(.top, 8)
        }
        .sheet(isPresented: $editing) { PlanEditor(goals: model.planGoals) }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(c).frame(width: 14, height: 4)
            Text(t).font(.caption).foregroundStyle(Theme.secondary)
        }
    }
}

struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ s: S) { make = { AnyView(s.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

struct GoalCard: View {
    let progress: WeeklyPlan.Progress

    var body: some View {
        let g = progress.goal
        let color = [Theme.worse, Color(white: 0.7), Theme.better][progress.level]
        PCard {
            HStack(spacing: 10) {
                Image(systemName: PlanText.icon(g.kind)).foregroundStyle(Theme.secondary)
                Caps(PlanText.title(g), size: 12)
                Spacer()
                if progress.met { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.better) }
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(PlanText.value(g.kind, progress.value)).scaledFont(26, weight: .bold, relativeTo: .title1).monospacedDigit().foregroundStyle(.white)
                    Caps("Esta semana", size: 9, color: Theme.secondary, weight: .semibold)
                    if let p = progress.previous {
                        Text("Media 4 semanas: \(PlanText.value(g.kind, p))").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right.2").font(.title3.bold()).foregroundStyle(Theme.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(g.kind == .bedtimeBefore ? "5 noches" : PlanText.target(g)).scaledFont(22, weight: .bold, relativeTo: .title1).monospacedDigit().foregroundStyle(.white)
                    Caps(g.kind == .habitNo ? "Límite semanal" : "Objetivo semanal", size: 9, color: Theme.secondary, weight: .semibold)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(color).frame(width: max(6, geo.size.width * progress.fraction))
                }
            }
            .frame(height: 6)
        }
    }
}

struct PlanEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var goals: [PlanGoal]

    var body: some View {
        NavigationStack {
            List {
                ForEach($goals) { $g in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(PlanText.title(g), systemImage: PlanText.icon(g.kind)).font(.subheadline.bold())
                        Stepper(value: $g.target, in: PlanText.range(g.kind), step: PlanText.step(g.kind)) {
                            Text(g.kind == .bedtimeBefore ? "Hora: \(PlanText.clock(g.target))" : "Objetivo: \(PlanText.value(g.kind, g.target))")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
                .onDelete { goals.remove(atOffsets: $0) }
                Section("Añadir meta") {
                    ForEach(PlanGoal.Kind.allCases.filter { $0 != .habitYes && $0 != .habitNo }, id: \.self) { k in
                        if !goals.contains(where: { $0.kind == k }) {
                            Button {
                                goals.append(PlanGoal(kind: k, target: PlanGoal.defaultTarget(k)))
                            } label: {
                                Label(PlanText.title(PlanGoal(kind: k, target: PlanGoal.defaultTarget(k))), systemImage: PlanText.icon(k))
                            }
                        }
                    }
                    Menu {
                        ForEach(JournalCatalog.items) { item in
                            Button("\(item.label): al menos N días") { goals.append(PlanGoal(kind: .habitYes, target: 5, habit: item.key)) }
                            Button("\(item.label): como mucho N días") { goals.append(PlanGoal(kind: .habitNo, target: 1, habit: item.key)) }
                        }
                    } label: {
                        Label("Hábito del diario…", systemImage: "book.closed")
                    }
                }
            }
            .navigationTitle("Editar plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        model.savePlan(goals)
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
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
