import XCTest
import PulsoStore
import PulsoAnalytics
@testable import PulsoIntelligence

/// What each analysis claims has to match what it actually computed.
final class AnalysisHonestyTests: XCTestCase {
    let base = IntelligenceTests()

    func day(_ i: Int) -> String { base.day(i) }

    // MARK: Coherence

    func testCoherenceSaysWhichSignalLastNightLacks() {
        var days = base.normalDays(40)
        days[39].skinTemp = nil
        let series = Deviation.series(days)
        let check = Deviation.check(night: day(39), days: days, series: series)
        XCTAssertNil(check.point)
        XCTAssertEqual(check.missing, ["Temperatura"])
        XCTAssertEqual(check.latest?.day, day(38), "the older night is named, not passed off as last night")
        let m = Deviation.coherenceMetric(series, night: check)
        XCTAssertNil(m.value)
        XCTAssertFalse(m.isLocked)
        XCTAssertTrue(m.summary.contains("falta temperatura"), m.summary)
        XCTAssertTrue(m.summary.contains("Última noche completa"), m.summary)

        let none = Deviation.check(night: day(40), days: days, series: series)
        XCTAssertFalse(none.hasNight)
        XCTAssertTrue(Deviation.coherenceMetric(series, night: none).summary.hasPrefix("Anoche aún no está analizada"))

        let ok = Deviation.check(night: day(38), days: days, series: series)
        XCTAssertEqual(ok.point?.day, day(38))
        XCTAssertEqual(Deviation.coherenceMetric(series, night: ok).value, ok.point!.coherence.rounded())
    }

    func testCoherenceExplainsItselfHonestly() {
        var days = base.normalDays(45)
        let m = Deviation.coherenceMetric(Deviation.series(days))
        XCTAssertFalse(m.formula.contains("P(χ²₄ ≥ D²)"), "the score is an empirical rank now")
        XCTAssertTrue(m.formula.contains("percentil"))
        XCTAssertEqual(m.confidenceNote, "Referencia completa: 28 noches")
        let p = Deviation.series(days).last!
        XCTAssertFalse(p.mixesSources)
        XCTAssertEqual(p.signals.map(\.key), ["hrv", "rhr", "resp", "temp"])
        for c in p.signals {
            XCTAssertTrue(c.band.contains(0), "the usual band surrounds the median")
            XCTAssertGreaterThan(c.usual, 0)
        }
        XCTAssertEqual(p.signals[0].usual, 65, accuracy: 6, "VFC reads in ms, not ln")

        for i in 0..<30 { days[i].source = "whoop" }
        let mixed = Deviation.series(days).last!
        XCTAssertTrue(mixed.mixesSources)
        XCTAssertTrue(Deviation.coherenceMetric(Deviation.series(days)).summary.contains("mezcla"))
    }

    // MARK: Simulator

    func testRareHabitStaysOutOfTheSimulator() {
        var r = IntelligenceTests.LCG(s: 11)
        var days: [DaySummary] = []
        var journal: [JournalEntry] = []
        for i in 0..<80 {
            var d = DaySummary(day: day(i))
            let sleep = 6 + 2.5 * r.next()
            let drank = i > 0 && r.next() < 0.2
            if drank { journal.append(JournalEntry(day: day(i - 1), key: "alcohol", value: 1)) }
            d.sleepMinutes = sleep * 60
            d.strain = 8 + 8 * r.next()
            d.recovery = Num.clamp(30 + 6 * sleep - 18 * (drank ? 1 : 0) + 4 * r.normal(), 1, 99)
            d.hrv = 60; d.rhr = 55; d.respRate = 14.5; d.skinTemp = 34.4
            days.append(d)
        }
        // Two late dinners, both before great days: one random pair would otherwise swing the forecast.
        journal.append(JournalEntry(day: day(30), key: "late_meal", value: 1))
        journal.append(JournalEntry(day: day(50), key: "late_meal", value: 1))
        days[31].recovery = 99; days[51].recovery = 99
        let dev = Deviation.series(days)
        let o = RecoveryModel.outlook(days: days, deviation: dev, journal: journal, today: days.last!.day)!
        XCTAssertTrue(o.model.usesHabit(0))
        XCTAssertFalse(o.model.usesHabit(2))
        let plain = RecoveryModel.scenario(o, sleepHours: 7.5, alcohol: false, caffeine: false, lateMeal: false)
        let meal = RecoveryModel.scenario(o, sleepHours: 7.5, alcohol: false, caffeine: false, lateMeal: true)
        let drunk = RecoveryModel.scenario(o, sleepHours: 7.5, alcohol: true, caffeine: false, lateMeal: false)
        XCTAssertEqual(meal.value, plain.value, accuracy: 1e-9)
        XCTAssertLessThan(drunk.value, plain.value - 8)
        XCTAssertFalse(o.model.contributions(o.todayInputs).contains { $0.name.lowercased().contains("cena") })
    }

    // MARK: Load ceiling

