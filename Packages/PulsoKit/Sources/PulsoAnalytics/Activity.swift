import Foundation
import PulsoStore

/// Heart-rate reserve helpers (Karvonen).
public struct HeartRateModel: Equatable {
    public var restingHR: Double
    public var maxHR: Double

    public init(restingHR: Double, maxHR: Double) {
        self.restingHR = restingHR
        self.maxHR = max(maxHR, restingHR + 40)
    }

    /// Tanaka (2001): 208 − 0.7 × age.
    public static func tanakaMax(age: Int) -> Double { 208 - 0.7 * Double(age) }

    public func reserveFraction(_ hr: Double) -> Double {
        (hr - restingHR) / (maxHR - restingHR)
    }

    /// Zone 1…5 for 50–60 / 60–70 / 70–80 / 80–90 / 90–100 % HRR; 0 below 50 %.
    public func zone(_ hr: Double) -> Int {
        let p = reserveFraction(hr)
        if p < 0.5 { return 0 }
        return min(5, Int((p - 0.5) * 10) + 1)
    }

    /// Lower HR bound of zone `z` (1…5).
    public func zoneFloor(_ z: Int) -> Double {
        restingHR + (0.4 + 0.1 * Double(z)) * (maxHR - restingHR)
    }
}

/// Cardiovascular load → Strain on a 0–21 logarithmic scale.
public enum Strain {
    /// Per-minute load weight. Everyday heart rate (15–40 % HRR) adds a little (up to 0.08/min) so a
    /// rest day still lands around 5–8, like moving about all day does; from 40 % HRR it rises by 1
    /// per 10 % HRR (Edwards-style, continuous).
    public static func weight(reserveFraction p: Double) -> Double {
        if p < 0.15 { return 0 }
        if p < 0.4 { return 0.08 * (p - 0.15) / 0.25 }
        return Stats.clamp(0.08 + (p - 0.4) * 10, 0, 6)
    }

    /// The load (TRIMP-like) at which strain reaches 21.
    public static let ceilingLoad = 4000.0

    public static func score(load: Double) -> Double {
        guard load > 0 else { return 0 }
        return Stats.clamp(21 * log(1 + load) / log(1 + ceilingLoad), 0, 21)
    }

    public struct Result: Equatable {
        public var load: Double
        public var strain: Double
        public var zoneMinutes: [Double]
        public var avgHR: Double?
        public var maxHR: Double?
    }

    /// Accumulates load over worn minutes of `epochs`.
    public static func compute(_ epochs: [MinuteEpoch], model: HeartRateModel) -> Result {
        var load = 0.0
        var zones = [Double](repeating: 0, count: 5)
        var hrs: [Double] = []
        for e in epochs where e.worn {
            guard let hr = e.hr else { continue }
            hrs.append(hr)
            let p = model.reserveFraction(hr)
            load += weight(reserveFraction: p)
            let z = model.zone(hr)
            if z > 0 { zones[z - 1] += 1 }
        }
        // Peak = best sustained minute (robust to single-second spikes).
        return Result(load: load, strain: score(load: load), zoneMinutes: zones,
                      avgHR: Stats.mean(hrs), maxHR: hrs.max())
    }
}

/// Energy expenditure: Mifflin-St Jeor BMR at rest, Keytel (2005) HR equation when active.
public enum Calories {
    public static func bmrPerDay(_ p: Profile) -> Double {
        let base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age)
        switch p.sex {
        case .male: return base + 5
        case .female: return base - 161
        case .other: return base - 78
        }
    }

    /// kcal/min from HR (Keytel 2005).
    public static func keytelPerMinute(hr: Double, _ p: Profile) -> Double {
        let w = p.weightKg, a = Double(p.age)
        let male = (-55.0969 + 0.6309 * hr + 0.1988 * w + 0.2017 * a) / 4.184
        let female = (-20.4022 + 0.4472 * hr - 0.1263 * w + 0.074 * a) / 4.184
        switch p.sex {
        case .male: return max(0, male)
        case .female: return max(0, female)
        case .other: return max(0, (male + female) / 2)
        }
    }

    /// Total and active kcal over the epochs; minutes with no data are billed at BMR.
    public static func compute(_ epochs: [MinuteEpoch], profile: Profile, model: HeartRateModel,
                               activeWindows: [ClosedRange<Int>] = []) -> (total: Double, active: Double) {
        let bmrMin = bmrPerDay(profile) / 1440
        var total = 0.0, active = 0.0
        for e in epochs {
            guard e.worn, let hr = e.hr else {
                total += bmrMin
                continue
            }
            let p = model.reserveFraction(hr)
            let inWorkout = activeWindows.contains { $0.contains(e.ts) }
            if p >= 0.5 || (inWorkout && p >= 0.3) {
                let k = max(bmrMin, keytelPerMinute(hr: hr, profile))
                total += k
                active += k - bmrMin
            } else {
                total += bmrMin
            }
        }
        return (total, active)
    }
}

