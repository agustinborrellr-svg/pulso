import Foundation

/// One stored second of strap data.
public struct Sample: Equatable, Sendable {
    public var ts: Int
    public var hr: Int?
    public var rr: [Int]
    public var gx: Double?
    public var gy: Double?
    public var gz: Double?
    public var dyn: Double?
    public var temp: Double?
    public var spo2: Int?
    public var steps: Int?
    public var activity: Int?
    public var sleepState: Int?
    public var quality: Int?
    public var poor: Bool
    public var off: Bool

    public init(ts: Int, hr: Int? = nil, rr: [Int] = [], gx: Double? = nil, gy: Double? = nil, gz: Double? = nil,
                dyn: Double? = nil, temp: Double? = nil, spo2: Int? = nil, steps: Int? = nil, activity: Int? = nil,
                sleepState: Int? = nil, quality: Int? = nil, poor: Bool = false, off: Bool = false) {
        self.ts = ts
        self.hr = hr
        self.rr = rr
        self.gx = gx
        self.gy = gy
        self.gz = gz
        self.dyn = dyn
        self.temp = temp
        self.spo2 = spo2
        self.steps = steps
        self.activity = activity
        self.sleepState = sleepState
        self.quality = quality
        self.poor = poor
        self.off = off
    }

    public var worn: Bool { !off && hr != nil }
}

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male, female, other
}

public struct Profile: Codable, Equatable, Sendable {
    public var name: String = ""
    public var birthYear: Int = 1990
    public var sex: Sex = .male
    public var weightKg: Double = 75
    public var heightCm: Double = 178
    /// Manual max HR; nil = estimated (Tanaka) and raised by observed peaks.
    public var maxHROverride: Int?
    /// Personal baseline sleep need in hours (before strain/debt adjustments).
    public var sleepNeedHours: Double = 8.0
    public var healthKitEnabled: Bool = false
    /// Days of raw per-second data to keep on the phone (summaries are kept forever).
    /// Days of raw per-second data kept (0 = forever). Summaries are always kept.
    public var rawRetentionDays: Int = 0
    /// Opt-in menstrual-cycle estimate from the nightly skin-temperature shift.
    public var cycleTracking: Bool = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case name, birthYear, sex, weightKg, heightCm, maxHROverride, sleepNeedHours, healthKitEnabled
        case rawRetentionDays, cycleTracking
    }

    /// Every field is optional on decode so a profile saved by an older version (without the newer
    /// keys) still loads instead of silently resetting to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Profile.defaults
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        birthYear = try c.decodeIfPresent(Int.self, forKey: .birthYear) ?? d.birthYear
        sex = try c.decodeIfPresent(Sex.self, forKey: .sex) ?? d.sex
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? d.weightKg
        heightCm = try c.decodeIfPresent(Double.self, forKey: .heightCm) ?? d.heightCm
        maxHROverride = try c.decodeIfPresent(Int.self, forKey: .maxHROverride)
        sleepNeedHours = try c.decodeIfPresent(Double.self, forKey: .sleepNeedHours) ?? d.sleepNeedHours
        healthKitEnabled = try c.decodeIfPresent(Bool.self, forKey: .healthKitEnabled) ?? d.healthKitEnabled
        rawRetentionDays = try c.decodeIfPresent(Int.self, forKey: .rawRetentionDays) ?? d.rawRetentionDays
        cycleTracking = try c.decodeIfPresent(Bool.self, forKey: .cycleTracking) ?? d.cycleTracking
    }

    private static let defaults = Profile()

    public var age: Int {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        return max(12, min(100, year - birthYear))
    }
}

public enum SleepStage: Int, Codable, CaseIterable, Sendable {
    case awake = 0
    case light = 1
    case deep = 2
    case rem = 3
}