    func event(_ i: Int, load: Double, nights: Double?, censored: Bool = false) -> LoadResponse.Event {
        LoadResponse.Event(day: day(i), sport: "Carrera", strain: 15, load3d: load, intensity: "alta", recoveryNights: nights, cost: 1,
                           peak: 2, hrvChangePct: nil, rhrChange: nil, respChange: nil, chained: false, censored: censored)
    }

    func testCeilingKeepsDaysThatNeverRecover() {
        let events = (0..<24).map { i -> LoadResponse.Event in
            let load = 20 + Double(i) * 2
            return load >= 50 ? event(i, load: load, nights: nil, censored: true) : event(i, load: load, nights: 1 + 0.02 * Double(i))
        }
        let c = LoadResponse.ceiling(events)
        XCTAssertEqual(c.points.count, 24, "overloads count as ≥ 5 nights instead of disappearing")
        XCTAssertEqual(c.overloads, 9)
        let knee = try! XCTUnwrap(c.knee)
        XCTAssertTrue((36...50).contains(knee), "knee \(knee) where recovery starts to run away")
        let m = LoadResponse.ceilingMetric(events)
        XCTAssertTrue(m.isAvailable)
        XCTAssertTrue(m.summary.contains("9 veces no te recuperaste"), m.summary)

        // Before the fix only the 15 recovered days were left: not even enough to try.
        XCTAssertEqual(events.filter { $0.recoveryNights != nil }.count, 15)

        let flat = (0..<24).map { event($0, load: 20 + Double($0) * 2, nights: 1 + 0.03 * Double($0)) }
        let none = LoadResponse.ceilingMetric(flat)
        XCTAssertNil(none.value)
        XCTAssertFalse(none.isLocked, "«no se ve límite» is a result")
        XCTAssertTrue(none.summary.hasPrefix("No se ve límite"))
        XCTAssertTrue(LoadResponse.ceilingMetric(Array(flat.prefix(5))).isLocked)
    }

    func testOverloadIsCensoredNotDropped() {
        var days = base.normalDays(40, seed: 3)
        days[30].strain = 19
        for k in 31...35 { days[k].hrv = 40; days[k].rhr = 62; days[k].respRate = 16 }
        let dev = Deviation.series(days)
        let e = LoadResponse.events(days: days, deviation: dev, workouts: []).first { $0.day == day(30) }!
        XCTAssertNil(e.recoveryNights)
        XCTAssertTrue(e.censored)
        XCTAssertEqual(e.nightsAtLeast, 5)
        // A night that was simply not measured is unknown, not an overload.
        days[33].hrv = nil
        let gap = LoadResponse.events(days: days, deviation: Deviation.series(days), workouts: []).first { $0.day == day(30) }!
        XCTAssertFalse(gap.censored)
        XCTAssertNil(gap.nightsAtLeast)
    }

    // MARK: Habits

    func testHabitsCompareOnlyDaysTheQuestionWasAsked() {
        let days = base.normalDays(60, seed: 9)
        var journal: [JournalEntry] = []
        // Days 0–29 imported: alcohol and screens asked explicitly, plus a question Pulso doesn't have.
        for i in 0..<30 {
            journal.append(JournalEntry(day: day(i), key: "alcohol", value: i % 3 == 0 ? 1 : 0))
            journal.append(JournalEntry(day: day(i), key: "whoop:¿Desayunaste?", value: 1))
        }
        // Days 30–58 logged in Pulso (only yes is stored).
        for i in 30..<59 {
            if i % 3 == 0 { journal.append(JournalEntry(day: day(i), key: "alcohol", value: 1)) }
            if i % 2 == 0 { journal.append(JournalEntry(day: day(i), key: "late_caffeine", value: 1)) }
            if i % 2 == 1 { journal.append(JournalEntry(day: day(i), key: "reading", value: 1)) }
        }
        let items = HabitImpact.analyze(journal: journal, days: days, deviation: Deviation.series(days))
        let caffeine = items.first { $0.key == "late_caffeine" }!
        XCTAssertEqual(caffeine.withCount, 15)
        XCTAssertEqual(caffeine.withoutCount, 14, "imported days never asked about caffeine: not a «no»")
        let alcohol = items.first { $0.key == "alcohol" }!
        XCTAssertEqual(alcohol.n, 59, "asked on both kinds of day")
        XCTAssertEqual(alcohol.withCount, 20)
        XCTAssertNil(items.first { $0.key == "sauna" }, "never asked anywhere it was logged, never ticked")
    }

