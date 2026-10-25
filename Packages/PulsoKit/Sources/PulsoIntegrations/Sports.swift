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
}

public enum SportCatalog {
    public static let all: [Sport] = [
        Sport(name: "Carrera", symbol: "figure.run", strava: ["Run", "TrailRun", "VirtualRun"], fitSport: 1, fitSubSport: 0, tcx: "Running", health: "running"),
        Sport(name: "Ciclismo", symbol: "figure.outdoor.cycle", strava: ["Ride", "MountainBikeRide", "GravelRide", "EBikeRide", "EMountainBikeRide", "VirtualRide", "Velomobile", "Handcycle"], fitSport: 2, fitSubSport: 0, tcx: "Biking", health: "cycling"),
        Sport(name: "Caminata", symbol: "figure.walk", strava: ["Walk"], fitSport: 11, fitSubSport: 0, tcx: "Other", health: "walking"),
        Sport(name: "Senderismo", symbol: "figure.hiking", strava: ["Hike"], fitSport: 17, fitSubSport: 0, tcx: "Other", health: "hiking"),
        Sport(name: "Fuerza", symbol: "figure.strengthtraining.traditional", strava: ["WeightTraining"], fitSport: 10, fitSubSport: 20, tcx: "Other", health: "strength"),
        Sport(name: "HIIT", symbol: "figure.highintensity.intervaltraining", strava: ["HighIntensityIntervalTraining"], fitSport: 10, fitSubSport: 26, tcx: "Other", health: "hiit"),
        Sport(name: "Crossfit", symbol: "figure.cross.training", strava: ["Crossfit"], fitSport: 10, fitSubSport: 26, tcx: "Other", health: "crossTraining"),
        Sport(name: "Natación", symbol: "figure.pool.swim", strava: ["Swim"], fitSport: 5, fitSubSport: 0, tcx: "Other", health: "swimming"),
        Sport(name: "Remo", symbol: "figure.rower", strava: ["Rowing", "VirtualRow", "Canoeing", "Kayaking"], fitSport: 15, fitSubSport: 0, tcx: "Other", health: "rowing"),
        Sport(name: "Yoga", symbol: "figure.yoga", strava: ["Yoga"], fitSport: 10, fitSubSport: 43, tcx: "Other", health: "yoga"),
        Sport(name: "Pilates", symbol: "figure.pilates", strava: ["Pilates"], fitSport: 10, fitSubSport: 44, tcx: "Other", health: "pilates"),
        Sport(name: "Elíptica", symbol: "figure.elliptical", strava: ["Elliptical", "StairStepper"], fitSport: 4, fitSubSport: 15, tcx: "Other", health: "elliptical"),
        Sport(name: "Pádel", symbol: "figure.tennis", strava: ["Padel"], fitSport: 8, fitSubSport: 0, tcx: "Other", health: "paddle"),
        Sport(name: "Tenis", symbol: "figure.tennis", strava: ["Tennis", "Pickleball", "Squash", "Badminton", "Racquetball", "TableTennis"], fitSport: 8, fitSubSport: 0, tcx: "Other", health: "tennis"),
        Sport(name: "Fútbol", symbol: "figure.soccer", strava: ["Soccer"], fitSport: 7, fitSubSport: 0, tcx: "Other", health: "soccer"),
        Sport(name: "Baloncesto", symbol: "figure.basketball", strava: ["Basketball"], fitSport: 6, fitSubSport: 0, tcx: "Other", health: "basketball"),
        Sport(name: "Escalada", symbol: "figure.climbing", strava: ["RockClimbing"], fitSport: 31, fitSubSport: 0, tcx: "Other", health: "climbing"),
        Sport(name: "Esquí", symbol: "figure.skiing.downhill", strava: ["AlpineSki", "BackcountrySki", "NordicSki", "Snowboard"], fitSport: 13, fitSubSport: 0, tcx: "Other", health: "skiing"),
        Sport(name: "Golf", symbol: "figure.golf", strava: ["Golf"], fitSport: 25, fitSubSport: 0, tcx: "Other", health: "golf"),
        Sport(name: "Baile", symbol: "figure.dance", strava: ["Dance"], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "dance"),
        Sport(name: "Actividad", symbol: "figure.mixed.cardio", strava: ["Workout"], fitSport: 0, fitSubSport: 0, tcx: "Other", health: "other"),
    ]

    public static var names: [String] { all.map { $0.name } }

    public static func named(_ name: String) -> Sport {
        all.first { $0.name == name } ?? all.last!
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
