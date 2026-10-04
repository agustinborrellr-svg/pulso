import XCTest
import WhoopProtocol
@testable import PulsoStore

final class StoreTests: XCTestCase {
    func db() throws -> PulsoDatabase {
        try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-store-\(UUID().uuidString).sqlite")
    }

    func testSamplesRoundTripAndDedup() throws {
        let d = try db()
        let s = HistorySample(unix: 1_790_000_000, heartRate: 61, rr: [980, 990], gravity: SIMD3(0, 0, 1),
                              dynamicAccelG: 0.01, skinTempC: 34.2, spo2: 97, steps: 12, activityClass: 0, sleepState: 2,
                              signalFlags: 0, signalQuality: 255)
        try d.insert([s, s])
        let out = try d.samples(from: 1_789_999_999, to: 1_790_000_001)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].hr, 61)
        XCTAssertEqual(out[0].rr, [980, 990])
        XCTAssertEqual(out[0].spo2, 97)
        XCTAssertEqual(out[0].temp ?? 0, 34.2, accuracy: 0.001)
        XCTAssertTrue(out[0].worn)
    }

    func testDaysSleepsWorkoutsJournalKV() throws {
        let d = try db()
        var day = DaySummary(day: "2026-09-10")
        day.recovery = 77
        day.contributors = [Contributor(key: "hrv", label: "VFC", value: 70, baseline: 60, unit: "ms", impact: 0.3)]
        try d.save(day)
        XCTAssertEqual(try d.day("2026-09-10")?.recovery, 77)
        XCTAssertEqual(try d.days(from: "2026-09-01", to: "2026-09-30").count, 1)

        var sl = SleepSession(start: 100, end: 30_000, stages: [.awake, .light, .deep, .rem])
        let id = try d.save(sl)
        sl.id = id
        sl.manual = true
        try d.save(sl)
        XCTAssertEqual(try d.sleep(id: id)?.manual, true)
        try d.deleteAutoSleeps(from: 0, to: 50_000)
        XCTAssertEqual(try d.sleeps(from: 0, to: 50_000).count, 1, "manual sleeps survive auto cleanup")

        let wid = try d.save(Workout(start: 1000, end: 4000, sport: "Carrera", source: .manual))
        XCTAssertEqual(try d.workouts(from: 0, to: 5000).first?.id, wid)
        try d.deleteAutoWorkouts(from: 0, to: 5000)
        XCTAssertEqual(try d.workouts(from: 0, to: 5000).count, 1)

        try d.setJournal(day: "2026-09-10", key: "alcohol", value: 1)
        XCTAssertEqual(try d.journal(day: "2026-09-10")["alcohol"], 1)
        try d.setJournal(day: "2026-09-10", key: "alcohol", value: nil)
        XCTAssertTrue(try d.journal(day: "2026-09-10").isEmpty)

        var p = d.profile
        p.name = "Gus"
        d.profile = p
        XCTAssertEqual(d.profile.name, "Gus")

        try d.eraseAll()
        XCTAssertNil(try d.day("2026-09-10"))
    }
}