    func testMultipleComparisonsGuard() {
        XCTAssertEqual(Num.tTwoSidedP(2.228, df: 10), 0.05, accuracy: 0.001)
        XCTAssertEqual(Num.tTwoSidedP(1.812, df: 10), 0.10, accuracy: 0.002)
        XCTAssertEqual(Num.tTwoSidedP(0, df: 10), 1, accuracy: 1e-9)
        let q = Num.benjaminiHochberg([0.01, 0.04, 0.03, 0.2])
        XCTAssertEqual(q[0], 0.04, accuracy: 1e-9)
        XCTAssertEqual(q[1], 0.16 / 3, accuracy: 1e-9)
        XCTAssertEqual(q[2], 0.16 / 3, accuracy: 1e-9)
        XCTAssertEqual(q[3], 0.2, accuracy: 1e-9)

        // 30 pure-noise questions: some 90 % intervals miss zero by chance; the corrected flag shouldn't.
        let days = base.normalDays(120, seed: 21)
        var r = IntelligenceTests.LCG(s: 5)
        var journal: [JournalEntry] = []
        for k in 0..<30 {
            for i in 0..<119 { journal.append(JournalEntry(day: day(i), key: "whoop:q\(k)", value: r.next() < 0.4 ? 1 : 0)) }
        }
        let items = HabitImpact.analyze(journal: journal, days: days, deviation: [])
        XCTAssertEqual(items.count, 30)
        let raw = items.filter(\.intervalExcludesZero).count
        let clear = items.filter(\.isClear).count
        XCTAssertLessThanOrEqual(clear, raw)
        XCTAssertLessThanOrEqual(clear, 1, "\(raw) uncorrected vs \(clear) after BH")
        XCTAssertTrue(items.allSatisfy { $0.qValue >= $0.pValue })
    }

    /// WHOOP cycles start at sleep onset, so a cycle's day is the day after that night; its journal answers
    /// describe that day. The night after it belongs to the next cycle, whose day is the journal day + 1.
    func testImportedJournalPairsWithTheFollowingRecovery() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let cycles = """
        Cycle start time,Cycle end time,Cycle timezone,Recovery score %,Heart rate variability (ms),Sleep onset,Wake onset
        2026-10-24 01:30:04,2026-10-25 00:50:00,UTC+02:00,70,80,2026-10-24 01:30:04,2026-10-24 09:00:00
        2026-10-25 00:50:00,2026-10-25 23:40:00,UTC+01:00,35,50,2026-10-25 00:50:00,2026-10-25 08:30:00
        """
        let journal = """
        Cycle start time,Cycle end time,Cycle timezone,Question text,Answered yes/no,Notes
        2026-10-24 01:30:04,2026-10-25 00:50:00,UTC+02:00,Did you have any alcohol?,true,
        """
        let b = WhoopExport.read([.init(name: "physiological_cycles.csv", text: cycles), .init(name: "journal_entries.csv", text: journal)],
                                 calendar: cal)
        XCTAssertEqual(b.days.map(\.day), ["2026-10-24", "2026-10-25"])
        let entry = try! XCTUnwrap(b.journal.first)
        XCTAssertEqual(entry.day, "2026-10-24", "keyed to the cycle it was logged in")
        XCTAssertEqual(LoadResponse.shift(entry.day, 1), "2026-10-25", "next day = the recovery after the night that followed")
        XCTAssertEqual(b.days.first { $0.day == LoadResponse.shift(entry.day, 1) }?.recovery, 35)
    }

    // MARK: Explorer

    func testFisherInterval() {
        let ci = Association.fisherInterval(r: 0.5, n: 30)!
        XCTAssertEqual(ci.lowerBound, 0.2286, accuracy: 0.002)
        XCTAssertEqual(ci.upperBound, 0.6995, accuracy: 0.002)
        XCTAssertTrue(Association.fisherInterval(r: 0.1, n: 20)!.contains(0))
        XCTAssertNil(Association.fisherInterval(r: 0.9, n: 3))
    }

    // MARK: Cardiac cost

    func testCardiacCostComparesCompleteDaysOnly() {
        var days = (0..<12).map { i -> DaySummary in var d = DaySummary(day: day(i)); d.extraBeats = 1000 + Double(i % 3) * 10; return d }
        days[11].extraBeats = 300
        let m = Rhythms.cardiacCostMetric(days, today: day(11))
        XCTAssertEqual(m.value, days[10].extraBeats)
        XCTAssertEqual(m.sampleSize, 11)
        XCTAssertTrue(m.summary.hasPrefix("Ayer"), m.summary)
        XCTAssertTrue(m.summary.contains("en lo que va de día: 300"), m.summary)
        XCTAssertFalse(m.summary.contains("−70") || m.summary.contains("-70"), "a half day is never compared")
        XCTAssertTrue(Rhythms.cardiacCostMetric(Array(days.prefix(5)), today: day(4)).isLocked)
    }

    // MARK: Guide

    func testEveryMetricHasItsGuide() {
        let days = base.normalDays(40)
        let report = Intelligence.report(days: days, sleeps: [], workouts: [], journal: [], now: Date(), currentDay: day(39))
        for m in report.sections.flatMap(\.metrics) {
            XCTAssertNotNil(MetricGuide.of(m.id), "missing guide for \(m.id)")
        }
        XCTAssertNotNil(MetricGuide.of("relation"))
        XCTAssertEqual(report.lastNight?.point?.day, day(39))
    }
}