/// A detected (or user-edited) sleep period with its computed metrics.
public struct SleepSession: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64?
    public var start: Int
    public var end: Int
    public var isNap: Bool
    public var manual: Bool
    /// One stage per minute from `start`.
    public var stages: [SleepStage]
    public var minutesAwake: Double
    public var minutesLight: Double
    public var minutesDeep: Double
    public var minutesREM: Double
    public var hrv: Double?
    public var hrvSDNN: Double?
    public var rhr: Double?
    public var respRate: Double?
    public var spo2: Double?
    public var skinTemp: Double?
    public var avgHR: Double?
    public var minHR: Double?
    public var disturbances: Int
    public var latencyMinutes: Double
    /// Per-5-minute (ts, hr, rmssd) points for charts.
    public var trend: [TrendPoint]
    /// How far the stage split can be trusted this night, and why.
    public var stageConfidence: StageConfidence?
    /// Daytime sleep the user has classified (nap or real sleep). False = Pulso decided on its own.
    public var kindConfirmed: Bool

    public init(id: Int64? = nil, start: Int, end: Int, isNap: Bool = false, manual: Bool = false,
                stages: [SleepStage] = [], minutesAwake: Double = 0, minutesLight: Double = 0,
                minutesDeep: Double = 0, minutesREM: Double = 0, hrv: Double? = nil, hrvSDNN: Double? = nil,
                rhr: Double? = nil, respRate: Double? = nil, spo2: Double? = nil, skinTemp: Double? = nil,
                avgHR: Double? = nil, minHR: Double? = nil, disturbances: Int = 0, latencyMinutes: Double = 0,
                trend: [TrendPoint] = [], stageConfidence: StageConfidence? = nil, kindConfirmed: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.isNap = isNap
        self.manual = manual
        self.stages = stages
        self.minutesAwake = minutesAwake
        self.minutesLight = minutesLight
        self.minutesDeep = minutesDeep
        self.minutesREM = minutesREM
        self.hrv = hrv
        self.hrvSDNN = hrvSDNN
        self.rhr = rhr
        self.respRate = respRate
        self.spo2 = spo2
        self.skinTemp = skinTemp
        self.avgHR = avgHR
        self.minHR = minHR
        self.disturbances = disturbances
        self.latencyMinutes = latencyMinutes
        self.trend = trend
        self.stageConfidence = stageConfidence
        self.kindConfirmed = kindConfirmed
    }

    public var inBedMinutes: Double { Double(end - start) / 60 }
    public var asleepMinutes: Double { minutesLight + minutesDeep + minutesREM }
    public var efficiency: Double { inBedMinutes > 0 ? min(1, asleepMinutes / inBedMinutes) : 0 }
    public var restorativeMinutes: Double { minutesDeep + minutesREM }
}

/// Trust in one night's stage split. Wrist sensors estimate stages from heart rate, its variability and
/// movement; only brain activity (EEG in a sleep lab) measures them, so even "high" means the signals were
/// clean and clear, not lab-grade.
public struct StageConfidence: Codable, Equatable, Sendable {
    public enum Level: String, Codable, Sendable {
        case high, medium, low

        public var label: String {
            switch self {
            case .high: return "Alta"
            case .medium: return "Media"
            case .low: return "Baja"
            }
        }
    }

    public var level: Level
    /// 0–100.
    public var score: Double
    /// Why it isn't higher, in plain Spanish (empty when nothing held it back).
    public var reasons: [String]
    /// Fraction of minutes with the strap on and reading.
    public var coverage: Double
    /// Fraction of minutes with a clean beat-to-beat signal (needed for HRV, the key to deep/REM).
    public var beatCoverage: Double
    /// Mean probability of the chosen stage per asleep minute (how clear each minute was).
    public var decisiveness: Double

    public init(level: Level, score: Double, reasons: [String], coverage: Double, beatCoverage: Double, decisiveness: Double) {
        self.level = level
        self.score = score
        self.reasons = reasons
        self.coverage = coverage
        self.beatCoverage = beatCoverage
        self.decisiveness = decisiveness
    }
}

