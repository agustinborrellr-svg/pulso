import XCTest
import PulsoStore
@testable import PulsoAnalytics

/// Replays a real backup (`PULSO_REAL_DB=/path/copy.sqlite`) through the current engine and prints what it finds.
/// Skipped without the variable: the data is personal and never lives in the repo.
final class RealDataReplayTests: XCTestCase {
    func testReplayRealBackup() throws {
        guard let src = ProcessInfo.processInfo.environment["PULSO_REAL_DB"] else { throw XCTSkip("PULSO_REAL_DB not set") }
        let path = NSTemporaryDirectory() + "pulso-replay-\(UUID().uuidString).sqlite"
        try FileManager.default.copyItem(atPath: src, toPath: path)
        let db = try PulsoDatabase(path: path)
        guard let bounds = try db.sampleBounds() else { return XCTFail("no samples") }
        let now = Date(timeIntervalSince1970: TimeInterval(bounds.last + 60))
        let days = try DayEngine(db: db).recompute(fromDay: nil, now: now)
        func t(_ ts: Int?) -> String { ts.map { Date(timeIntervalSince1970: TimeInterval($0)).formatted(date: .omitted, time: .shortened) } ?? "–" }
        for d in days {
            print("DAY \(d.day) cycle \(t(d.cycleStart))→\(t(d.cycleEnd)) recovery \(d.recovery.map { "\($0)" } ?? "nil") strain \(d.strain ?? -1) steps \(d.steps ?? -1) kcal \(Int(d.kcal ?? -1)) sleep \(d.sleepMinutes ?? -1) naps \(d.napMinutes ?? 0) stressAvg \(d.stressAvg ?? -1) high \(d.stressHighMinutes ?? -1) maxHR \(d.maxHR ?? -1)")
            print("STRESS \(d.stressHourly.enumerated().compactMap { i, v in v.map { "\(i)h:\(String(format: "%.2f", $0))" } }.joined(separator: " "))")
        }
        for s in try db.sleeps(from: bounds.first - 86400, to: bounds.last + 86400) {
            print("SLEEP \(t(s.start))–\(t(s.end)) nap=\(s.isNap) manual=\(s.manual) asleep=\(Int(s.asleepMinutes)) confirmed=\(s.kindConfirmed)")
        }
        for w in try db.workouts(from: bounds.first, to: bounds.last + 60) {
            print("WORKOUT \(t(w.start))–\(t(w.end)) \(w.sport) \(w.source) strain \(w.strain ?? -1)")
        }
        let merged = HistoryMerge.days(measured: days, imported: try db.importedDays(), profile: db.profile)
        if let last = merged.last { print("MERGED \(last.day) recovery \(last.recovery ?? -1) nightImported \(last.nightImported) sleep \(last.sleepMinutes ?? -1)") }
        for (label, hour) in [("next 07:00", 7), ("next 10:00", 10)] {
            let morning = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now.addingTimeInterval(86400))!
            print("NIGHTSTATUS \(label): \(NightStatus.evaluate(now: morning, currentCycleDay: days.last?.day ?? "", recentCycleStarts: days.compactMap(\.cycleStart), lastSampleTs: bounds.last))")
        }
    }
}
