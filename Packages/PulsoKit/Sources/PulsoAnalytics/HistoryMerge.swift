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
        let observed = all.suffix(400).compactMap(\.maxHR).filter { $0 < 230 }.max() ?? 0
        let maxHR = Double(profile.maxHROverride ?? Int(max(HeartRateModel.tanakaMax(age: profile.age), observed)))
        let filled = extra.map { d -> DaySummary in
            var d = d
            if d.vo2max == nil, let rhr = d.rhr {
                d.vo2max = Fitness.vo2max(maxHR: maxHR, restingHR: rhr).map { ($0 * 10).rounded() / 10 }
            }
            return d
        }
        return (measured + filled).sorted { $0.day < $1.day }
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
