import Foundation

// Stored JSON comes from older versions too: a field added later must not make old rows unreadable.
// Every field that has a sensible default is decoded with `decodeIfPresent`; only the identity is required.

extension DaySummary {
    private enum TolerantKeys: String, CodingKey {
        case day, cycleStart, cycleEnd, recovery, calibrating, hrv, rhr, respRate, spo2, skinTemp, skinTempDeviation, contributors, sleepId, sleepStart, sleepEnd, deepMinutes, remMinutes, lightMinutes, awakeMinutes, disturbances, sleepMinutes, inBedMinutes, sleepNeedMinutes, sleepPerformance, sleepEfficiency, sleepConsistency, sleepDebtMinutes, restorativeMinutes, napMinutes, strain, kcal, activeKcal, avgHR, maxHR, steps, zoneMinutes, workoutCount, stressAvg, stressHighMinutes, stressHourly, calmHR, calmHRV, extraBeats, vo2max, wornMinutes, source, nightImported
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        let day = try c.decode(String.self, forKey: .day)
        self.init(day: day)
        cycleStart = try c.decodeIfPresent(Int.self, forKey: .cycleStart)
        cycleEnd = try c.decodeIfPresent(Int.self, forKey: .cycleEnd)
        recovery = try c.decodeIfPresent(Double.self, forKey: .recovery)
        calibrating = try c.decodeIfPresent(Bool.self, forKey: .calibrating) ?? true
        hrv = try c.decodeIfPresent(Double.self, forKey: .hrv)
        rhr = try c.decodeIfPresent(Double.self, forKey: .rhr)
        respRate = try c.decodeIfPresent(Double.self, forKey: .respRate)
        spo2 = try c.decodeIfPresent(Double.self, forKey: .spo2)
        skinTemp = try c.decodeIfPresent(Double.self, forKey: .skinTemp)
        skinTempDeviation = try c.decodeIfPresent(Double.self, forKey: .skinTempDeviation)
        contributors = try c.decodeIfPresent([Contributor].self, forKey: .contributors) ?? []
        sleepId = try c.decodeIfPresent(Int64.self, forKey: .sleepId)
        sleepStart = try c.decodeIfPresent(Int.self, forKey: .sleepStart)
        sleepEnd = try c.decodeIfPresent(Int.self, forKey: .sleepEnd)
        deepMinutes = try c.decodeIfPresent(Double.self, forKey: .deepMinutes)
        remMinutes = try c.decodeIfPresent(Double.self, forKey: .remMinutes)
        lightMinutes = try c.decodeIfPresent(Double.self, forKey: .lightMinutes)
        awakeMinutes = try c.decodeIfPresent(Double.self, forKey: .awakeMinutes)
        disturbances = try c.decodeIfPresent(Int.self, forKey: .disturbances)
        sleepMinutes = try c.decodeIfPresent(Double.self, forKey: .sleepMinutes)
        inBedMinutes = try c.decodeIfPresent(Double.self, forKey: .inBedMinutes)
        sleepNeedMinutes = try c.decodeIfPresent(Double.self, forKey: .sleepNeedMinutes)
        sleepPerformance = try c.decodeIfPresent(Double.self, forKey: .sleepPerformance)
        sleepEfficiency = try c.decodeIfPresent(Double.self, forKey: .sleepEfficiency)
        sleepConsistency = try c.decodeIfPresent(Double.self, forKey: .sleepConsistency)
        sleepDebtMinutes = try c.decodeIfPresent(Double.self, forKey: .sleepDebtMinutes)
        restorativeMinutes = try c.decodeIfPresent(Double.self, forKey: .restorativeMinutes)
        napMinutes = try c.decodeIfPresent(Double.self, forKey: .napMinutes)
        strain = try c.decodeIfPresent(Double.self, forKey: .strain)
        kcal = try c.decodeIfPresent(Double.self, forKey: .kcal)
        activeKcal = try c.decodeIfPresent(Double.self, forKey: .activeKcal)
        avgHR = try c.decodeIfPresent(Double.self, forKey: .avgHR)
        maxHR = try c.decodeIfPresent(Double.self, forKey: .maxHR)
        steps = try c.decodeIfPresent(Int.self, forKey: .steps)
        zoneMinutes = try c.decodeIfPresent([Double].self, forKey: .zoneMinutes) ?? [0, 0, 0, 0, 0]
        workoutCount = try c.decodeIfPresent(Int.self, forKey: .workoutCount) ?? 0
        stressAvg = try c.decodeIfPresent(Double.self, forKey: .stressAvg)
        stressHighMinutes = try c.decodeIfPresent(Double.self, forKey: .stressHighMinutes)
        stressHourly = try c.decodeIfPresent([Double?].self, forKey: .stressHourly) ?? []
        calmHR = try c.decodeIfPresent(Double.self, forKey: .calmHR)
        calmHRV = try c.decodeIfPresent(Double.self, forKey: .calmHRV)
        extraBeats = try c.decodeIfPresent(Double.self, forKey: .extraBeats)
        vo2max = try c.decodeIfPresent(Double.self, forKey: .vo2max)
        wornMinutes = try c.decodeIfPresent(Double.self, forKey: .wornMinutes) ?? 0
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "strap"
        nightImported = try c.decodeIfPresent(Bool.self, forKey: .nightImported) ?? false
    }
}

