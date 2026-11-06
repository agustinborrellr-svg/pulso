import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
    /// Says your recovery, strain and pulse out loud (headphones or speaker).
    case speakStatus
    /// 60-second still check; the result is spoken and notified.
    case scan
    /// Calls a web address of your choice: Home Assistant (open a door, switch a light), IFTTT, a Telegram/ntfy alert…
    case webhook
    /// Shows a notification that runs one of your Shortcuts when you tap it (iOS only runs them in the foreground).
    case shortcut

    public var label: String {
        switch self {
        case .none: return "Nada"
        case .marker: return "Guardar una marca"
        case .toggleWorkout: return "Empezar / terminar entreno"
        case .lap: return "Marcar vuelta"
        case .breathing: return "Respiración guiada con vibración"
        case .speakStatus: return "Decirme cómo estoy (voz)"
        case .scan: return "Escanear 60 s"
        case .webhook: return "Llamar a una dirección web (casa, avisos…)"
        case .shortcut: return "Lanzar un Atajo"
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
        case speakStatus
        case scan
        case webhook
        case shortcut
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
        case .speakStatus: return .speakStatus
        case .scan: return .scan
        case .webhook: return .webhook
        case .shortcut: return .shortcut
        }
    }
}

/// The web call a double tap makes. Only http(s); a JSON body says what happened.
public enum DoubleTapWebhook {
    public enum Method: String, Codable, CaseIterable, Sendable { case post = "POST", get = "GET" }

    public static func request(url: String, method: Method, heartRate: Int?, at date: Date) -> URLRequest? {
        guard let u = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http", u.host != nil else { return nil }
        var r = URLRequest(url: u, timeoutInterval: 10)
        r.httpMethod = method.rawValue
        if method == .post {
            var body: [String: Any] = ["event": "double_tap", "source": "pulso", "ts": Int(date.timeIntervalSince1970)]
            if let heartRate { body["heart_rate"] = heartRate }
            r.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    /// The Shortcuts app URL that runs a shortcut by name.
    public static func shortcutURL(name: String) -> URL? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let q = n.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "shortcuts://run-shortcut?name=\(q)")
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
    /// Double tap → web call.
    public var tapURL: String
    public var tapMethod: DoubleTapWebhook.Method
    /// Double tap → Shortcuts name.
    public var tapShortcut: String

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
        tapURL = ""
        tapMethod = .post
        tapShortcut = ""
    }

    private enum CodingKeys: String, CodingKey {
        case doubleTap, quickSport, hrBroadcast, voiceCues, stravaAutoUpload, stravaImport, healthImport, healthWorkouts, labEnabled
        case tapURL, tapMethod, tapShortcut
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeatureSettings()
        // Enums decode with try?: an unknown case (from a newer build) keeps the default, not a reset of all settings.
        doubleTap = (try? c.decodeIfPresent(DoubleTapAction.self, forKey: .doubleTap)) ?? d.doubleTap
        quickSport = try c.decodeIfPresent(String.self, forKey: .quickSport) ?? d.quickSport
        hrBroadcast = try c.decodeIfPresent(Bool.self, forKey: .hrBroadcast) ?? d.hrBroadcast
        voiceCues = try c.decodeIfPresent(Bool.self, forKey: .voiceCues) ?? d.voiceCues
        stravaAutoUpload = try c.decodeIfPresent(Bool.self, forKey: .stravaAutoUpload) ?? d.stravaAutoUpload
        stravaImport = try c.decodeIfPresent(Bool.self, forKey: .stravaImport) ?? d.stravaImport
        healthImport = try c.decodeIfPresent(Bool.self, forKey: .healthImport) ?? d.healthImport
        healthWorkouts = try c.decodeIfPresent(Bool.self, forKey: .healthWorkouts) ?? d.healthWorkouts
        labEnabled = try c.decodeIfPresent(Bool.self, forKey: .labEnabled) ?? d.labEnabled
        tapURL = try c.decodeIfPresent(String.self, forKey: .tapURL) ?? d.tapURL
        tapMethod = (try? c.decodeIfPresent(DoubleTapWebhook.Method.self, forKey: .tapMethod)) ?? d.tapMethod
        tapShortcut = try c.decodeIfPresent(String.self, forKey: .tapShortcut) ?? d.tapShortcut
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
