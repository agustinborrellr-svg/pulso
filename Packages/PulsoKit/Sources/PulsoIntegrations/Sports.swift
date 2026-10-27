import Foundation

/// Every sport Pulso knows, with how each other service calls it.
public struct Sport: Equatable, Identifiable, Sendable {
    /// Spanish display name, also what `Workout.sport` stores.
    public let name: String
    public let symbol: String
    /// Strava `sport_type` used when matching imports.
    public let strava: [String]
    /// FIT `sport` / `sub_sport` enum values.
    public let fitSport: UInt8
    public let fitSubSport: UInt8
    /// TCX `Sport` attribute (Running / Biking / Other).
    public let tcx: String
    /// Key the app maps to an HKWorkoutActivityType.
    public let health: String

    public var id: String { name }

    /// Private activities stay on the phone: never sent to Strava or Apple Health.
    public var shareable: Bool { health != "private" }
}

public enum SportCatalog {
    public static let all: [Sport] = [
        Sport(name: "Carrera", symbol: "figure.run", strava: ["Run", "TrailRun", "VirtualRun"], fitSport: 1, fitSubSport: 0, tcx: "Running", health: "running"),
        Sport(name: "Cinta de correr", symbol: "figure.run", strava: [], fitSport: 1, fitSubSport: 1, tcx: "Running", health: "running"),
        Sport(name: "Atletismo", symbol: "figure.track.and.field", strava: [], fitSport: 1, fitSubSport: 4, tcx: "Running", health: "trackAndField"),
        Sport(name: "Ciclismo", symbol: "figure.outdoor.cycle", strava: ["Ride", "GravelRide", "Velomobile", "Handcycle"], fitSport: 2, fitSubSport: 0, tcx: "Biking", health: "cycling"),
        Sport(name: "Bici de montaña", symbol: "bicycle", strava: ["MountainBikeRide", "EMountainBikeRide"], fitSport: 2, fitSubSport: 8, tcx: "Biking", health: "cycling"),
        Sport(name: "Bici eléctrica", symbol: "bicycle", strava: ["EBikeRide"], fitSport: 21, fitSubSport: 0, tcx: "Biking", health: "cycling"),
        Sport(name: "Spinning", symbol: "figure.indoor.cycle", strava: ["VirtualRide"], fitSport: 2, fitSubSport: 6, tcx: "Biking", health: "cycling"),
        Sport(name: "Caminata", symbol: "figure.walk", strava: ["Walk"], fitSport: 11, fitSubSport: 0, tcx: "Other", health: "walking"),
        Sport(name: "Senderismo", symbol: "figure.hiking", strava: ["Hike"], fitSport: 17, fitSubSport: 0, tcx: "Other", health: "hiking"),
        Sport(name: "Montañismo", symbol: "mountain.2", strava: ["Snowshoe"], fitSport: 16, fitSubSport: 0, tcx: "Other", health: "hiking"),
        Sport(name: "Fuerza", symbol: "figure.strengthtraining.traditional", strava: ["WeightTraining"], fitSport: 10, fitSubSport: 20, tcx: "Other", health: "strength"),
        Sport(name: "Entrenamiento funcional", symbol: "figure.strengthtraining.functional", strava: [], fitSport: 10, fitSubSport: 20, tcx: "Other", health: "functionalStrength"),
        Sport(name: "Core / abdominales", symbol: "figure.core.training", strava: [], fitSport: 10, fitSubSport: 20, tcx: "Other", health: "core"),
        Sport(name: "Calistenia", symbol: "figure.cross.training", strava: [], fitSport: 10, fitSubSport: 20, tcx: "Other", health: "functionalStrength"),
        Sport(name: "HIIT", symbol: "figure.highintensity.intervaltraining", strava: ["HighIntensityIntervalTraining"], fitSport: 62, fitSubSport: 0, tcx: "Other", health: "hiit"),
        Sport(name: "Crossfit", symbol: "figure.cross.training", strava: ["Crossfit"], fitSport: 10, fitSubSport: 26, tcx: "Other", health: "crossTraining"),
        Sport(name: "Comba", symbol: "figure.jumprope", strava: [], fitSport: 84, fitSubSport: 0, tcx: "Other", health: "jumpRope"),
        Sport(name: "Natación", symbol: "figure.pool.swim", strava: ["Swim"], fitSport: 5, fitSubSport: 17, tcx: "Other", health: "swimming"),
        Sport(name: "Aguas abiertas", symbol: "figure.open.water.swim", strava: [], fitSport: 5, fitSubSport: 18, tcx: "Other", health: "swimming"),
        Sport(name: "Waterpolo", symbol: "figure.waterpolo", strava: [], fitSport: 5, fitSubSport: 0, tcx: "Other", health: "waterPolo"),
        Sport(name: "Remo", symbol: "figure.rower", strava: ["Rowing", "VirtualRow"], fitSport: 15, fitSubSport: 0, tcx: "Other", health: "rowing"),
        Sport(name: "Kayak / piragüismo", symbol: "oar.2.crossed", strava: ["Kayaking", "Canoeing"], fitSport: 41, fitSubSport: 0, tcx: "Other", health: "paddle"),
        Sport(name: "Paddle surf", symbol: "figure.surfing", strava: ["StandUpPaddling"], fitSport: 37, fitSubSport: 0, tcx: "Other", health: "paddle"),
        Sport(name: "Surf", symbol: "figure.surfing", strava: ["Surfing"], fitSport: 38, fitSubSport: 0, tcx: "Other", health: "surfing"),
        Sport(name: "Windsurf / kitesurf", symbol: "wind", strava: ["Windsurf", "Kitesurf"], fitSport: 43, fitSubSport: 0, tcx: "Other", health: "surfing"),
        Sport(name: "Vela", symbol: "sailboat", strava: ["Sail"], fitSport: 32, fitSubSport: 0, tcx: "Other", health: "sailing"),
        Sport(name: "Buceo", symbol: "water.waves", strava: [], fitSport: 53, fitSubSport: 0, tcx: "Other", health: "diving"),
        Sport(name: "Yoga", symbol: "figure.yoga", strava: ["Yoga"], fitSport: 10, fitSubSport: 43, tcx: "Other", health: "yoga"),
        Sport(name: "Pilates", symbol: "figure.pilates", strava: ["Pilates"], fitSport: 10, fitSubSport: 44, tcx: "Other", health: "pilates"),
        Sport(name: "Barre", symbol: "figure.barre", strava: [], fitSport: 10, fitSubSport: 0, tcx: "Other", health: "barre"),
        Sport(name: "Estiramientos", symbol: "figure.flexibility", strava: [], fitSport: 10, fitSubSport: 19, tcx: "Other", health: "flexibility"),
        Sport(name: "Meditación", symbol: "figure.mind.and.body", strava: [], fitSport: 67, fitSubSport: 0, tcx: "Other", health: "mindAndBody"),
        Sport(name: "Taichí", symbol: "figure.taichi", strava: [], fitSport: 10, fitSubSport: 0, tcx: "Other", health: "taiChi"),
        Sport(name: "Elíptica", symbol: "figure.elliptical", strava: ["Elliptical"], fitSport: 4, fitSubSport: 15, tcx: "Other", health: "elliptical"),
        Sport(name: "Escaleras", symbol: "figure.stair.stepper", strava: ["StairStepper"], fitSport: 4, fitSubSport: 16, tcx: "Other", health: "stairs"),
        Sport(name: "Pádel", symbol: "figure.tennis", strava: ["Padel"], fitSport: 64, fitSubSport: 0, tcx: "Other", health: "paddleRacket"),
        Sport(name: "Tenis", symbol: "figure.tennis", strava: ["Tennis"], fitSport: 8, fitSubSport: 0, tcx: "Other", health: "tennis"),
        Sport(name: "Squash", symbol: "figure.squash", strava: ["Squash", "Racquetball"], fitSport: 64, fitSubSport: 0, tcx: "Other", health: "squash"),
        Sport(name: "Bádminton", symbol: "figure.badminton", strava: ["Badminton"], fitSport: 64, fitSubSport: 0, tcx: "Other", health: "badminton"),
        Sport(name: "Pickleball", symbol: "figure.pickleball", strava: ["Pickleball"], fitSport: 64, fitSubSport: 0, tcx: "Other", health: "pickleball"),
        Sport(name: "Pimpón", symbol: "figure.table.tennis", strava: ["TableTennis"], fitSport: 64, fitSubSport: 0, tcx: "Other", health: "tableTennis"),
        Sport(name: "Fútbol", symbol: "figure.soccer", strava: ["Soccer"], fitSport: 7, fitSubSport: 0, tcx: "Other", health: "soccer"),
        Sport(name: "Fútbol sala", symbol: "figure.soccer", strava: [], fitSport: 7, fitSubSport: 0, tcx: "Other", health: "soccer"),
        Sport(name: "Baloncesto", symbol: "figure.basketball", strava: ["Basketball"], fitSport: 6, fitSubSport: 0, tcx: "Other", health: "basketball"),
        Sport(name: "Voleibol", symbol: "figure.volleyball", strava: ["Volleyball"], fitSport: 75, fitSubSport: 0, tcx: "Other", health: "volleyball"),
        Sport(name: "Balonmano", symbol: "figure.handball", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "handball"),
        Sport(name: "Rugby", symbol: "figure.rugby", strava: [], fitSport: 72, fitSubSport: 0, tcx: "Other", health: "rugby"),
        Sport(name: "Fútbol americano", symbol: "figure.american.football", strava: [], fitSport: 9, fitSubSport: 0, tcx: "Other", health: "americanFootball"),
        Sport(name: "Béisbol", symbol: "figure.baseball", strava: [], fitSport: 49, fitSubSport: 0, tcx: "Other", health: "baseball"),
        Sport(name: "Hockey", symbol: "figure.hockey", strava: [], fitSport: 73, fitSubSport: 0, tcx: "Other", health: "hockey"),
        Sport(name: "Críquet", symbol: "figure.cricket", strava: ["Cricket"], fitSport: 71, fitSubSport: 0, tcx: "Other", health: "cricket"),
        Sport(name: "Escalada", symbol: "figure.climbing", strava: ["RockClimbing"], fitSport: 31, fitSubSport: 0, tcx: "Other", health: "climbing"),
        Sport(name: "Esquí", symbol: "figure.skiing.downhill", strava: ["AlpineSki", "BackcountrySki"], fitSport: 13, fitSubSport: 0, tcx: "Other", health: "skiing"),
        Sport(name: "Esquí de fondo", symbol: "figure.skiing.crosscountry", strava: ["NordicSki", "RollerSki"], fitSport: 12, fitSubSport: 0, tcx: "Other", health: "crossCountrySkiing"),
        Sport(name: "Snowboard", symbol: "figure.snowboarding", strava: ["Snowboard"], fitSport: 14, fitSubSport: 0, tcx: "Other", health: "snowboarding"),
        Sport(name: "Patinaje", symbol: "figure.skating", strava: ["IceSkate", "InlineSkate"], fitSport: 30, fitSubSport: 0, tcx: "Other", health: "skating"),
        Sport(name: "Skate", symbol: "figure.skating", strava: ["Skateboard"], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "skating"),
        Sport(name: "Boxeo", symbol: "figure.boxing", strava: [], fitSport: 47, fitSubSport: 0, tcx: "Other", health: "boxing"),
        Sport(name: "Kickboxing", symbol: "figure.kickboxing", strava: [], fitSport: 47, fitSubSport: 0, tcx: "Other", health: "kickboxing"),
        Sport(name: "Artes marciales", symbol: "figure.martial.arts", strava: [], fitSport: 80, fitSubSport: 0, tcx: "Other", health: "martialArts"),
        Sport(name: "Lucha", symbol: "figure.wrestling", strava: [], fitSport: 80, fitSubSport: 0, tcx: "Other", health: "wrestling"),
        Sport(name: "Esgrima", symbol: "figure.fencing", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "fencing"),
        Sport(name: "Gimnasia", symbol: "figure.gymnastics", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "gymnastics"),
        Sport(name: "Golf", symbol: "figure.golf", strava: ["Golf"], fitSport: 25, fitSubSport: 0, tcx: "Other", health: "golf"),
        Sport(name: "Equitación", symbol: "figure.equestrian.sports", strava: [], fitSport: 27, fitSubSport: 0, tcx: "Other", health: "equestrian"),
        Sport(name: "Tiro con arco", symbol: "figure.archery", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "archery"),
        Sport(name: "Bolos", symbol: "figure.bowling", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "bowling"),
        Sport(name: "Baile", symbol: "figure.dance", strava: ["Dance"], fitSport: 83, fitSubSport: 0, tcx: "Other", health: "dance"),
        Sport(name: "Bailar de fiesta", symbol: "figure.socialdance", strava: [], fitSport: 83, fitSubSport: 0, tcx: "Other", health: "socialDance"),
        Sport(name: "Zumba", symbol: "figure.dance", strava: [], fitSport: 83, fitSubSport: 0, tcx: "Other", health: "dance"),
        Sport(name: "Silla de ruedas", symbol: "figure.roll", strava: ["Wheelchair"], fitSport: 65, fitSubSport: 0, tcx: "Other", health: "wheelchair"),
        Sport(name: "Tareas de casa", symbol: "house", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "other"),
        Sport(name: "Jardinería", symbol: "leaf", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "other"),
        Sport(name: "Jugar con niños", symbol: "figure.play", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "play"),
        Sport(name: "Videojuegos activos", symbol: "gamecontroller", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "fitnessGaming"),
        Sport(name: "Conducir", symbol: "car", strava: [], fitSport: 24, fitSubSport: 0, tcx: "Other", health: "other"),
        Sport(name: "Moto", symbol: "motorcycle", strava: [], fitSport: 22, fitSubSport: 0, tcx: "Other", health: "other"),
        Sport(name: "Sauna", symbol: "flame", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "recovery"),
        Sport(name: "Baño de hielo", symbol: "snowflake", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "recovery"),
        Sport(name: "Intimidad", symbol: "heart", strava: [], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "private"),
        Sport(name: "Actividad", symbol: "figure.mixed.cardio", strava: ["Workout"], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "other"),
    ]

    public static var names: [String] { all.map { $0.name } }

    public static func named(_ name: String) -> Sport {
        all.first { $0.name == name } ?? all.first { $0.name == "Actividad" }!
    }

    public static func fromStrava(_ type: String) -> Sport {
        all.first { $0.strava.contains(type) } ?? named("Actividad")
    }

    public static func fromHealth(_ key: String) -> Sport {
        all.first { $0.health == key } ?? named("Actividad")
    }

    /// Strava `sport_type` to report for a Pulso sport (first alias).
    public static func stravaType(_ name: String) -> String {
        named(name).strava.first ?? "Workout"
    }
}
