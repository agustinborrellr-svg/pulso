import Foundation
import PulsoStore

/// Turns raw strap seconds into nights, days, workouts and scores, and stores them.
///
/// A "day" D is a physiological cycle: it starts when the main sleep ending on D ends and runs until
/// the next main sleep starts (or now). Recovery for D comes from that main sleep; Strain accumulates
/// over the cycle.
public final class DayEngine {
    public let db: PulsoDatabase
    public var calendar: Calendar

    public init(db: PulsoDatabase, calendar: Calendar = .current) {
        self.db = db
        self.calendar = calendar
    }

    /// Keeps a few whole local days of raw samples in memory so consecutive day windows (which
    /// overlap by ~26 h) don't reload the same rows.
    private var chunks: [Int: [Sample]] = [:]

    private func loadSamples(from: Int, to: Int) throws -> [Sample] {
        var out: [Sample] = []
        var dayStart = Int(calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(from))).timeIntervalSince1970)
        var used: [Int] = []
        while dayStart < to {
            let next = Int((calendar.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: TimeInterval(dayStart)))
                ?? Date(timeIntervalSince1970: TimeInterval(dayStart + 86400))).timeIntervalSince1970)
            if chunks[dayStart] == nil {
                chunks[dayStart] = try db.samples(from: dayStart, to: next)
            }
            out += Epochs.slice(chunks[dayStart] ?? [], from: max(from, dayStart), to: min(to, next))
            used.append(dayStart)
            dayStart = next
        }
        // Evict chunks that fall before this window (days are processed in order).
        for key in chunks.keys where key < (used.first ?? 0) { chunks[key] = nil }
        return out
    }

    private func ts(_ day: String, hour: Double) -> Int {
        let d = DayKey.date(day, calendar: calendar) ?? Date()
        return Int(d.timeIntervalSince1970 + hour * 3600)
    }

    /// Recomputes every day from `fromDay` (default: first day with data) through today.
    @discardableResult
    public func recompute(fromDay: String? = nil, now: Date = Date(), progress: ((Double) -> Void)? = nil) throws -> [DaySummary] {
        guard let bounds = try db.sampleBounds() else { return [] }
        chunks.removeAll()
        defer { chunks.removeAll() }
        let firstDay = DayKey.string(ts: bounds.first, calendar: calendar)
        let today = DayKey.string(now, calendar: calendar)
        var day = max(fromDay ?? firstDay, firstDay)
        guard day <= today else { return [] }

        let profile = db.profile
        var past = try history(before: day)
        var results: [DaySummary] = []
        let totalDays = max(1, daysBetween(day, today) + 1)
        var done = 0

        while day <= today {
            if let summary = try computeDay(day, profile: profile, past: past, now: now) {
                try db.save(summary)
                past.append(summary)
                results.append(summary)
            }
            done += 1
            progress?(Double(done) / Double(totalDays))
            day = DayKey.shift(day, days: 1, calendar: calendar)
        }

        // Raw-data retention: summaries are kept, raw seconds older than the window are dropped.
        let cutoff = Int(now.timeIntervalSince1970) - profile.rawRetentionDays * 86400
        if profile.rawRetentionDays > 0 { try db.pruneSamples(olderThan: cutoff) }
        return results
    }

    private func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = DayKey.date(a, calendar: calendar), let dbb = DayKey.date(b, calendar: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: da, to: dbb).day ?? 0
    }

    /// Computed days before `day`, with imported WHOOP days filling gaps (they seed the baselines).
    func history(before day: String) throws -> [DaySummary] {
        let computed = try db.days(from: "0000-00-00", to: DayKey.shift(day, days: -1, calendar: calendar))
        let have = Set(computed.map { $0.day })
        let imported = try db.importedDays().filter { $0.day < day && !have.contains($0.day) }
        return (computed + imported).sorted { $0.day < $1.day }
    }

    func heartRateModel(profile: Profile, past: [DaySummary]) -> HeartRateModel {
        let recent = Array(past.suffix(30))
        let rhr = Baseline.from(recent.compactMap { $0.rhr }, floor: 1)?.center ?? 60
        let observed = past.suffix(180).compactMap { $0.maxHR }.max() ?? 0
        let maxHR = Double(profile.maxHROverride ?? Int(max(HeartRateModel.tanakaMax(age: profile.age), observed)))
        return HeartRateModel(restingHR: rhr, maxHR: maxHR)
    }

    /// Picks the main sleep ending on `day` from detected blocks (absolute ts ranges).
    func mainSleep(for day: String, blocks: [(start: Int, end: Int)]) -> (start: Int, end: Int)? {
        let lo = ts(day, hour: 0), hi = ts(day, hour: 16)
        let candidates = blocks.filter { $0.end > lo && $0.end <= hi && $0.end - $0.start >= 60 * 60 }
        guard var main = candidates.max(by: { ($0.end - $0.start) < ($1.end - $1.start) }) else { return nil }
        // Fold in neighbouring blocks separated by a long awakening (≤ 90 min) on the same night.
        var changed = true
        while changed {
            changed = false
            for b in blocks where !(b.start == main.start && b.end == main.end) {
                let gapBefore = main.start - b.end, gapAfter = b.start - main.end
                if (gapBefore >= 0 && gapBefore <= 90 * 60 && b.end - b.start >= 20 * 60 && b.start >= lo - 14 * 3600)
                    || (gapAfter >= 0 && gapAfter <= 90 * 60 && b.end <= hi && b.end - b.start >= 20 * 60) {
                    main = (min(main.start, b.start), max(main.end, b.end))
                    changed = true
                }
            }
        }
        return main
    }

    func detectBlocks(samples: [Sample], from: Int, to: Int) -> (blocks: [(start: Int, end: Int)], stillThreshold: Double) {
        let epochs = Epochs.minutes(samples, from: from, to: to)
        let thr = SleepDetector.stillThreshold(epochs)
        let blocks = SleepDetector.blocks(epochs).map { b in
            (start: epochs[b.startIndex].ts, end: epochs[b.endIndex].ts + 60)
        }
        return (blocks, thr)
    }

    func computeDay(_ day: String, profile: Profile, past: [DaySummary], now: Date) throws -> DaySummary? {
        let nowTs = Int(now.timeIntervalSince1970)
        let loadFrom = ts(day, hour: -12), loadTo = min(nowTs + 60, ts(day, hour: 38))
        guard loadTo > loadFrom else { return nil }
        let samples = try loadSamples(from: loadFrom, to: loadTo)
        guard samples.count >= 600 else { return nil }

        let (blocks, stillThr) = detectBlocks(samples: samples, from: loadFrom, to: loadTo)

        // Main sleep: a manual edit wins over detection.
        let dayStart = ts(day, hour: 0), mainHi = ts(day, hour: 16)
        let existing = try db.sleeps(from: ts(day, hour: -12), to: ts(day, hour: 24))
        let manualMain = existing.first { $0.manual && !$0.isNap && $0.end > dayStart && $0.end <= mainHi }
        let detectedMain = mainSleep(for: day, blocks: blocks)
        let mainBounds: (start: Int, end: Int)? = manualMain.map { ($0.start, $0.end) } ?? detectedMain

        // Replace this day's automatic sessions.
        try db.sql.run("DELETE FROM sleeps WHERE manual = 0 AND is_nap = 0 AND end > ? AND end <= ?",
                       [.int(Int64(dayStart)), .int(Int64(mainHi))])
        let napLo = ts(day, hour: 10), napHi = ts(day, hour: 22), dayEnd = ts(day, hour: 24)
        try db.sql.run("DELETE FROM sleeps WHERE manual = 0 AND is_nap = 1 AND start >= ? AND start < ?",
                       [.int(Int64(napLo)), .int(Int64(napHi))])

        var main: SleepSession?
        if let mb = mainBounds {
            var s = SleepAnalyzer.analyze(samples: samples, start: mb.start, end: mb.end, isNap: false,
                                          manual: manualMain != nil, stillThreshold: stillThr, existingID: manualMain?.id)
            s.id = try db.save(s)
            main = s
        }

        var naps: [SleepSession] = []
        for b in blocks where b.start >= napLo && b.start < napHi && b.end <= dayEnd {
            let len = b.end - b.start
            guard len >= 15 * 60, len <= 180 * 60 else { continue }
            if let m = mainBounds, b.start < m.end && b.end > m.start { continue }
            var nap = SleepAnalyzer.analyze(samples: samples, start: b.start, end: b.end, isNap: true, manual: false, stillThreshold: stillThr)
            nap.id = try db.save(nap)
            naps.append(nap)
        }
        naps += existing.filter { $0.manual && $0.isNap && $0.start >= napLo && $0.start < napHi }

        // Cycle bounds.
        let cycleStart = main?.end ?? dayStart
        let nextDay = DayKey.shift(day, days: 1, calendar: calendar)
        let nextManual = try db.sleeps(from: ts(nextDay, hour: -12), to: ts(nextDay, hour: 16))
            .first { $0.manual && !$0.isNap && $0.end > ts(nextDay, hour: 0) }
        let nextMain = nextManual.map { ($0.start, $0.end) } ?? mainSleep(for: nextDay, blocks: blocks)
        var cycleEnd = nextMain.map { $0.0 } ?? ts(nextDay, hour: 4)
        cycleEnd = min(cycleEnd, nowTs)
        guard cycleEnd > cycleStart || main != nil else { return nil }

        var d = DaySummary(day: day)
        d.cycleStart = cycleStart
        d.cycleEnd = max(cycleEnd, cycleStart)

        let model = heartRateModel(profile: profile, past: past)
        let cycleEpochs = Epochs.minutes(Epochs.slice(samples, from: cycleStart, to: d.cycleEnd!), from: cycleStart, to: d.cycleEnd!)
        let worn = cycleEpochs.filter { $0.worn }
        d.wornMinutes = Double(worn.count)

        // Strain & activity.
        let strain = Strain.compute(cycleEpochs, model: model)
        d.strain = worn.count >= 30 ? (strain.strain * 10).rounded() / 10 : nil
        d.zoneMinutes = strain.zoneMinutes
        d.avgHR = strain.avgHR
        d.maxHR = strain.maxHR
        let stepTotal = cycleEpochs.reduce(0) { $0 + $1.stepsDelta }
        d.steps = stepTotal > 0 ? stepTotal : nil

        // Workouts: re-detect automatic ones, keep manual/live ones and refresh their metrics.
        try db.deleteAutoWorkouts(from: cycleStart, to: d.cycleEnd!)
        var workouts = try db.workouts(from: cycleStart, to: d.cycleEnd!)
        let userWindows = workouts.map { $0.start...$0.end }
        for bout in WorkoutDetector.detect(cycleEpochs, model: model, stillThreshold: stillThr)
        where !userWindows.contains(where: { $0.overlaps(bout.start...bout.end) }) {
            workouts.append(Workout(start: bout.start, end: bout.end, sport: bout.sport, source: .auto))
        }
        for i in workouts.indices {
            let w = workouts[i]
            let we = cycleEpochs.filter { $0.ts >= w.start && $0.ts < w.end }
            // An imported workout the strap barely saw keeps the other app's numbers.
            if w.source.isExternal && Double(we.filter { $0.worn }.count) < max(5, w.durationMinutes * 0.5) {
                continue
            }
            let ws = Strain.compute(we, model: model)
            workouts[i].strain = (ws.strain * 10).rounded() / 10
            workouts[i].zoneMinutes = ws.zoneMinutes
            workouts[i].avgHR = ws.avgHR ?? 0
            workouts[i].maxHR = ws.maxHR ?? 0
            workouts[i].kcal = Calories.compute(we, profile: profile, model: model, activeWindows: [w.start...w.end]).total
            workouts[i].id = try db.save(workouts[i])
        }
        d.workoutCount = workouts.count
        let workoutWindows = workouts.map { $0.start...$0.end }

        let energyFrom = main?.start ?? cycleStart
        let energyEpochs = Epochs.minutes(Epochs.slice(samples, from: energyFrom, to: d.cycleEnd!), from: energyFrom, to: d.cycleEnd!)
        let kcal = Calories.compute(energyEpochs, profile: profile, model: model, activeWindows: workoutWindows)
        d.kcal = kcal.total.rounded()
        d.activeKcal = kcal.active.rounded()

        // Sleep metrics.
        let pastWithSleep = past.filter { $0.sleepMinutes != nil }
        if let m = main {
            d.sleepId = m.id
            d.sleepStart = m.start
            d.sleepEnd = m.end
            d.sleepMinutes = m.asleepMinutes
            d.inBedMinutes = m.inBedMinutes
            d.sleepEfficiency = m.efficiency
            d.restorativeMinutes = m.restorativeMinutes
            d.deepMinutes = m.minutesDeep
            d.remMinutes = m.minutesREM
            d.lightMinutes = m.minutesLight
            d.awakeMinutes = m.minutesAwake
            d.disturbances = m.disturbances
            d.hrv = m.hrv
            d.rhr = m.rhr
            d.respRate = m.respRate
            d.spo2 = m.spo2
            d.skinTemp = m.skinTemp

            let prevDay = past.last { $0.day == DayKey.shift(day, days: -1, calendar: calendar) }
            let shortfalls = pastWithSleep.suffix(3).compactMap { p -> Double? in
                guard let need = p.sleepNeedMinutes, let slept = p.sleepMinutes else { return nil }
                return need - slept
            }
            let need = SleepCoach.need(baseHours: profile.sleepNeedHours, previousStrain: prevDay?.strain,
                                       recentShortfalls: shortfalls, napMinutes: prevDay?.napMinutes ?? 0)
            d.sleepNeedMinutes = need.rounded()
            d.sleepPerformance = SleepCoach.performance(asleepMinutes: m.asleepMinutes, needMinutes: need)
            let prevTimes = pastWithSleep.suffix(4).compactMap { p -> (onset: Double, wake: Double)? in
                guard let s = p.sleepStart, let e = p.sleepEnd else { return nil }
                return (SleepCoach.minutesAfterMidnight(ts: s, calendar: calendar), SleepCoach.minutesAfterMidnight(ts: e, calendar: calendar))
            }
            d.sleepConsistency = SleepCoach.consistency(
                onsetMinutes: SleepCoach.minutesAfterMidnight(ts: m.start, calendar: calendar),
                wakeMinutes: SleepCoach.minutesAfterMidnight(ts: m.end, calendar: calendar),
                previous: prevTimes)
            // Debt is a decaying carry-over (half of last night's debt is kept, plus tonight's shortfall;
            // a surplus pays it back), not a plain 7-day sum, which grows without bound.
            let prevDebt = prevDay?.sleepDebtMinutes ?? 0
            d.sleepDebtMinutes = Stats.clamp(prevDebt * 0.5 + (need - m.asleepMinutes), 0, 12 * 60).rounded()
        }
        d.napMinutes = naps.isEmpty ? nil : naps.reduce(0) { $0 + $1.asleepMinutes }

        // Recovery against personal baselines (only days before this one).
        let baselines = Baselines.from(history: past)
        let rec = Recovery.compute(hrv: d.hrv, rhr: d.rhr, resp: d.respRate, skinTemp: d.skinTemp, spo2: d.spo2,
                                   sleepPerformance: d.sleepPerformance, baselines: baselines)
        d.recovery = main == nil ? nil : rec.score
        d.calibrating = rec.calibrating
        d.contributors = rec.contributors
        d.skinTempDeviation = rec.skinTempDeviation

        // Stress while awake and still, outside workouts and naps, against a two-week calm baseline.
        let excluding = workoutWindows + naps.map { $0.start...$0.end }
        let still = Stress.stillWindows(samples: samples, epochs: cycleEpochs, from: cycleStart, to: d.cycleEnd!,
                                        excluding: excluding, stillThreshold: stillThr)
        let todayCalm = Stress.calmReference(still)
        d.calmHR = todayCalm.hr
        d.calmHRV = todayCalm.hrv
        let calmHRs = past.suffix(14).compactMap { $0.calmHR } + [todayCalm.hr].compactMap { $0 }
        let calmHRVs = past.suffix(14).compactMap { $0.calmHRV } + [todayCalm.hrv].compactMap { $0 }
        if let refHR = Stats.median(calmHRs) {
            let stress = Stress.score(still, calmHR: refHR, calmHRV: Stats.median(calmHRVs))
            if !stress.isEmpty {
                d.stressAvg = Stats.mean(stress.map { $0.score })
                d.stressHighMinutes = Double(stress.filter { $0.score >= 2 }.count * 5)
                var hourly = [[Double]](repeating: [], count: 24)
                for w in stress {
                    let h = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(w.ts)))
                    hourly[h].append(w.score)
                }
                d.stressHourly = hourly.map { Stats.mean($0) }
            }
        }

        // Fitness.
        let rhrForFitness = baselines.rhr?.center ?? d.rhr
        if let r = rhrForFitness {
            d.vo2max = Fitness.vo2max(maxHR: model.maxHR, restingHR: r).map { ($0 * 10).rounded() / 10 }
        }
        return d
    }
}
