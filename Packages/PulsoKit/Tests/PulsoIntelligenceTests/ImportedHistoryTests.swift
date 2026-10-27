import XCTest
import PulsoStore
import PulsoAnalytics
@testable import PulsoIntelligence

/// With only a WHOOP import (no strap yet) Inteligencia and VO₂max must still have something to say.
final class ImportedHistoryTests: XCTestCase {
    func testImportedHistoryFeedsIntelligenceAndVO2() throws {
        guard let dir = ProcessInfo.processInfo.environment["PULSO_WHOOP_EXPORT"] else { throw XCTSkip("PULSO_WHOOP_EXPORT not set") }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let names = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.lowercased().hasSuffix(".csv") }
        let files = try names.map { WhoopExport.File(name: $0, text: try String(contentsOfFile: dir + "/" + $0, encoding: .utf8)) }
        let bundle = WhoopExport.read(files, calendar: cal)
        var profile = Profile()
        profile.birthYear = 1990
        let days = HistoryMerge.days(measured: [], imported: bundle.days, profile: profile)
        let vo2 = days.compactMap(\.vo2max)
        print("IMPORT VO2: \(vo2.count) días, último \(vo2.last ?? -1)")
        XCTAssertGreaterThan(vo2.count, 100, "every imported day with a resting HR gets a VO₂max")
        XCTAssert(vo2.allSatisfy { (25...80).contains($0) })

        let sleeps = HistoryMerge.sleeps(from: bundle.days, excluding: [])
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 20))!
        let report = Intelligence.report(days: days, sleeps: sleeps, workouts: bundle.workouts, journal: bundle.journal, now: now, calendar: cal)
        let all = report.sections.flatMap(\.metrics)
        let available = all.filter(\.isAvailable)
        print("IMPORT INTELIGENCIA: \(available.count) de \(all.count) métricas con datos")
        for m in all { print("  \(m.isAvailable ? "✓" : "·") \(m.name): \(m.summary.prefix(90))") }
        XCTAssertGreaterThanOrEqual(available.count, all.count / 2, "most of Inteligencia works from the import alone")
    }
}
