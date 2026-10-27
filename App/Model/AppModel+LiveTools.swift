import Foundation
import PulsoStore
import PulsoAnalytics

/// A saved 60-second scan, orthostatic test or heart-rate-recovery test.
struct LiveTestRecord: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case scan, orthostatic, recovery, maxHR }
    var id: Date { date }
    var date: Date
    var kind: Kind
    /// Main number (scan: state 0–100; orthostatic: rise in bpm; recovery: drop at 60 s; max HR: peak).
    var value: Double
    var hr: Double?
    var rmssd: Double?
    var resp: Double?
    var stress: Double?
    var detail: String
}

/// «En vivo» tools: beat stream, live day strain, zone guard, laps and test history.
extension AppModel {
    /// Called from handleLive: each notification carries the R-R intervals that ended at `date`.
    func appendLiveBeats(rr: [Int], at date: Date) {
        var t = date.timeIntervalSince1970
        var new: [LiveMetrics.Beat] = []
        for v in rr.reversed() where v >= 250 && v <= 2500 {
            new.append(.init(t: t, rr: Double(v)))
            t -= Double(v) / 1000
        }
        liveBeats += new.reversed().filter { b in b.t > (liveBeats.last?.t ?? 0) + 0.05 }
        let cutoff = date.timeIntervalSince1970 - 360
        if let i = liveBeats.firstIndex(where: { $0.t >= cutoff }), i > 0 { liveBeats.removeFirst(i) }
    }

    func beats(since t: Date) -> [LiveMetrics.Beat] {
        liveBeats.filter { $0.t >= t.timeIntervalSince1970 }
    }

    /// Your calm, still daytime self (last two weeks), for the scan.
    var liveBaseline: LiveMetrics.Baseline {
        let recent = Array(days.suffix(14))
        return LiveMetrics.Baseline(calmHR: Stats.median(recent.compactMap(\.calmHR)),
                                    calmHRV: Stats.median(recent.compactMap(\.calmHRV)),
                                    restingHR: Stats.median(recent.compactMap(\.rhr)),
                                    nightHRV: Stats.median(recent.compactMap(\.hrv)))
    }

    /// Today's strain plus what the live stream has added since the last download.
    var liveDayStrain: Double? {
        guard let base = today?.strain ?? (liveExtraLoad > 0 ? 0 : nil) else { return nil }
        return Strain.score(load: Strain.load(score: base) + liveExtraLoad)
    }

    /// Live load and zone guard, per live sample.
    func trackLive(heartRate: Int, dt: Double) {
        let p = heartRateModel.reserveFraction(Double(heartRate))
        liveExtraLoad += Strain.weight(reserveFraction: p) * dt / 60
        guard liveWorkout != nil, var g = zoneGuard else { return }
        let cue = g.update(hr: Double(heartRate), at: Date().timeIntervalSince1970)
        zoneGuard = g
        switch cue {
        case .tooHigh?:
            strap.buzz(loops: 3)
            if settings.voiceCues { voice.say("Baja el ritmo") }
        case .tooLow?:
            strap.buzz(loops: 1)
            if settings.voiceCues { voice.say("Sube el ritmo") }
        case .backIn?:
            if settings.voiceCues { voice.say("En zona") }
        case nil:
            break
        }
    }

    /// Target band for the current workout (nil = off).
    func setTargetZone(_ zone: Int?) {
        guard var w = liveWorkout else { return }
        w.targetZone = zone
        liveWorkout = w
        if let z = zone {
            let m = heartRateModel
            zoneGuard = LiveMetrics.ZoneGuard(low: m.zoneFloor(z), high: z >= 5 ? m.maxHR : m.zoneFloor(z + 1))
        } else {
            zoneGuard = nil
        }
    }

    /// Stats of the lap that just ended (from the stored live stream).
    func lapSummary(from start: Int, to end: Int) -> LiveMetrics.Lap {
        let rows = (try? db.liveHR(from: start, to: end)) ?? []
        let s = rows.map { (t: Double($0.ts), hr: Double($0.hr)) }
        return LiveMetrics.laps(s, marks: [], start: Double(start), end: Double(end)).first
            ?? LiveMetrics.Lap(start: Double(start), end: Double(end), avgHR: nil, maxHR: nil)
    }

    /// Heart-rate samples (1 Hz) stored since `t`, for the tests.
    func liveSamples(since t: Date) -> [(t: Double, hr: Double)] {
        ((try? db.liveHR(from: Int(t.timeIntervalSince1970), to: Int(Date().timeIntervalSince1970) + 1)) ?? [])
            .map { (t: Double($0.ts), hr: Double($0.hr)) }
    }

    // MARK: History

    var liveTests: [LiveTestRecord] { db.get([LiveTestRecord].self, for: "live.tests") ?? [] }

    func saveLiveTest(_ r: LiveTestRecord) {
        var all = liveTests
        all.append(r)
        try? db.set(Array(all.suffix(500)), for: "live.tests")
        objectWillChange.send()
    }

    /// Workouts of a month and the one before (for the monthly report).
    func monthWorkouts(_ month: String) -> [Workout] {
        guard let from = DayKey.date(MonthlyReport.shiftMonth(month, -1) + "-01"),
              let to = DayKey.date(MonthlyReport.shiftMonth(month, 1) + "-01") else { return [] }
        return (try? db.workouts(from: Int(from.timeIntervalSince1970), to: Int(to.timeIntervalSince1970))) ?? []
    }

    func setMaxHR(_ bpm: Int) {
        var p = profile
        p.maxHROverride = bpm
        saveProfile(p)
    }
}
