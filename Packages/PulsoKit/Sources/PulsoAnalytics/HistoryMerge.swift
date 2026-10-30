import Foundation
import PulsoStore

/// Days measured by the strap plus days imported from WHOOP, as one history for every screen and analysis.
public enum HistoryMerge {
    /// Measured days win; imported days fill the gaps. Imported days get the VO₂max the strap would have
    /// estimated for them (Uth: 15.3 × max HR / resting HR) with the same max HR the rest of the app uses.
    public static func days(measured: [DaySummary], imported: [DaySummary], profile: Profile) -> [DaySummary] {
        let have = Set(measured.map(\.day))
        let extra = imported.filter { !have.contains($0.day) }
        let all = measured + extra
        let maxHR = HeartRateModel.maxHR(override: profile.maxHROverride, age: profile.age,
                                         dailyPeaks: all.suffix(400).compactMap(\.maxHR))
        let filled = extra.map { d -> DaySummary in
            var d = d
            if d.vo2max == nil, let rhr = d.rhr {
                d.vo2max = Fitness.vo2max(maxHR: maxHR, restingHR: rhr).map { ($0 * 10).rounded() / 10 }
            }
            return d
        }
        // A measured day without its night (the strap was put on after waking): last night and its recovery come
        // from the import instead of being left empty or computed from a daytime rest.
        let importedByDay = Dictionary(imported.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let completed = measured.map { m -> DaySummary in
            guard m.sleepStart == nil, m.recovery == nil, let i = importedByDay[m.day], i.recovery != nil else { return m }
            var d = m
            d.recovery = i.recovery; d.hrv = i.hrv; d.rhr = i.rhr; d.respRate = i.respRate; d.spo2 = i.spo2
            d.skinTemp = i.skinTemp; d.sleepStart = i.sleepStart; d.sleepEnd = i.sleepEnd
            d.sleepMinutes = i.sleepMinutes; d.inBedMinutes = i.inBedMinutes; d.deepMinutes = i.deepMinutes
            d.remMinutes = i.remMinutes; d.lightMinutes = i.lightMinutes; d.awakeMinutes = i.awakeMinutes
            d.disturbances = i.disturbances; d.sleepPerformance = i.sleepPerformance; d.sleepEfficiency = i.sleepEfficiency
            d.sleepConsistency = i.sleepConsistency; d.sleepNeedMinutes = i.sleepNeedMinutes; d.sleepDebtMinutes = i.sleepDebtMinutes
            d.restorativeMinutes = i.restorativeMinutes
            d.nightImported = true
            return d
        }
        return (completed + filled).sorted { $0.day < $1.day }
    }

    /// Imported nights as sleep periods (bed and wake times; stages unknown, counted as light sleep) so the
    /// timing analyses — regularity, social jet lag, rhythm — can use the WHOOP history too.
    public static func sleeps(from imported: [DaySummary], excluding measured: Set<String>) -> [SleepSession] {
        imported.compactMap { d in measured.contains(d.day) ? nil : summarySleep(d) }
    }

    /// A night rebuilt from a day's totals (imported days, or days whose minute-by-minute session is missing):
    /// stage minutes, disturbances and vitals, with every minute marked light because the order is unknown.
    public static func summarySleep(_ d: DaySummary) -> SleepSession? {
        guard let a = d.sleepStart, let b = d.sleepEnd, b - a >= 3600, b - a <= 16 * 3600 else { return nil }
        let minutes = (b - a) / 60
        let asleep = min(Double(minutes), d.sleepMinutes ?? Double(minutes))
        var s = SleepSession(start: a, end: b, stages: Array(repeating: .light, count: minutes))
        let deep = d.deepMinutes ?? 0, rem = d.remMinutes ?? 0
        if deep + rem > 0, let light = d.lightMinutes {
            s.minutesLight = light
            s.minutesDeep = deep
            s.minutesREM = rem
            s.minutesAwake = d.awakeMinutes ?? max(0, Double(minutes) - light - deep - rem)
        } else {
            s.minutesLight = asleep
            s.minutesAwake = max(0, Double(minutes) - asleep)
        }
        s.disturbances = d.disturbances ?? 0
        s.rhr = d.rhr
        s.hrv = d.hrv
        s.respRate = d.respRate
        s.spo2 = d.spo2
        s.skinTemp = d.skinTemp
        return s
    }
}
