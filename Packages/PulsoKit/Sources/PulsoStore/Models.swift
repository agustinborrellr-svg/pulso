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
    public var rawRetentionDays: Int = 120

    public init() {}

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

    public init(id: Int64? = nil, start: Int, end: Int, isNap: Bool = false, manual: Bool = false,
                stages: [SleepStage] = [], minutesAwake: Double = 0, minutesLight: Double = 0,
                minutesDeep: Double = 0, minutesREM: Double = 0, hrv: Double? = nil, hrvSDNN: Double? = nil,
                rhr: Double? = nil, respRate: Double? = nil, spo2: Double? = nil, skinTemp: Double? = nil,
                avgHR: Double? = nil, minHR: Double? = nil, disturbances: Int = 0, latencyMinutes: Double = 0,
                trend: [TrendPoint] = []) {
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
    }

    public var inBedMinutes: Double { Double(end - start) / 60 }
    public var asleepMinutes: Double { minutesLight + minutesDeep + minutesREM }
    public var efficiency: Double { inBedMinutes > 0 ? min(1, asleepMinutes / inBedMinutes) : 0 }
    public var restorativeMinutes: Double { minutesDeep + minutesREM }
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
    case auto, manual, live
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

    public init(id: Int64? = nil, start: Int, end: Int, sport: String, source: WorkoutSource, strain: Double = 0,
                avgHR: Double = 0, maxHR: Double = 0, kcal: Double = 0, zoneMinutes: [Double] = [0, 0, 0, 0, 0],
                notes: String = "") {
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
    }

    public var durationMinutes: Double { Double(end - start) / 60 }
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
