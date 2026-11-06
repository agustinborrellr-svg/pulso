import XCTest
import WhoopProtocol
@testable import PulsoStore

/// Month archives of the per-second data, weekly copies with only the current month, and the restore merge
/// that brings every second back.
final class BackupArchiveTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func ts(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Int {
        Int(utc.date(from: DateComponents(year: y, month: m, day: d, hour: h))!.timeIntervalSince1970)
    }

    private func tempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "pulso-copies-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sample(_ t: Int, hr: UInt8? = 60, spo2: UInt8? = nil) -> HistorySample {
        HistorySample(unix: UInt32(t), heartRate: hr, spo2: spo2)
    }

    /// Sep, Oct and Nov 2026 seconds, a day summary and a live reading in October.
    private func populated() throws -> PulsoDatabase {
        let d = try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-arch-\(UUID().uuidString).sqlite")
        try d.insert([sample(ts(2026, 9, 10)), sample(ts(2026, 9, 30, 23))])
        try d.insert((0..<5).map { sample(ts(2026, 10, 1, 0) + $0) } + [sample(ts(2026, 10, 31, 23))])
        try d.insert([sample(ts(2026, 11, 1, 0)), sample(ts(2026, 11, 5))])
        try d.insertLive(ts: ts(2026, 10, 15), hr: 70, rr: [850])
        var day = DaySummary(day: "2026-10-15")
        day.recovery = 77
        try d.save(day)
        return d
    }

    func testMonthArchiveHoldsOnlyThatMonthAndPassesIntegrity() throws {
        let d = try populated()
        let dir = try tempDir()
        let now = Date(timeIntervalSince1970: TimeInterval(ts(2026, 11, 15)))
        // One month per call, oldest first; the current month is never archived.
        XCTAssertEqual(try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: false), "2026-09")
        XCTAssertEqual(try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: false), "2026-10")
        XCTAssertNil(try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: true))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).sorted()
        XCTAssertEqual(files, ["Pulso-segundos-2026-09.sqlite", "Pulso-segundos-2026-10.sqlite"], "nothing temporary left")

        let path = dir + "/Pulso-segundos-2026-10.sqlite"
        XCTAssertTrue(PulsoDatabase.isIntactCopy(path: path))
        let info = try XCTUnwrap(PulsoDatabase.monthArchiveInfo(path: path))
        XCTAssertEqual(info.month, "2026-10")
        XCTAssertEqual(info.counts.rows, 6)
        XCTAssertEqual(info.counts.live, 1)
        let arch = try PulsoDatabase(path: path)
        let secs = try arch.samples(from: 0, to: Int.max).map(\.ts)
        XCTAssertEqual(secs.count, 6)
        XCTAssertTrue(secs.allSatisfy { $0 >= ts(2026, 10, 1, 0) && $0 < ts(2026, 11, 1, 0) })
        XCTAssertEqual(try arch.liveHR(from: 0, to: Int.max).count, 1)
        XCTAssertTrue(try arch.allDays().isEmpty, "only per-second data")
        XCTAssertEqual(try d.sampleCount(), 10, "the live database is untouched")
        XCTAssertNil(PulsoDatabase.monthArchiveInfo(path: d.sql.path), "the live database is not an archive")
    }

    func testArchiveIsRewrittenWhenItsMonthGetsMoreSecondsAndNeverShrinks() throws {
        let d = try populated()
        let dir = try tempDir()
        let now = Date(timeIntervalSince1970: TimeInterval(ts(2026, 11, 15)))
        while try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: false) != nil {}
        let path = dir + "/Pulso-segundos-2026-10.sqlite"

        // The strap offloads an old October second late, and fills a value of one already stored.
        try d.insert([sample(ts(2026, 10, 20)), sample(ts(2026, 10, 1, 0), hr: nil, spo2: 97)])
        XCTAssertNil(try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: false), "refresh only when asked")
        XCTAssertEqual(try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: true), "2026-10")
        XCTAssertNil(try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: true), "up to date now")
        var arch = try PulsoDatabase(path: path)
        XCTAssertEqual(try arch.sampleCount(), 7)
        XCTAssertEqual(try arch.samples(from: ts(2026, 10, 1, 0), to: ts(2026, 10, 1, 0) + 1).first?.spo2, 97)

        // Seconds pruned from the live database (retention limit) never shrink the archive…
        try d.dropSamples(olderThan: ts(2026, 11, 1, 0))
        XCTAssertNil(try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: true))
        // …and a forced rewrite merges what the archive had with what the live database has now.
        try d.insert([sample(ts(2026, 10, 25))])
        try d.writeMonthArchive(month: "2026-10", calendar: utc, to: path)
        arch = try PulsoDatabase(path: path)
        XCTAssertEqual(try arch.sampleCount(), 8)
        XCTAssertEqual(try arch.liveHR(from: 0, to: Int.max).count, 1)
    }

    func testDamagedArchiveIsSetAsideNotDeleted() throws {
        let d = try populated()
        let dir = try tempDir()
        let path = dir + "/Pulso-segundos-2026-10.sqlite"
        try "not a database".write(toFile: path, atomically: true, encoding: .utf8)
        try d.writeMonthArchive(month: "2026-10", calendar: utc, to: path)
        XCTAssertEqual(try PulsoDatabase(path: path).sampleCount(), 6)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir)
        let aside = try XCTUnwrap(names.first { $0.contains("-revisar-") })
        XCTAssertNil(BackupPolicy.parse(aside), "the rotation never touches it")
    }

    func testWeeklyCopyHoldsCurrentMonthSecondsAndEverythingElse() throws {
        let d = try populated()
        try d.set("valor", for: "ajuste")
        let now = Date(timeIntervalSince1970: TimeInterval(ts(2026, 11, 15)))
        let path = NSTemporaryDirectory() + "pulso-weekly-\(UUID().uuidString).sqlite"
        try d.backupRecent(to: path, since: BackupPolicy.monthStart(now, calendar: utc))
        XCTAssertTrue(PulsoDatabase.isValidBackup(path: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path + "-wal"), "a single self-contained file")
        let copy = try PulsoDatabase(path: path)
        XCTAssertEqual(try copy.samples(from: 0, to: Int.max).map(\.ts), [ts(2026, 11, 1, 0), ts(2026, 11, 5)])
        XCTAssertEqual(try copy.day("2026-10-15")?.recovery, 77)
        XCTAssertEqual(copy.get(String.self, for: "ajuste"), "valor")
        XCTAssertEqual(try copy.liveHR(from: 0, to: Int.max).count, 0, "October's live reading is in its archive")
        XCTAssertEqual(Int(try copy.sql.scalarInt("PRAGMA user_version;") ?? -1), PulsoDatabase.schemaVersion)
    }

    func testRestoreMergeBringsBackSecondsFromArchivesAndTheReplacedDatabase() throws {
        let live = try populated()
        let dir = try tempDir()
        let now = Date(timeIntervalSince1970: TimeInterval(ts(2026, 11, 15)))
        while try live.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: false) != nil {}
        let copyPath = dir + "/" + BackupPolicy.fileName(.daily, at: now)
        try live.backupLight(to: copyPath)
        // After the copy: a new second in the live database, and seconds pruned from it (only in an archive).
        try live.insert([sample(ts(2026, 11, 14), hr: 61, spo2: 98)])
        try live.dropSamples(olderThan: ts(2026, 10, 1, 0))

        let restored = try PulsoDatabase(path: copyPath)
        // The copy has its own value for one second: it wins, its empty fields are filled.
        try restored.insert([sample(ts(2026, 11, 14), hr: 75)])
        XCTAssertNotNil(try restored.mergeSeconds(from: live.sql.path))
        for name in try FileManager.default.contentsOfDirectory(atPath: dir) where BackupPolicy.parse(name)?.kind == .archive {
            _ = try restored.mergeSeconds(from: dir + "/" + name)
        }
        XCTAssertEqual(try restored.sampleCount(), 11, "Sep from its archive, Oct, Nov and the new second")
        let s = try XCTUnwrap(restored.samples(from: ts(2026, 11, 14), to: ts(2026, 11, 14) + 1).first)
        XCTAssertEqual(s.hr, 75, "the restored copy's value is kept")
        XCTAssertEqual(s.spo2, 98, "an empty field is filled")
        XCTAssertEqual(try restored.liveHR(from: 0, to: Int.max).count, 1)
        XCTAssertEqual(try restored.day("2026-10-15")?.recovery, 77)
        XCTAssertNil(try restored.mergeSeconds(from: live.sql.path), "merging again changes nothing")
    }

    func testPolicyParsesNewAndOldNames() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let weekly = BackupPolicy.parse(BackupPolicy.fileName(.weekly, at: date))
        XCTAssertEqual(weekly?.kind, .weekly)
        XCTAssertEqual(weekly?.content, .month)
        XCTAssertTrue(BackupPolicy.fileName(.weekly, at: date).hasPrefix("Pulso-semanal-2026"))
        let legacyWeekly = BackupPolicy.parse("Pulso-semanal-completa-2026-10-27_081500.sqlite")
        XCTAssertEqual(legacyWeekly?.kind, .weekly)
        XCTAssertEqual(legacyWeekly?.content, .full)
        XCTAssertEqual(BackupPolicy.parse(BackupPolicy.fileName(.daily, at: date))?.content, .light)
        for content in BackupPolicy.Content.allCases {
            let name = BackupPolicy.fileName(.safety, reason: "importar", content: content, at: date)
            XCTAssertEqual(BackupPolicy.parse(name)?.kind, .safety)
            XCTAssertEqual(BackupPolicy.parse(name)?.content, content, name)
            XCTAssertEqual(BackupPolicy.parse(name)?.date, date)
        }
        XCTAssertEqual(BackupPolicy.parse("Pulso-antes-de-importar-2026-10-27_081500.sqlite")?.content, .full, "older safety copies were full")
        let archive = BackupPolicy.parse("Pulso-segundos-2026-10.sqlite")
        XCTAssertEqual(archive?.kind, .archive)
        XCTAssertEqual(archive?.month, "2026-10")
        XCTAssertNil(BackupPolicy.parse("Pulso-segundos-2026-13.sqlite"))
        XCTAssertNil(BackupPolicy.parse("Pulso-segundos-2026-10-revisar-1790000000.sqlite"))

        XCTAssertFalse(BackupPolicy.excludedFromDeviceBackup(BackupPolicy.parse(BackupPolicy.fileName(.daily, at: date))!))
        XCTAssertFalse(BackupPolicy.excludedFromDeviceBackup(BackupPolicy.parse(BackupPolicy.fileName(.safety, reason: "importar", content: .light, at: date))!))
        XCTAssertTrue(BackupPolicy.excludedFromDeviceBackup(archive!))
        XCTAssertTrue(BackupPolicy.excludedFromDeviceBackup(weekly!))
        XCTAssertTrue(BackupPolicy.excludedFromDeviceBackup(legacyWeekly!))
        XCTAssertTrue(BackupPolicy.excludedFromDeviceBackup(BackupPolicy.parse(BackupPolicy.fileName(.safety, reason: "borrar", at: date))!))
    }

    func testRotationKeepsFullSafetyCopiesByCountAndNeverDeletesArchives() {
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        func at(_ days: Double) -> Date { base.addingTimeInterval(-days * 86400) }
        let archives = ["Pulso-segundos-2024-01.sqlite", "Pulso-segundos-2026-09.sqlite", "Pulso-segundos-2026-10.sqlite"]
        let weekly = [BackupPolicy.fileName(.weekly, at: at(1)),
                      "Pulso-semanal-completa-" + String(BackupPolicy.fileName(.daily, at: at(8)).suffix(24)),
                      "Pulso-semanal-completa-" + String(BackupPolicy.fileName(.daily, at: at(15)).suffix(24))]
        let fullNew = BackupPolicy.fileName(.safety, reason: "borrar", content: .full, at: at(2))
        let fullOld = "Pulso-antes-de-restaurar-" + String(BackupPolicy.fileName(.daily, at: at(3)).suffix(24))
        let lights = (4...7).map { BackupPolicy.fileName(.safety, reason: "importar", content: .light, at: at(Double($0))) }
        let month = BackupPolicy.fileName(.safety, reason: "restaurar", content: .month, at: at(0.5))
        XCTAssertNotNil(BackupPolicy.parse(weekly[1]))
        let plan = BackupPolicy.plan(existing: archives + weekly + [fullNew, fullOld, month] + lights, now: base)
        for a in archives { XCTAssertFalse(plan.delete.contains(a), a) }
        XCTAssertFalse(plan.makeWeekly)
        XCTAssertEqual(Set(plan.delete.filter { $0.contains("semanal") }), [weekly[2]], "at most 2 weekly, old ones included")
        // Two full safety copies (two «Borrar todo», or an old one) both stay: they may hold settings, journal or
        // imports nothing else has. 7 safety copies: only the 2 oldest go, by count.
        XCTAssertFalse(plan.delete.contains(fullOld))
        XCTAssertFalse(plan.delete.contains(fullNew))
        XCTAssertFalse(plan.delete.contains(month))
        XCTAssertEqual(Set(plan.delete.filter { BackupPolicy.parse($0)?.kind == .safety }), [lights[2], lights[3]])
    }

    /// The known gap: «Borrar todo» twice in a row used to leave the first erase's current-month seconds only in
    /// a safety copy the rotation could drop. Now every month, the current one included, is archived first.
    func testEraseTwiceNeverLosesCurrentMonthSeconds() throws {
        let d = try populated()
        let dir = try tempDir()
        let nov15 = Date(timeIntervalSince1970: TimeInterval(ts(2026, 11, 15)))
        try d.archiveAllMonths(in: dir, now: nov15, calendar: utc)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir).sorted()
        XCTAssertEqual(names, ["Pulso-segundos-2026-09.sqlite", "Pulso-segundos-2026-10.sqlite", "Pulso-segundos-2026-11.sqlite"])
        try d.eraseAll()

        // New November seconds after the first erase, then a second erase.
        try d.insert([sample(ts(2026, 11, 16)), sample(ts(2026, 11, 17))])
        let nov18 = Date(timeIntervalSince1970: TimeInterval(ts(2026, 11, 18)))
        try d.archiveAllMonths(in: dir, now: nov18, calendar: utc)
        try d.eraseAll()
        let nov = try PulsoDatabase(path: dir + "/Pulso-segundos-2026-11.sqlite").samples(from: 0, to: Int.max).map(\.ts)
        XCTAssertEqual(nov, [ts(2026, 11, 1, 0), ts(2026, 11, 5), ts(2026, 11, 16), ts(2026, 11, 17)], "both erases' seconds")
        XCTAssertEqual(try PulsoDatabase(path: dir + "/Pulso-segundos-2026-10.sqlite").sampleCount(), 6)

        // Once November closes, the archive written mid-month is refreshed (merged) with the rest of the month.
        try d.insert([sample(ts(2026, 11, 28))])
        let dec3 = Date(timeIntervalSince1970: TimeInterval(ts(2026, 12, 3)))
        XCTAssertEqual(try d.archiveNextMonth(in: dir, now: dec3, calendar: utc, refresh: true), "2026-11")
        XCTAssertEqual(try PulsoDatabase(path: dir + "/Pulso-segundos-2026-11.sqlite").sampleCount(), 5)
        // Nothing to archive: no failure, no file.
        try d.eraseAll()
        try d.archiveAllMonths(in: dir, now: dec3, calendar: utc)
        // Copies only (opening an archive above can leave its own -wal/-shm next to it).
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".sqlite") }.count, 3)
    }

    func testRetentionNeverPrunesSecondsOfAMonthWithoutItsArchive() throws {
        let d = try populated()
        let dir = try tempDir()
        let now = Date(timeIntervalSince1970: TimeInterval(ts(2026, 11, 15)))
        // No coverage recorded yet: the retention limit deletes nothing.
        try d.pruneSamples(olderThan: ts(2026, 11, 1, 0))
        XCTAssertEqual(try d.sampleCount(), 10)
        XCTAssertEqual(try d.updateArchiveCoverage(in: dir, now: now, calendar: utc), ts(2026, 9, 10))
        try d.pruneSamples(olderThan: ts(2026, 11, 1, 0))
        XCTAssertEqual(try d.sampleCount(), 10, "September has no archive")

        XCTAssertEqual(try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: false), "2026-09")
        XCTAssertEqual(try d.updateArchiveCoverage(in: dir, now: now, calendar: utc), ts(2026, 10, 1, 0))
        try d.pruneSamples(olderThan: ts(2026, 11, 1, 0))
        XCTAssertEqual(try d.sampleCount(), 8, "only September, archived, goes")
        XCTAssertEqual(try d.liveHR(from: 0, to: Int.max).count, 1)

        // A damaged October archive does not count.
        try "not a database".write(toFile: dir + "/Pulso-segundos-2026-10.sqlite", atomically: true, encoding: .utf8)
        XCTAssertEqual(try d.updateArchiveCoverage(in: dir, now: now, calendar: utc), ts(2026, 10, 1, 0))
        try FileManager.default.removeItem(atPath: dir + "/Pulso-segundos-2026-10.sqlite")

        XCTAssertEqual(try d.archiveNextMonth(in: dir, now: now, calendar: utc, refresh: false), "2026-10")
        XCTAssertEqual(try d.updateArchiveCoverage(in: dir, now: now, calendar: utc), ts(2026, 11, 1, 0))
        try d.pruneSamples(olderThan: ts(2026, 12, 1, 0))
        XCTAssertEqual(try d.samples(from: 0, to: Int.max).map(\.ts), [ts(2026, 11, 1, 0), ts(2026, 11, 5)], "the current month is never pruned")
        XCTAssertEqual(try d.liveHR(from: 0, to: Int.max).count, 0)
    }

    func testMonthBoundariesFollowTheLocalCalendarAcrossDaylightSaving() throws {
        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = TimeZone(identifier: "Europe/Madrid")!
        // October 2026 in Madrid: starts at 00:00 CEST (UTC+2), ends at 00:00 CET (UTC+1) after the change on the 25th.
        let r = try XCTUnwrap(BackupPolicy.monthRange("2026-10", calendar: madrid))
        XCTAssertEqual(r.from, ts(2026, 9, 30, 22))
        XCTAssertEqual(r.to, ts(2026, 10, 31, 23))
        XCTAssertEqual(r.to - r.from, 31 * 86400 + 3600)
        XCTAssertEqual(BackupPolicy.monthKey(Date(timeIntervalSince1970: TimeInterval(ts(2026, 10, 31, 23))), calendar: madrid), "2026-11")
        let now = Date(timeIntervalSince1970: TimeInterval(ts(2027, 1, 2)))
        XCTAssertEqual(BackupPolicy.closedMonths(firstSecond: ts(2026, 10, 3), now: now, calendar: madrid), ["2026-10", "2026-11", "2026-12"])
        XCTAssertEqual(BackupPolicy.closedMonths(firstSecond: ts(2027, 1, 1), now: now, calendar: madrid), [])
    }
}