extension SleepSession {
    private enum TolerantKeys: String, CodingKey {
        case id, start, end, isNap, manual, stages, minutesAwake, minutesLight, minutesDeep, minutesREM, hrv, hrvSDNN, rhr, respRate, spo2
        case skinTemp, avgHR, minHR, disturbances, latencyMinutes, trend, stageConfidence, kindConfirmed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        self.init(id: try c.decodeIfPresent(Int64.self, forKey: .id),
                  start: try c.decode(Int.self, forKey: .start),
                  end: try c.decode(Int.self, forKey: .end),
                  isNap: try c.decodeIfPresent(Bool.self, forKey: .isNap) ?? false,
                  manual: try c.decodeIfPresent(Bool.self, forKey: .manual) ?? false,
                  stages: try c.decodeIfPresent([SleepStage].self, forKey: .stages) ?? [],
                  minutesAwake: try c.decodeIfPresent(Double.self, forKey: .minutesAwake) ?? 0,
                  minutesLight: try c.decodeIfPresent(Double.self, forKey: .minutesLight) ?? 0,
                  minutesDeep: try c.decodeIfPresent(Double.self, forKey: .minutesDeep) ?? 0,
                  minutesREM: try c.decodeIfPresent(Double.self, forKey: .minutesREM) ?? 0,
                  hrv: try c.decodeIfPresent(Double.self, forKey: .hrv),
                  hrvSDNN: try c.decodeIfPresent(Double.self, forKey: .hrvSDNN),
                  rhr: try c.decodeIfPresent(Double.self, forKey: .rhr),
                  respRate: try c.decodeIfPresent(Double.self, forKey: .respRate),
                  spo2: try c.decodeIfPresent(Double.self, forKey: .spo2),
                  skinTemp: try c.decodeIfPresent(Double.self, forKey: .skinTemp),
                  avgHR: try c.decodeIfPresent(Double.self, forKey: .avgHR),
                  minHR: try c.decodeIfPresent(Double.self, forKey: .minHR),
                  disturbances: try c.decodeIfPresent(Int.self, forKey: .disturbances) ?? 0,
                  latencyMinutes: try c.decodeIfPresent(Double.self, forKey: .latencyMinutes) ?? 0,
                  trend: try c.decodeIfPresent([TrendPoint].self, forKey: .trend) ?? [],
                  stageConfidence: try? c.decodeIfPresent(StageConfidence.self, forKey: .stageConfidence),
                  kindConfirmed: try c.decodeIfPresent(Bool.self, forKey: .kindConfirmed) ?? false)
    }
}

extension Workout {
    private enum TolerantKeys: String, CodingKey {
        case id, start, end, sport, source, strain, avgHR, maxHR, kcal, zoneMinutes, notes, externalIDs, externalApp, distanceMeters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TolerantKeys.self)
        self.init(id: try c.decodeIfPresent(Int64.self, forKey: .id),
                  start: try c.decode(Int.self, forKey: .start),
                  end: try c.decode(Int.self, forKey: .end),
                  sport: try c.decodeIfPresent(String.self, forKey: .sport) ?? "Actividad",
                  // A source written by a newer version falls back to "manual" instead of hiding the workout.
                  source: (try? c.decodeIfPresent(WorkoutSource.self, forKey: .source)) ?? .manual,
                  strain: try c.decodeIfPresent(Double.self, forKey: .strain) ?? 0,
                  avgHR: try c.decodeIfPresent(Double.self, forKey: .avgHR) ?? 0,
                  maxHR: try c.decodeIfPresent(Double.self, forKey: .maxHR) ?? 0,
                  kcal: try c.decodeIfPresent(Double.self, forKey: .kcal) ?? 0,
                  zoneMinutes: try c.decodeIfPresent([Double].self, forKey: .zoneMinutes) ?? [0, 0, 0, 0, 0],
                  notes: try c.decodeIfPresent(String.self, forKey: .notes) ?? "",
                  externalIDs: try c.decodeIfPresent([String: String].self, forKey: .externalIDs),
                  externalApp: try c.decodeIfPresent(String.self, forKey: .externalApp),
                  distanceMeters: try c.decodeIfPresent(Double.self, forKey: .distanceMeters))
    }
}