/// The user's answer to "¿fue una siesta o era tu sueño?" for a daytime sleep.
public struct SleepDecision: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case nap, sleep }
    public var start: Int
    public var end: Int
    public var kind: Kind

    public init(start: Int, end: Int, kind: Kind) {
        self.start = start
        self.end = end
        self.kind = kind
    }

    /// Overlap of two intervals as a fraction of the shorter one.
    public static func overlapFraction(_ a0: Int, _ a1: Int, _ b0: Int, _ b1: Int) -> Double {
        let o = min(a1, b1) - max(a0, b0)
        let shorter = min(a1 - a0, b1 - b0)
        guard o > 0, shorter > 0 else { return 0 }
        return Double(o) / Double(shorter)
    }
}

public struct TrendPoint: Codable, Equatable, Sendable {
    public var ts: Int
    public var hr: Double?
    public var hrv: Double?

    public init(ts: Int, hr: Double?, hrv: Double?) {
        self.ts = ts
        self.hr = hr
        self.hrv = hrv
    }
}

public enum WorkoutSource: String, Codable, Sendable {
    /// Detected from heart rate / motion.
    case auto
    /// Entered or edited by hand.
    case manual
    /// Recorded live in the app.
    case live
    /// Imported from Apple Health (Garmin, Nike, Peloton, gym apps…).
    case health
    /// Imported from Strava.
    case strava
    /// Imported from a WHOOP data export (CSV).
    case whoop

    /// Imported from another app: its own metrics are kept when the strap has no data for the window.
    public var isExternal: Bool { self == .health || self == .strava || self == .whoop }
}

public struct Workout: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64?
    public var start: Int
    public var end: Int
    public var sport: String
    public var source: WorkoutSource
    public var strain: Double
    public var avgHR: Double
    public var maxHR: Double
    public var kcal: Double
    /// Minutes in zones 1…5.
    public var zoneMinutes: [Double]
    public var notes: String
    /// Ids of this workout in other services: "strava" (activity id), "strava_upload", "health" (HK UUID).
    public var externalIDs: [String: String]?
    /// App that recorded it when imported ("Strava", "Garmin Connect"…).
    public var externalApp: String?
    public var distanceMeters: Double?

    public init(id: Int64? = nil, start: Int, end: Int, sport: String, source: WorkoutSource, strain: Double = 0,
                avgHR: Double = 0, maxHR: Double = 0, kcal: Double = 0, zoneMinutes: [Double] = [0, 0, 0, 0, 0],
                notes: String = "", externalIDs: [String: String]? = nil, externalApp: String? = nil,
                distanceMeters: Double? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.sport = sport
        self.source = source
        self.strain = strain
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.kcal = kcal
        self.zoneMinutes = zoneMinutes
        self.notes = notes
        self.externalIDs = externalIDs
        self.externalApp = externalApp
        self.distanceMeters = distanceMeters
    }

    public var durationMinutes: Double { Double(end - start) / 60 }

    public func externalID(_ service: String) -> String? { externalIDs?[service] }

    public mutating func setExternalID(_ id: String?, for service: String) {
        var ids = externalIDs ?? [:]
        ids[service] = id
        externalIDs = ids.isEmpty ? nil : ids
    }
}

