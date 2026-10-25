import Foundation

/// What a double tap on the strap does when no alarm is ringing.
public enum DoubleTapAction: String, Codable, CaseIterable, Sendable {
    case none
    /// Saves a timestamped marker ("algo ha pasado aquí") visible in the day's timeline.
    case marker
    /// Starts a workout, or ends the one in progress.
    case toggleWorkout
    /// Marks a lap in the workout in progress (a marker otherwise).
    case lap
    /// One minute of paced breathing guided by strap vibrations.
    case breathing

    public var label: String {
        switch self {
        case .none: return "Nada"
        case .marker: return "Guardar una marca"
        case .toggleWorkout: return "Empezar / terminar entreno"
        case .lap: return "Marcar vuelta"
        case .breathing: return "Respiración guiada con vibración"
        }
    }
}

public enum GestureRouter {
    public enum Outcome: Equatable {
        /// Handled by the alarm that is ringing.
        case alarm
        case marker
        case startWorkout
        case stopWorkout
        case lap
        case breathing
        case ignored
    }

    /// Alarms always win; otherwise the configured action applies.
    public static func route(action: DoubleTapAction, alarmActive: Bool, workoutActive: Bool) -> Outcome {
        if alarmActive { return .alarm }
        switch action {
        case .none: return .ignored
        case .marker: return .marker
        case .toggleWorkout: return workoutActive ? .stopWorkout : .startWorkout
        case .lap: return workoutActive ? .lap : .marker
        case .breathing: return .breathing
        }
    }
}

/// Settings for features that don't belong to the profile (stored as one JSON blob).
public struct FeatureSettings: Codable, Equatable, Sendable {
    public var doubleTap: DoubleTapAction
    /// Sport used when a double tap starts a workout.
    public var quickSport: String
    /// Re-broadcast the strap's heart rate as a standard Bluetooth heart-rate sensor.
    public var hrBroadcast: Bool
    /// Speak interval cues.
    public var voiceCues: Bool
    /// Upload finished workouts to Strava automatically.
    public var stravaAutoUpload: Bool
    /// Import activities from Strava.
    public var stravaImport: Bool
    /// Import workouts recorded by other apps from Apple Health.
    public var healthImport: Bool
    /// Save workouts (with heart rate) to Apple Health.
    public var healthWorkouts: Bool
    /// Show the "Laboratorio" tools (raw capture, haptic tester).
    public var labEnabled: Bool

    public init() {
        doubleTap = .marker
        quickSport = "Actividad"
        hrBroadcast = false
        voiceCues = true
        stravaAutoUpload = true
        stravaImport = true
        healthImport = true
        healthWorkouts = true
        labEnabled = false
    }

    private enum CodingKeys: String, CodingKey {
        case doubleTap, quickSport, hrBroadcast, voiceCues, stravaAutoUpload, stravaImport, healthImport, healthWorkouts, labEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureSettings()
        doubleTap = try c.decodeIfPresent(DoubleTapAction.self, forKey: .doubleTap) ?? d.doubleTap
        quickSport = try c.decodeIfPresent(String.self, forKey: .quickSport) ?? d.quickSport
        hrBroadcast = try c.decodeIfPresent(Bool.self, forKey: .hrBroadcast) ?? d.hrBroadcast
        voiceCues = try c.decodeIfPresent(Bool.self, forKey: .voiceCues) ?? d.voiceCues
        stravaAutoUpload = try c.decodeIfPresent(Bool.self, forKey: .stravaAutoUpload) ?? d.stravaAutoUpload
        stravaImport = try c.decodeIfPresent(Bool.self, forKey: .stravaImport) ?? d.stravaImport
        healthImport = try c.decodeIfPresent(Bool.self, forKey: .healthImport) ?? d.healthImport
        healthWorkouts = try c.decodeIfPresent(Bool.self, forKey: .healthWorkouts) ?? d.healthWorkouts
        labEnabled = try c.decodeIfPresent(Bool.self, forKey: .labEnabled) ?? d.labEnabled
    }
}

/// A moment saved with a double tap (or a lap during a workout).
public struct Marker: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(ts)" }
    public var ts: Int
    public var kind: String
    public var note: String

    public init(ts: Int, kind: String, note: String = "") {
        self.ts = ts
        self.kind = kind
        self.note = note
    }
}
