import XCTest
import PulsoStore
@testable import PulsoAnalytics

/// End to end: per-second strap data with a known truth (the demo's day plans) → the full engine →
/// does each metric land where the physiology says it should?
final class MetricsTruthTests: XCTestCase {
    struct Truth {
        var plan: DemoData.DayPlan
        var index: Int
        var sick: Bool
    }

    func testMetricsMatchTheKnownPhysiology() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let db = try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-truth-\(UUID().uuidString).sqlite")
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20))!
        let n = 21
        let days = try DemoData.populate(db: db, days: n, now: now, calendar: cal, keepRawDays: nil)
        var rng = DemoData.RNG(state: 2026)
        let plans = DemoData.plans(days: n, rng: &rng)
        let today = cal.startOfDay(for: now)

        // The Pulso day of plan i is the date of waking up from the night that starts on day i - n.
        var truth: [String: Truth] = [:]
        for (i, p) in plans.enumerated() {
            let start = cal.date(byAdding: .day, value: i - n, to: today)!
            let wake = start.addingTimeInterval(p.bedMinute * 60 + p.sleepHours * 3600)
            truth[DayKey.string(wake, calendar: cal)] = Truth(plan: p, index: i, sick: i >= n - 2)
        }
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let workouts = try db.workouts(from: 0, to: Int(now.timeIntervalSince1970) + 86400)

        var sleepErr: [Double] = [], rhrErr: [Double] = []
        for (day, t) in truth.sorted(by: { $0.key < $1.key }) {
            guard let d = byDay[day] else { continue }
            let p = t.plan
            let truthBed = p.sleepHours * 60
            print(String(format: "TRUTH %@ cama=%.0f/%.0f dormido=%.0f FCR=%.1f/%.1f VFC=%.0f rec=%@ esf=%.1f %@%@",
                         day, d.inBedMinutes ?? -1, truthBed, d.sleepMinutes ?? -1, d.rhr ?? -1, p.restingHR, d.hrv ?? -1,
                         d.recovery.map { String(Int($0)) } ?? "-", d.strain ?? -1, p.alcohol ? "alcohol " : "", t.sick ? "ENFERMO" : ""))
            if let inBed = d.inBedMinutes, t.index < n - 1 {
                sleepErr.append(abs(inBed - truthBed))
                // Time in bed within 25 min of the truth (the demo opens each night with 12 awake minutes).
                XCTAssertLessThan(abs(inBed - truthBed), 25, "en cama \(day)")
                if let asleep = d.sleepMinutes {
                    XCTAssertLessThanOrEqual(asleep, inBed + 0.5, "dormido ≤ en cama \(day)")
                    XCTAssertGreaterThan(asleep, inBed * 0.8, "dormido \(day)")
                }
            }
            if let rhr = d.rhr {
                // Lowest sustained sleeping HR: deep sleep sits at base − 3, light at base + 1.
                rhrErr.append(abs(rhr - (p.restingHR - 2)))
                XCTAssertLessThan(abs(rhr - (p.restingHR - 2)), 3.5, "FC en reposo \(day)")
            }
            if let deep = d.deepMinutes, let rem = d.remMinutes, let light = d.lightMinutes, let asleep = d.sleepMinutes {
                XCTAssertEqual(deep + rem + light, asleep, accuracy: 3, "fases suman lo dormido \(day)")
            }
        }
        print(String(format: "TRUTH error medio: cama %.1f min, FC reposo %.1f lpm", mean(sleepErr), mean(rhrErr)))

        // Workouts: each planned session is found, with its length and heart rate.
        for (i, p) in plans.enumerated() {
            guard let w = p.workout else { continue }
            let dayStart = cal.date(byAdding: .day, value: i - n, to: today)!
            let wake = dayStart.addingTimeInterval(p.bedMinute * 60 + p.sleepHours * 3600)
            let base = cal.startOfDay(for: wake)
            let ws = Int(base.timeIntervalSince1970 + w.startHour * 3600)
            // The demo only writes the part of a session that falls after waking up.
            let realStart = max(ws, Int(wake.timeIntervalSince1970))
            let realMinutes = (ws + w.minutes * 60 - realStart) / 60
            guard realMinutes >= 20, ws + w.minutes * 60 < Int(now.timeIntervalSince1970) else { continue }
            let found = workouts.first { abs($0.start - realStart) < 15 * 60 }
            XCTAssertNotNil(found, "entreno del plan \(i) a las \(w.startHour) h")
            if let f = found {
                XCTAssertEqual(f.durationMinutes, Double(realMinutes), accuracy: 8, "duración entreno \(i)")
                XCTAssertEqual(f.avgHR, w.hr, accuracy: 6, "FC media entreno \(i)")
            }
        }

        // Directions the physiology dictates.
        let scored = truth.compactMap { k, t -> (Truth, DaySummary)? in byDay[k].map { (t, $0) } }.filter { $0.1.recovery != nil }
        let alcohol = scored.filter { $0.0.plan.alcohol }.compactMap { $0.1.recovery }
        let clean = scored.filter { !$0.0.plan.alcohol && !$0.0.sick }.compactMap { $0.1.recovery }
        print("TRUTH recuperación con alcohol \(alcohol.map { Int($0) }) sin \(clean.map { Int($0) })")
        if !alcohol.isEmpty { XCTAssertLessThan(mean(alcohol), mean(clean) - 10, "el alcohol baja la recuperación") }
        let sick = scored.filter { $0.0.sick }.compactMap { $0.1.recovery }
        if !sick.isEmpty { XCTAssertLessThan(mean(sick), mean(clean) - 15, "los días de enfermedad bajan la recuperación") }
        let hrvClean = scored.filter { !$0.0.plan.alcohol && !$0.0.sick }.compactMap { $0.1.hrv }
        let hrvAlcohol = scored.filter { $0.0.plan.alcohol }.compactMap { $0.1.hrv }
        if !hrvAlcohol.isEmpty { XCTAssertLessThan(mean(hrvAlcohol), mean(hrvClean), "VFC más baja tras alcohol") }

        // Strain follows the training: hard > easy > rest.
        func strain(_ f: (DemoData.DayPlan) -> Bool) -> Double {
            mean(truth.filter { f($0.value.plan) && !$0.value.sick }.compactMap { byDay[$0.key]?.strain })
        }
        let hard = strain { ($0.workout?.hr ?? 0) > 155 }, easy = strain { ($0.workout?.hr ?? 200) < 150 }, rest = strain { $0.workout == nil }
        print(String(format: "TRUTH esfuerzo duro %.1f fácil %.1f descanso %.1f", hard, easy, rest))
        XCTAssertGreaterThan(hard, easy)
        XCTAssertGreaterThan(easy, rest)
        for d in days {
            if let s = d.strain { XCTAssert((0...21).contains(s), "esfuerzo 0–21 \(d.day)") }
            if let r = d.recovery { XCTAssert((0...100).contains(r), "recuperación 0–100 \(d.day)") }
            if let p = d.sleepPerformance { XCTAssert((0...1).contains(p), "rendimiento 0–1 \(d.day)") }
        }

        // Fever-like nights show up as a skin-temperature deviation.
        let sickTemp = scored.filter { $0.0.sick }.compactMap { $0.1.skinTempDeviation }
        print("TRUTH desviación de temperatura en los días de enfermedad \(sickTemp)")
        if !sickTemp.isEmpty { XCTAssertGreaterThan(sickTemp.max() ?? 0, 0.3) }
    }

    private func mean(_ x: [Double]) -> Double { x.isEmpty ? .nan : x.reduce(0, +) / Double(x.count) }
}