/// One "day" = the physiological cycle that starts when the main sleep ending on that date ends.
public struct DaySummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String { day }
    public var day: String
    public var cycleStart: Int?
    public var cycleEnd: Int?

    // Recovery
    public var recovery: Double?
    public var calibrating: Bool = true
    public var hrv: Double?
    public var rhr: Double?
    public var respRate: Double?
    public var spo2: Double?
    public var skinTemp: Double?
    public var skinTempDeviation: Double?
    public var contributors: [Contributor] = []

    // Sleep
    public var sleepId: Int64?
    public var sleepStart: Int?
    public var sleepEnd: Int?
    public var deepMinutes: Double?
    public var remMinutes: Double?
    public var lightMinutes: Double?
    public var awakeMinutes: Double?
    public var disturbances: Int?
    public var sleepMinutes: Double?
    public var inBedMinutes: Double?
    public var sleepNeedMinutes: Double?
    public var sleepPerformance: Double?
    public var sleepEfficiency: Double?
    public var sleepConsistency: Double?
    public var sleepDebtMinutes: Double?
    public var restorativeMinutes: Double?
    public var napMinutes: Double?

    // Strain / activity
    public var strain: Double?
    public var kcal: Double?
    public var activeKcal: Double?
    public var avgHR: Double?
    public var maxHR: Double?
    public var steps: Int?
    public var zoneMinutes: [Double] = [0, 0, 0, 0, 0]
    public var workoutCount: Int = 0

    // Stress
    public var stressAvg: Double?
    public var stressHighMinutes: Double?
    public var stressHourly: [Double?] = []
    /// Calm daytime reference of this day (used to build the stress baseline).
    public var calmHR: Double?
    public var calmHRV: Double?

    /// Heart beats above resting while awake, outside workouts and naps (cardiac cost of daily life).
    public var extraBeats: Double?

    // Fitness
    public var vo2max: Double?
    public var wornMinutes: Double = 0
    public var source: String = "strap"

    public init(day: String) {
        self.day = day
    }
}

/// One factor of a score, shown in the "why" breakdown.
public struct Contributor: Codable, Equatable, Sendable, Identifiable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var value: Double?
    public var baseline: Double?
    public var unit: String
    /// Signed contribution (positive helps the score).
    public var impact: Double

    public init(key: String, label: String, value: Double?, baseline: Double?, unit: String, impact: Double) {
        self.key = key
        self.label = label
        self.value = value
        self.baseline = baseline
        self.unit = unit
        self.impact = impact
    }
}

public struct JournalEntry: Codable, Equatable, Sendable {
    public var day: String
    public var key: String
    public var value: Double

    public init(day: String, key: String, value: Double) {
        self.day = day
        self.key = key
        self.value = value
    }
}

public enum ECGSource: String, Codable, Sendable {
    /// Recorded with a WHOOP MG's ECG electrodes.
    case whoopMG
    /// Imported from an Apple Watch ECG in Apple Health.
    case appleWatch
    /// Generated by the built-in simulator (testing / demo).
    case simulated
}

/// One single-lead ECG recording. `samples` are millivolts at `sampleRate` Hz.
public struct ECGRecording: Equatable, Identifiable, Sendable {
    public var id: Int64?
    public var start: Int
    public var sampleRate: Double
    public var samples: [Float]
    public var source: ECGSource
    /// Analysis result key (see PulsoECG.Rhythm) and average heart rate.
    public var rhythm: String?
    public var avgHR: Double?
    public var notes: String
    /// Source-specific id (e.g. the Apple Health UUID) used to avoid importing twice.
    public var externalID: String?

    public init(id: Int64? = nil, start: Int, sampleRate: Double, samples: [Float], source: ECGSource,
                rhythm: String? = nil, avgHR: Double? = nil, notes: String = "", externalID: String? = nil) {
        self.id = id
        self.start = start
        self.sampleRate = sampleRate
        self.samples = samples
        self.source = source
        self.rhythm = rhythm
        self.avgHR = avgHR
        self.notes = notes
        self.externalID = externalID
    }

    public var durationSeconds: Double { sampleRate > 0 ? Double(samples.count) / sampleRate : 0 }
}

public struct StoredEvent: Equatable, Sendable {
    public var ts: Int
    public var kind: Int
    public var value: Double?

    public init(ts: Int, kind: Int, value: Double?) {
        self.ts = ts
        self.kind = kind
        self.value = value
    }
}

public enum DayKey {
    public static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public static func string(ts: Int, calendar: Calendar = .current) -> String {
        string(Date(timeIntervalSince1970: TimeInterval(ts)), calendar: calendar)
    }

    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func shift(_ key: String, days: Int, calendar: Calendar = .current) -> String {
        guard let d = date(key, calendar: calendar), let n = calendar.date(byAdding: .day, value: days, to: d) else { return key }
        return string(n, calendar: calendar)
    }
}
