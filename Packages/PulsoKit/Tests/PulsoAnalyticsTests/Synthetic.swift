import Foundation
import WhoopProtocol
import PulsoStore

/// Generates physiologically-shaped 1 Hz strap data (what the v18 offload would give us) so the
/// whole pipeline can be exercised deterministically.
struct SyntheticStrap {
    var rng = LCG(seed: 42)
    var beatClock: Double = 0
    var stepCounter: UInt16 = 1000

    struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func normal() -> Double {
            let u1 = max(next(), 1e-12), u2 = next()
            return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
        }
    }

    enum Phase {
        case awake(hr: Double, motion: Double)
        case workout(hr: Double)
        case sleep(stage: Int, baseHR: Double, rsa: Double) // 1 light 2 deep 3 rem
        case off
    }

    /// One second of data. `rsa` = relative RR modulation depth at the breathing frequency.
    mutating func second(_ t: Int, _ phase: Phase, respHz: Double = 0.233) -> HistorySample {
        var hr: Double
        var motion: Double
        var rsa: Double
        var sleepState: UInt8 = 1
        var activity: UInt8 = 0
        var stepInc: UInt16 = 0
        switch phase {
        case .off:
            return HistorySample(unix: UInt32(t), offWrist: true)
        case .awake(let h, let m):
            hr = h + rng.normal() * 3
            motion = max(0.02, m + rng.normal() * m * 0.4)
            rsa = 0.03
            if m > 0.1 && rng.next() < 0.3 { stepInc = 1 }
        case .workout(let h):
            hr = h + rng.normal() * 4
            motion = 0.9 + rng.normal() * 0.2
            rsa = 0.005
            activity = 2
            stepInc = rng.next() < 0.5 ? 3 : 2
        case .sleep(let stage, let base, let r):
            sleepState = 2
            switch stage {
            case 2: hr = base - 3 + rng.normal() * 0.5; rsa = r * 1.3; motion = 0.008
            case 3: hr = base + 6 + rng.normal() * 3.5; rsa = r * 0.7; motion = 0.007
            default: hr = base + 1 + rng.normal() * 1.5; rsa = r; motion = 0.01
            }
            if rng.next() < 0.004 { motion = 0.2 }
        }
        stepCounter = stepCounter &+ stepInc
        // Beats inside [t, t+1).
        var rr: [UInt16] = []
        if beatClock < Double(t) { beatClock = Double(t) + rng.next() * 0.5 }
        while beatClock < Double(t + 1) {
            let base = 60.0 / hr
            let interval = base * (1 + rsa * sin(2 * Double.pi * respHz * beatClock)) + rng.normal() * 0.004
            beatClock += interval
            if rr.count < 4 { rr.append(UInt16(max(300, min(2000, interval * 1000)))) }
        }
        let g = SIMD3<Float>(0.1, 0.2, 0.97)
        return HistorySample(
            unix: UInt32(t), recordIndex: UInt32(t), heartRate: UInt8(max(30, min(220, hr.rounded()))), rr: rr,
            gravity: g, dynamicAccelG: Float(motion), skinTempC: sleepState == 2 ? 34.6 : 33.2,
            spo2: sleepState == 2 ? 96 : nil, steps: stepCounter, activityClass: activity, sleepState: sleepState,
            signalFlags: 0, signalQuality: 255, signalPoor: false, offWrist: false)
    }

    /// A full day: awake from `wake`, a 45-min run at wake+9h, bed at 23:00 local, sleep until 07:00.
    /// Sleep cycles of 90 min: deep early, REM late.
    mutating func day(startingAt dayStart: Int, restingHR: Double = 54, rsa: Double = 0.06) -> [HistorySample] {
        var out: [HistorySample] = []
        let wake = dayStart + 7 * 3600
        let bed = dayStart + 23 * 3600
        let nextWake = dayStart + 31 * 3600
        for t in wake..<bed {
            let workoutStart = wake + 9 * 3600
            if t >= workoutStart && t < workoutStart + 45 * 60 {
                out.append(second(t, .workout(hr: 155)))
            } else {
                let hourOfDay = (t - dayStart) / 3600
                let desk = (9..<13).contains(hourOfDay) || (18..<21).contains(hourOfDay)
                out.append(second(t, .awake(hr: desk ? 70 : 78, motion: desk ? 0.035 : 0.15)))
            }
        }
        for t in bed..<nextWake {
            let minute = (t - bed) / 60
            let cyclePos = minute % 90
            let cycle = minute / 90
            let stage: Int
            if minute < 12 {
                out.append(second(t, .awake(hr: 64, motion: 0.03)))
                continue
            } else if cyclePos < 20 && cycle < 3 {
                stage = 2
            } else if cyclePos >= 70 || (cycle >= 3 && cyclePos >= 55) {
                stage = 3
            } else {
                stage = 1
            }
            out.append(second(t, .sleep(stage: stage, baseHR: restingHR, rsa: rsa)))
        }
        return out
    }
}