/// Automatic workout detection from sustained elevated heart rate (+ motion when available).
public enum WorkoutDetector {
    public struct Bout: Equatable {
        public var start: Int
        public var end: Int
        public var sport: String
    }

    public static func detect(_ epochs: [MinuteEpoch], model: HeartRateModel, stillThreshold: Double,
                              minMinutes: Int = 12) -> [Bout] {
        var active = [Bool](repeating: false, count: epochs.count)
        for (i, e) in epochs.enumerated() where e.worn {
            guard let hr = e.hr else { continue }
            let p = model.reserveFraction(hr)
            let moving = (e.motion ?? 0) > stillThreshold * 2 || (e.activityClass ?? 0) > 0 || e.stepsDelta > 20
            active[i] = p >= 0.55 || (p >= 0.40 && moving)
        }
        var bouts: [Bout] = []
        var i = 0
        while i < epochs.count {
            guard active[i] else { i += 1; continue }
            var j = i
            var gap = 0
            var k = i
            while k < epochs.count {
                if active[k] {
                    j = k
                    gap = 0
                } else {
                    gap += 1
                    if gap > 3 { break }
                }
                k += 1
            }
            let len = j - i + 1
            if len >= minMinutes {
                let window = Array(epochs[i...j])
                let hrs = window.compactMap { $0.hr }
                let meanP = Stats.mean(hrs.map { model.reserveFraction($0) }) ?? 0
                if meanP >= 0.42 {
                    bouts.append(Bout(start: epochs[i].ts, end: epochs[j].ts + 60, sport: guessSport(window)))
                }
            }
            i = j + 1
        }
        return bouts
    }

    static func guessSport(_ w: [MinuteEpoch]) -> String {
        let classes = w.compactMap { $0.activityClass }
        let steps = w.reduce(0) { $0 + $1.stepsDelta }
        let cadence = Double(steps) / Double(max(1, w.count))
        if classes.filter({ $0 == 2 }).count > classes.count / 2 || cadence > 130 { return "Carrera" }
        if classes.filter({ $0 == 1 }).count > classes.count / 2 || cadence > 70 { return "Caminata" }
        let motion = Stats.mean(w.compactMap { $0.motion }) ?? 0
        if motion < 0.08 { return "Ciclismo" }
        return "Actividad"
    }
}

/// Energy / cardiovascular fitness estimates.
public enum Fitness {
    /// Uth et al. (2004): VO₂max ≈ 15.3 × HRmax / HRrest (ml/kg/min).
    public static func vo2max(maxHR: Double, restingHR: Double) -> Double? {
        guard restingHR > 25 else { return nil }
        let v = 15.3 * maxHR / restingHR
        return (15...90).contains(v) ? v : nil
    }

    /// Age at which a population-average person has this VO₂max (Jackson non-exercise norms, simplified).
    public static func fitnessAge(vo2max: Double, sex: Sex) -> Int {
        // Average VO₂max declines ≈ 0.4 ml/kg/min per year from ≈ 47 (men) / 39 (women) at age 20.
        let base = sex == .female ? 39.0 : (sex == .male ? 47.0 : 43.0)
        let age = 20 + (base - vo2max) / 0.4
        return Int(Stats.clamp(age, 18, 90).rounded())
    }
}
