import AppIntents
import PulsoStore
import PulsoAnalytics
import PulsoIntegrations

/// Siri / Shortcuts / Spotlight actions. They run inside the app process.
struct RecoveryIntent: AppIntent {
    static var title: LocalizedStringResource = "Ver mi recuperación"
    static var description = IntentDescription("Dice tu recuperación, el sueño de anoche y el esfuerzo recomendado.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let d = model.today ?? model.days.last else {
            return .result(dialog: "Todavía no tengo datos. Sincroniza la pulsera.")
        }
        var parts: [String] = []
        if let r = d.recovery { parts.append("Tu recuperación es del \(Int(r)) por ciento") }
        if let s = d.sleepMinutes { parts.append("dormiste \(Int(s) / 60) horas y \(Int(s) % 60) minutos") }
        if d.recovery != nil {
            let a = model.coachAdvice(for: d)
            parts.append("esfuerzo recomendado entre \(Int(a.strainTarget.lowerBound)) y \(Int(a.strainTarget.upperBound))")
        }
        return .result(dialog: IntentDialog(stringLiteral: parts.isEmpty ? "Aún estoy calculando tu día." : parts.joined(separator: ", ") + "."))
    }
}

enum SportOption: String, AppEnum {
    case carrera, ciclismo, fuerza, caminata, natacion, hiit, yoga, padel, actividad

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Deporte"
    static var caseDisplayRepresentations: [SportOption: DisplayRepresentation] = [
        .carrera: "Carrera", .ciclismo: "Ciclismo", .fuerza: "Fuerza", .caminata: "Caminata", .natacion: "Natación",
        .hiit: "HIIT", .yoga: "Yoga", .padel: "Pádel", .actividad: "Actividad",
    ]

    var sportName: String {
        switch self {
        case .carrera: return "Carrera"
        case .ciclismo: return "Ciclismo"
        case .fuerza: return "Fuerza"
        case .caminata: return "Caminata"
        case .natacion: return "Natación"
        case .hiit: return "HIIT"
        case .yoga: return "Yoga"
        case .padel: return "Pádel"
        case .actividad: return "Actividad"
        }
    }
}

struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Empezar entreno"
    static var description = IntentDescription("Empieza a registrar un entreno con la pulsera.")

    @Parameter(title: "Deporte", default: .carrera)
    var sport: SportOption

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard model.liveWorkout == nil else { return .result(dialog: "Ya hay un entreno en marcha.") }
        model.startWorkout(sport: sport.sportName)
        model.strap.buzz(loops: 2)
        return .result(dialog: IntentDialog(stringLiteral: "Entreno de \(sport.sportName.lowercased()) iniciado."))
    }
}

struct StopWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Terminar entreno"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let w = model.liveWorkout else { return .result(dialog: "No hay ningún entreno en marcha.") }
        let strain = Strain.score(load: w.load)
        model.stopWorkout(save: true)
        return .result(dialog: IntentDialog(stringLiteral: String(format: "Entreno guardado. Esfuerzo %.1f, %d kilocalorías.", strain, Int(w.kcal))))
    }
}

struct BuzzStrapIntent: AppIntent {
    static var title: LocalizedStringResource = "Hacer vibrar la pulsera"

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.strap.buzz(loops: 2)
        return .result()
    }
}

struct SyncIntent: AppIntent {
    static var title: LocalizedStringResource = "Sincronizar la pulsera"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.shared.connect()
        AppModel.shared.syncNow()
        return .result(dialog: "Sincronizando.")
    }
}

struct BreatheIntent: AppIntent {
    static var title: LocalizedStringResource = "Respiración guiada con la pulsera"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.shared.startBreathingGuide()
        return .result(dialog: "Sigue la vibración: un toque para inspirar, dos para espirar.")
    }
}

struct PulsoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecoveryIntent(), phrases: ["¿Cómo está mi recuperación en \(.applicationName)?",
                                                        "Mi recuperación en \(.applicationName)"],
                    shortTitle: "Recuperación", systemImageName: "circle.circle")
        AppShortcut(intent: StartWorkoutIntent(), phrases: ["Empieza un entreno en \(.applicationName)",
                                                            "Empezar \(\.$sport) en \(.applicationName)"],
                    shortTitle: "Empezar entreno", systemImageName: "figure.run")
        AppShortcut(intent: StopWorkoutIntent(), phrases: ["Termina el entreno en \(.applicationName)"],
                    shortTitle: "Terminar entreno", systemImageName: "stop.circle")
        AppShortcut(intent: BreatheIntent(), phrases: ["Respirar con \(.applicationName)"],
                    shortTitle: "Respirar", systemImageName: "wind")
        AppShortcut(intent: SyncIntent(), phrases: ["Sincroniza \(.applicationName)"],
                    shortTitle: "Sincronizar", systemImageName: "arrow.triangle.2.circlepath")
    }
}
