import Foundation
import WhoopProtocol
import PulsoStore

/// Fills the database with a realistic, varied stretch of strap data so every screen can be seen
/// and tried without a strap: nights of different quality, workouts, rest days, a couple of nights
/// after alcohol, journal entries and, at the end, two nights of "incubating something".
/// Deterministic (same seed → same data). Everything it writes can be wiped with `eraseAll`.
public enum DemoData {
    public static let flagKey = "demo.active"

    struct RNG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func normal() -> Double {
            let u1 = max(next(), 1e-12), u2 = next()
            return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
        }
        mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    }

    /// How one demo day goes.
    struct DayPlan {
        var bedMinute: Double        // minutes after the day's midnight (e.g. 23*60+15)
        var sleepHours: Double
        var restingHR: Double
        var rsa: Double              // breathing-linked RR modulation → HRV
        var nightTemp: Double
        var workout: (startHour: Double, minutes: Int, hr: Double)?
        var alcohol: Bool
        var lateCaffeine: Bool
        var meditation: Bool
    }

    static func plans(days: Int, rng: inout RNG) -> [DayPlan] {
        (0..<days).map { i in
            let sickTail = i >= days - 2
            let alcohol = !sickTail && (i % 7 == 5 || i % 11 == 3)
            let rest = i % 7 == 6 || sickTail
            let hard = !rest && (i % 3 == 0)
            var workout: (Double, Int, Double)? = nil
            if !rest {
                workout = (rng.range(7.5, 19), Int(rng.range(35, hard ? 80 : 55)), hard ? rng.range(158, 168) : rng.range(132, 148))
            }
            let baseRHR = 53 + rng.normal() * 1.2
            return DayPlan(
                bedMinute: 23 * 60 + rng.range(-35, alcohol ? 75 : 40),
                sleepHours: alcohol ? rng.range(5.8, 6.6) : rng.range(6.8, 8.2),
                restingHR: baseRHR + (alcohol ? 6 : 0) + (sickTail ? 7 : 0) + (hard ? 1 : 0),
                rsa: (alcohol ? 0.035 : 0.065) * (sickTail ? 0.6 : 1) * rng.range(0.85, 1.15),
                nightTemp: 34.5 + rng.normal() * 0.06 + (sickTail ? 0.75 : 0) + (alcohol ? 0.2 : 0),
                workout: workout,
                alcohol: alcohol,
                lateCaffeine: i % 4 == 1,
                meditation: i % 5 == 2
            )
        }
    }

    /// Per-second generator, same physiology as the test suite's synthetic strap.
    struct Strap {
        var rng: RNG
        var beatClock = 0.0
        var steps: UInt16 = 1000

        enum Phase {
            case awake(hr: Double, motion: Double)
            case workout(hr: Double)
            case sleep(stage: Int, baseHR: Double, rsa: Double, temp: Double)
        }

        mutating func second(_ t: Int, _ phase: Phase) -> HistorySample {
            var hr: Double, motion: Double, rsa: Double
            var sleepState: UInt8 = 1, activity: UInt8 = 0, inc: UInt16 = 0
            var temp: Float = 33.2
            var spo2: UInt8?
            switch phase {
            case .awake(let h, let m):
                hr = h + rng.normal() * 3
                motion = max(0.02, m + rng.normal() * m * 0.4)
                rsa = 0.03
                if m > 0.1 && rng.next() < 0.3 { inc = 1 }
            case .workout(let h):
                hr = h + rng.normal() * 4
                motion = 0.9 + rng.normal() * 0.2
                rsa = 0.005
                activity = 2
                inc = rng.next() < 0.5 ? 3 : 2
            case .sleep(let stage, let base, let r, let tp):
                sleepState = 2
                temp = Float(tp + rng.normal() * 0.03)
                spo2 = UInt8(max(90, min(99, 96 + rng.normal() * 0.8)))
                switch stage {
                case 2: hr = base - 3 + rng.normal() * 0.5; rsa = r * 1.3; motion = 0.008
                case 3: hr = base + 6 + rng.normal() * 3.5; rsa = r * 0.7; motion = 0.007
                default: hr = base + 1 + rng.normal() * 1.5; rsa = r; motion = 0.01
                }
                if rng.next() < 0.004 { motion = 0.2 }
            }
            steps = steps &+ inc
            var rr: [UInt16] = []
            if beatClock < Double(t) { beatClock = Double(t) + rng.next() * 0.5 }
            while beatClock < Double(t + 1) {
                let interval = 60.0 / hr * (1 + rsa * sin(2 * Double.pi * 0.233 * beatClock)) + rng.normal() * 0.004
                beatClock += interval
                if rr.count < 4 { rr.append(UInt16(max(300, min(2000, interval * 1000)))) }
            }
            return HistorySample(unix: UInt32(t), recordIndex: UInt32(t), heartRate: UInt8(max(30, min(220, hr.rounded()))), rr: rr,
                                 gravity: SIMD3<Float>(0.1, 0.2, 0.97), dynamicAccelG: Float(motion), skinTempC: temp, spo2: spo2,
                                 steps: steps, activityClass: activity, sleepState: sleepState, signalFlags: 0, signalQuality: 255)
        }
    }

    /// Writes `days` days of seconds ending now, the matching journal, and runs the analysis.
    /// `progress` goes 0…1 (generation is the first half, analysis the second).
    @discardableResult
    public static func populate(db: PulsoDatabase, days: Int = 21, now: Date = Date(), calendar: Calendar = .current,
                                seed: UInt64 = 2026, progress: ((Double) -> Void)? = nil) throws -> [DaySummary] {
        var rng = RNG(state: seed)
        let plans = plans(days: days, rng: &rng)
        var strap = Strap(rng: RNG(state: seed &+ 1))
        let today = calendar.startOfDay(for: now)
        let nowTs = Int(now.timeIntervalSince1970)
        var buffer: [HistorySample] = []
        buffer.reserveCapacity(20_000)
        func flush() throws {
            try db.insert(buffer)
            buffer.removeAll(keepingCapacity: true)
        }

        for (i, plan) in plans.enumerated() {
            // Day i: the night that starts on day (i - days) and the following day until the next bedtime.
            guard let dayDate = calendar.date(byAdding: .day, value: i - days, to: today) else { continue }
            let midnight = Int(dayDate.timeIntervalSince1970)
            let bed = midnight + Int(plan.bedMinute * 60)
            let wake = bed + Int(plan.sleepHours * 3600)
            let nextBed = i + 1 < plans.count ? midnight + 86400 + Int(plans[i + 1].bedMinute * 60) : nowTs
            // Night: 90-minute cycles, deep early, REM late, a short awakening now and then.
            var t = bed
            while t < min(wake, nowTs) {
                let minute = (t - bed) / 60
                let pos = minute % 90, cycle = minute / 90
                if minute < 12 || (pos == 45 && cycle >= 2 && minute % 3 == 0) {
                    buffer.append(strap.second(t, .awake(hr: plan.restingHR + 10, motion: 0.03)))
                } else {
                    let stage = (pos < 20 && cycle < 3) ? 2 : ((pos >= 70 || (cycle >= 3 && pos >= 55)) ? 3 : 1)
                    buffer.append(strap.second(t, .sleep(stage: stage, baseHR: plan.restingHR, rsa: plan.rsa, temp: plan.nightTemp)))
                }
                t += 1
                if buffer.count >= 20_000 { try flush() }
            }
            // Day.
            t = wake
            let workoutStart = plan.workout.map { midnight + 86400 * (wake >= midnight + 86400 ? 1 : 0) + Int($0.startHour * 3600) }
            while t < min(nextBed, nowTs) {
                if let w = plan.workout, let ws = workoutStart, t >= ws, t < ws + w.minutes * 60 {
                    buffer.append(strap.second(t, .workout(hr: w.hr)))
                } else {
                    let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(t)))
                    let desk = (9..<13).contains(hour) || (15..<18).contains(hour)
                    buffer.append(strap.second(t, .awake(hr: desk ? 70 : 78, motion: desk ? 0.035 : 0.15)))
                }
                t += 1
                if buffer.count >= 20_000 { try flush() }
            }
            try flush()
            // Journal: the evening's habits are logged on the day the night starts (their effect shows
            // in the next day's recovery, which is what Insights measures).
            let journalDay = DayKey.string(dayDate, calendar: calendar)
            if plan.alcohol { try db.setJournal(day: journalDay, key: "alcohol", value: 1) }
            if plan.lateCaffeine { try db.setJournal(day: journalDay, key: "late_caffeine", value: 1) }
            if plan.meditation { try db.setJournal(day: journalDay, key: "meditation", value: 1) }
            if plan.workout.map({ $0.hr > 155 }) == true { try db.setJournal(day: journalDay, key: "hard_training", value: 1) }
            progress?(Double(i + 1) / Double(days) * 0.5)
        }
        try db.set(true, for: flagKey)
        let engine = DayEngine(db: db, calendar: calendar)
        return try engine.recompute(fromDay: nil, now: now, progress: { p in progress?(0.5 + p * 0.5) })
    }

    public static func isActive(_ db: PulsoDatabase) -> Bool { db.get(Bool.self, for: flagKey) ?? false }
}
