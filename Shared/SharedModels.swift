import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Shared between the app and the widget extension (compiled into both targets).
enum SharedConfig {
    static let appGroup = "group.es.gusborrell.pulso"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
}

/// What the home / lock screen widgets show. Written by the app after each analysis.
struct WidgetSnapshot: Codable, Equatable {
    var updated: Date
    var day: String
    var recovery: Double?
    var strain: Double?
    var strainTarget: String?
    var sleepPerformance: Double?
    var sleepMinutes: Double?
    var hrv: Double?
    var rhr: Double?
    var battery: Double?
    var nextAlarm: Date?
    var headline: String?

    static let placeholder = WidgetSnapshot(updated: Date(), day: "", recovery: 72, strain: 9.8, strainTarget: "14–18",
                                            sleepPerformance: 0.91, sleepMinutes: 452, hrv: 68, rhr: 52, battery: 64,
                                            nextAlarm: nil, headline: "Tu cuerpo está listo para rendir.")

    private static var fileURL: URL? { SharedConfig.containerURL?.appendingPathComponent("widget.json") }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

#if canImport(ActivityKit)
/// Live Activity of a workout in progress (lock screen + Dynamic Island).
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var heartRate: Int
        var zone: Int
        var strain: Double
        var kcal: Int
        /// Current interval step label, if following a plan.
        var step: String?
        var stepEnds: Date?
    }

    var sport: String
    var symbol: String
    var start: Date
}
#endif
