import XCTest
import WhoopProtocol
@testable import PulsoStore

final class StoreExtrasTests: XCTestCase {
    func db() throws -> PulsoDatabase {
        try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-extra-\(UUID().uuidString).sqlite")
    }

    func testProfileFromOlderVersionKeepsValues() throws {
        // A profile saved before `cycleTracking` existed must still decode with the user's values.
        let old = #"{"name":"Gus","birthYear":1994,"sex":"male","weightKg":80,"heightCm":182,"sleepNeedHours":7.5,"healthKitEnabled":true,"rawRetentionDays":365}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        XCTAssertEqual(p.name, "Gus")
        XCTAssertEqual(p.birthYear, 1994)
        XCTAssertEqual(p.weightKg, 80)
        XCTAssertEqual(p.rawRetentionDays, 365)
        XCTAssertFalse(p.cycleTracking)
        // Round trip with the new field.
        var q = p
        q.cycleTracking = true
        let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(q))
        XCTAssertEqual(back, q)
    }

    func testOldWorkoutJSONStillDecodes() throws {
        let old = #"{"start":10,"end":70,"sport":"Carrera","source":"live","strain":8.2,"avgHR":150,"maxHR":171,"kcal":420,"zoneMinutes":[0,1,2,3,0],"notes":""}"#
        let w = try JSONDecoder().decode(Workout.self, from: Data(old.utf8))
        XCTAssertEqual(w.sport, "Carrera")
        XCTAssertNil(w.externalIDs)
        XCTAssertFalse(w.source.isExternal)
    }

    func testWorkoutExternalIDsAndLookup() throws {
        let d = try db()
        var w = Workout(start: 1000, end: 4600, sport: "Ciclismo", source: .strava, kcal: 600, distanceMeters: 30_000)
        w.setExternalID("123456789", for: "strava")
        w.setExternalID("ABC-DEF", for: "health")
        let id = try d.save(w)
        let found = try d.workout(externalID: "123456789", service: "strava")
        XCTAssertEqual(found?.id, id)
        XCTAssertEqual(found?.distanceMeters, 30_000)
        XCTAssertEqual(found?.externalID("health"), "ABC-DEF")
        XCTAssertNil(try d.workout(externalID: "12345678", service: "strava"), "prefix must not match")
        XCTAssertNil(try d.workout(externalID: "123456789", service: "health"))
        // Imported workouts survive the automatic-bout cleanup.
        try d.deleteAutoWorkouts(from: 0, to: 10_000)
        XCTAssertEqual(try d.workouts(from: 0, to: 10_000).count, 1)
        // Clearing the last id leaves nil, not an empty dictionary.
        var x = Workout(start: 1, end: 2, sport: "x", source: .manual)
        x.setExternalID("1", for: "strava")
        x.setExternalID(nil, for: "strava")
        XCTAssertNil(x.externalIDs)
    }

    func testECGRoundTripAndListWithoutSamples() throws {
        let d = try db()
        let samples: [Float] = (0..<5120).map { Float(sin(Double($0) / 20)) * 1.2 }
        var rec = ECGRecording(start: 1_790_000_000, sampleRate: 512, samples: samples, source: .simulated,
                               rhythm: "sinus", avgHR: 62.5, notes: "prueba", externalID: "hk-1")
        rec.id = try d.save(rec)
        let all = try d.ecgRecordings()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].samples, samples, "float samples are stored bit-exact")
        XCTAssertEqual(all[0].rhythm, "sinus")
        XCTAssertEqual(all[0].avgHR, 62.5)
        XCTAssertEqual(all[0].durationSeconds, 10, accuracy: 0.001)
        XCTAssertTrue(try d.hasECG(externalID: "hk-1"))
        XCTAssertFalse(try d.hasECG(externalID: "hk-2"))
        let light = try d.ecgRecordings(withSamples: false)
        XCTAssertTrue(light[0].samples.isEmpty)
        XCTAssertEqual(light[0].notes, "prueba")
        rec.notes = "editada"
        try d.save(rec)
        XCTAssertEqual(try d.ecgRecording(id: rec.id!)?.notes, "editada")
        try d.deleteECG(id: rec.id!)
        XCTAssertTrue(try d.ecgRecordings().isEmpty)
    }

    func testBackupIsAValidCopy() throws {
        let d = try db()
        var day = DaySummary(day: "2026-10-01")
        day.recovery = 81
        try d.save(day)
        try d.insert([HistorySample(unix: 1_790_000_000, heartRate: 58)])
        let path = NSTemporaryDirectory() + "pulso-backup-\(UUID().uuidString).sqlite"
        try d.backup(to: path)
        try d.backup(to: path) // overwriting works
        XCTAssertTrue(PulsoDatabase.isValidBackup(path: path))
        let copy = try PulsoDatabase(path: path)
        XCTAssertEqual(try copy.day("2026-10-01")?.recovery, 81)
        XCTAssertEqual(try copy.sampleCount(), 1)

        let junk = NSTemporaryDirectory() + "pulso-junk-\(UUID().uuidString).txt"
        try "not a database".write(toFile: junk, atomically: true, encoding: .utf8)
        XCTAssertFalse(PulsoDatabase.isValidBackup(path: junk))
        XCTAssertFalse(PulsoDatabase.isValidBackup(path: NSTemporaryDirectory() + "missing-\(UUID().uuidString)"))
    }
}
