import XCTest
import WhoopProtocol
import PulsoStore
@testable import PulsoAnalytics

final class AnalyticsTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    func tempDB() throws -> PulsoDatabase {
        let path = NSTemporaryDirectory() + "pulso-test-\(UUID().uuidString).sqlite"
        return try PulsoDatabase(path: path)
    }

    func midnight(_ y: Int, _ m: Int, _ d: Int) -> Int {
        Int(calendar.date(from: DateComponents(year: y, month: m, day: d))!.timeIntervalSince1970)
    }

    func testHRVMath() {
        // Alternating 800/850 ms → every successive diff is 50 ms → RMSSD 50.
        let run: RRRun = (0..<100).map { $0 % 2 == 0 ? 800 : 850 }
        XCTAssertEqual(HRV.rmssd([run])!, 50, accuracy: 0.001)
        // An ectopic beat is removed and splits the run instead of creating a huge difference.
        var withEctopic = run
        withEctopic[50] = 400
        let cleaned = HRV.clean([withEctopic])
        XCTAssertEqual(HRV.rmssd(cleaned)!, 50, accuracy: 0.001)
        XCTAssertGreaterThan(cleaned.count, 1)
    }

    func testRRRunsBreakOnMissedBeatButNotOnEmptySeconds() {
        // 50 bpm: 1200 ms beats, so every sixth second carries no beat — that must NOT break the run.
        var samples: [Sample] = []
        var beat = 0.3
        for t in 0..<120 {
            var rr: [Int] = []
            while beat < Double(t + 1) {
                if beat >= Double(t) { rr.append(1200) }
                beat += 1.2
            }
            // Drop one beat report at t == 60 (a missed beat).
            if t == 60 { rr = [] }
            samples.append(Sample(ts: t, hr: 50, rr: rr))
        }
        let runs = Epochs.rrRuns(samples, from: 0, to: 120)
        XCTAssertEqual(runs.count, 2, "a missed beat splits the run exactly once")
        XCTAssertGreaterThan(runs[0].count, 40)
    }

    func testRespiratoryRateFromRSA() {
        var s = SyntheticStrap()
        var samples: [Sample] = []
        for t in 0..<900 {
            let h = s.second(t, .sleep(stage: 1, baseHR: 56, rsa: 0.07), respHz: 0.25)
            samples.append(Sample(ts: t, hr: h.heartRate.map { Int($0) }, rr: h.rr.map { Int($0) }))
        }
        let runs = HRV.clean(Epochs.rrRuns(samples, from: 0, to: 900))
        let rate = HRV.respiratoryRate(runs)
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate ?? 0, 15, accuracy: 1.5)
    }

    func testStrainScale() {
        XCTAssertEqual(Strain.score(load: 0), 0)
        XCTAssertEqual(Strain.score(load: Strain.ceilingLoad), 21, accuracy: 0.001)
        let hour3 = Strain.score(load: 180)
        XCTAssertTrue((11...15).contains(hour3), "60 min at 70% HRR should be a solid workout, got \(hour3)")
        XCTAssertLessThan(Strain.score(load: 30), Strain.score(load: 180))
    }

    func testRecoveryRespondsToHRV() {
        var hist: [DaySummary] = []
        for i in 0..<14 {
            var d = DaySummary(day: String(format: "2026-01-%02d", i + 1))
            d.hrv = 60 + Double(i % 3) * 3
            d.rhr = 52 + Double(i % 2)
            d.respRate = 14.5
            d.skinTemp = 34.5
            hist.append(d)
        }
        let b = Baselines.from(history: hist)
        let good = Recovery.compute(hrv: 75, rhr: 50, resp: 14.4, skinTemp: 34.5, spo2: nil, sleepPerformance: 0.95, baselines: b)
        let bad = Recovery.compute(hrv: 40, rhr: 60, resp: 16.5, skinTemp: 35.5, spo2: nil, sleepPerformance: 0.6, baselines: b)
        XCTAssertGreaterThan(good.score!, 67)
        XCTAssertLessThan(bad.score!, 34)
        let cold = Recovery.compute(hrv: 60, rhr: 52, resp: nil, skinTemp: nil, spo2: nil, sleepPerformance: 0.9, baselines: Baselines())
        XCTAssertTrue(cold.calibrating)
        XCTAssertNil(cold.score)
    }

    func testFullPipelineOnSyntheticWeek() throws {
        let db = try tempDB()
        var p = Profile()
        p.birthYear = 1990
        p.rawRetentionDays = 0
        db.profile = p
        var strap = SyntheticStrap()
        let start = midnight(2026, 9, 1)
        var all: [HistorySample] = []
        for d in 0..<7 {
            // Night 5 is a rough one: lower HRV (smaller RSA) and higher resting HR.
            let rough = d == 5
            all += strap.day(startingAt: start + d * 86400, restingHR: rough ? 62 : 53, rsa: rough ? 0.025 : 0.065)
        }
        try db.insert(all)
        XCTAssertEqual(try db.sampleCount(), all.count)

        let engine = DayEngine(db: db, calendar: calendar)
        let now = Date(timeIntervalSince1970: TimeInterval(start + 7 * 86400 + 12 * 3600))
        let days = try engine.recompute(now: now)
        XCTAssertGreaterThanOrEqual(days.count, 6)

        // Every morning from the 2nd has a main sleep near 23:00 → 07:00.
        let mornings = days.filter { $0.sleepStart != nil }
        XCTAssertGreaterThanOrEqual(mornings.count, 6)
        for d in mornings {
            let onset = SleepCoach.minutesAfterMidnight(ts: d.sleepStart!, calendar: calendar)
            let wake = SleepCoach.minutesAfterMidnight(ts: d.sleepEnd!, calendar: calendar)
            XCTAssertLessThan(Stats.circularDistanceMinutes(onset, 23 * 60), 45, "onset \(onset) on \(d.day)")
            XCTAssertLessThan(Stats.circularDistanceMinutes(wake, 7 * 60), 30, "wake \(wake) on \(d.day)")
            XCTAssertNotNil(d.hrv)
            XCTAssertNotNil(d.rhr)
            XCTAssertGreaterThan(d.deepMinutes ?? 0, 20)
            XCTAssertGreaterThan(d.remMinutes ?? 0, 20)
            if let r = d.respRate { XCTAssertEqual(r, 14, accuracy: 2) }
            XCTAssertEqual(d.spo2 ?? 0, 96, accuracy: 0.5)
        }

        // Workouts are detected and strain lands in a sensible range.
        let dayWithRun = days.first { $0.day == DayKey.string(ts: start + 86400, calendar: calendar) }!
        XCTAssertGreaterThanOrEqual(dayWithRun.workoutCount, 1)
        XCTAssertTrue((8.0...19.0).contains(dayWithRun.strain ?? 0), "strain \(String(describing: dayWithRun.strain))")
        let workouts = try db.workouts(from: start, to: start + 8 * 86400)
        XCTAssertTrue(workouts.contains { $0.sport == "Carrera" && abs($0.durationMinutes - 45) < 8 })

        // Recovery kicks in after calibration and punishes the rough night.
        let roughDay = DayKey.string(ts: start + 6 * 86400, calendar: calendar)
        let scored = days.filter { $0.recovery != nil }
        XCTAssertFalse(scored.isEmpty)
        if let rough = days.first(where: { $0.day == roughDay })?.recovery {
            let others = scored.filter { $0.day != roughDay }.compactMap { $0.recovery }
            XCTAssertLessThan(rough, Stats.mean(others)! - 15, "rough night should score clearly lower")
        } else {
            XCTFail("rough day should have a recovery score")
        }

        // Exports work.
        let csv = Exporter.daysCSV(days)
        XCTAssertTrue(csv.hasPrefix("fecha,recuperacion"))
    }

    func testWhoopCSVImport() {
        let csv = """
        Cycle start time,Cycle end time,Cycle timezone,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Skin temp (celsius),Blood oxygen %,Day Strain,Energy burned (cal),Max HR (bpm),Average HR (bpm),Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min)
        2026-08-01 23:10:00,2026-08-02 23:30:00,UTC+02:00,72,51,68,34.2,96.5,12.4,2400,171,68,2026-08-01 23:10:00,2026-08-02 07:05:00,91,14.2,430,470
        """
        let days = WhoopExportImporter.parse(csv: csv, calendar: calendar)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].day, "2026-08-02")
        XCTAssertEqual(days[0].hrv, 68)
        XCTAssertEqual(days[0].rhr, 51)
        XCTAssertEqual(days[0].sleepPerformance ?? 0, 0.91, accuracy: 0.0001)
    }

    // MARK: WHOOP export (Spanish and English, any subset of files)

    static let esCycles = """
    Hora de inicio del ciclo,Hora de finalización del ciclo,Zona horaria del ciclo,Puntuación de recuperación (%),Frecuencia cardíaca en reposo (lpm),Variabilidad de la frecuencia cardíaca (ms),Temp. cutánea (grados centígrados),Oxígeno en sangre %,Esfuerzo del día,Energía quemada (cal),FC máx. (lpm),FC promedio (lpm),Inicio del sueño,Inicio de la vigilia,Calificación del sueño (%),Frecuencia respiratoria (rpm),Duración del sueño (min),Tiempo en la cama (min),Duración de sueño ligero (min),Duración de sueño profundo (SWS) (min),Duración de sueño REM (min),Tempo despierto/a (min),Sueño necesario (min),Deuda de sueño (min),Eficiencia del sueño %,Regularidad del sueño %
    2026-10-26 01:19:37,,UTC+01:00,45,53,77,33.15,95.44,,,,,2026-10-26 01:19:37,2026-10-26 08:08:39,77,16.5,383,409,186,126,71,26,603,106,93,86
    2026-10-25 01:14:24,2026-10-26 01:19:37,UTC+01:00,69,48,93,33.33,95.29,14.1,2582,148,71,2026-10-25 01:14:24,2026-10-25 09:16:58,78,15.6,409,482,217,103,89,73,575,78,84,79
    """

    static let esSleeps = """
    Hora de inicio del ciclo,Hora de finalización del ciclo,Zona horaria del ciclo,Inicio del sueño,Inicio de la vigilia,Calificación del sueño (%),Frecuencia respiratoria (rpm),Duración del sueño (min),Tiempo en la cama (min),Duración de sueño ligero (min),Duración de sueño profundo (SWS) (min),Duración de sueño REM (min),Tempo despierto/a (min),Sueño necesario (min),Deuda de sueño (min),Eficiencia del sueño %,Regularidad del sueño %,Siesta
    2026-10-25 01:14:24,2026-10-26 01:19:37,UTC+01:00,2026-10-25 01:14:24,2026-10-25 09:16:58,78,15.6,409,482,217,103,89,73,575,78,84,79,false
    2026-10-25 01:14:24,2026-10-26 01:19:37,UTC+01:00,2026-10-25 16:00:00,2026-10-25 16:25:00,,,22,25,22,0,0,3,,,88,,true
    2026-10-20 00:30:00,2026-10-21 00:40:00,UTC+02:00,2026-10-20 00:30:00,2026-10-20 08:00:00,90,15.0,420,450,200,110,110,30,500,20,93,85,false
    """

    static let esWorkouts = """
    Hora de inicio del ciclo,Hora de finalización del ciclo,Zona horaria del ciclo,Hora de inicio del entrenamiento,Hora de finalización del entrenamiento,Duración (min),Nombre de la actividad,Esfuerzo de actividad,Energía quemada (cal),FC máx. (lpm),FC promedio (lpm),Zona FC 1%,Zona FC 2%,Zona FC 3%,Zona FC 4%,Zona FC 5%,GPS habilitado
    2026-10-25 01:14:24,2026-10-26 01:19:37,UTC+01:00,2026-10-25 11:01:00,2026-10-25 11:44:00,43,HIIT,9.4,84.0,125,84,8,0,0,0,0,false
    2026-10-24 01:24:22,2026-10-25 02:14:24,UTC+02:00,2026-10-25 00:40:00,2026-10-25 01:15:59,35,Natación,6.6,189.0,165,108,47,12,4,0,0,false
    2026-10-23 01:00:00,2026-10-24 01:24:22,UTC+02:00,2026-10-23 18:00:00,2026-10-23 18:30:00,30,Paracaidismo,1.0,40.0,95,80,0,0,0,0,0,false
    """

    static let esJournal = #"""
    Hora de inicio del ciclo,Hora de finalización del ciclo,Zona horaria del ciclo,Texto de la pregunta,"Respondió ""Sí""",Notas
    2026-10-24 01:30:04,2026-10-25 03:30:06,UTC+02:00,¿Tomas bebidas alcohólicas?,true,
    2026-10-24 01:30:04,2026-10-25 03:30:06,UTC+02:00,¿Usaste un dispositivo con pantalla en la cama?,false,
    2026-10-24 01:30:04,2026-10-25 03:30:06,UTC+02:00,¿Desayunaste?,true,"con ""notas"", y comas"
    """#

    func testWhoopExportRecognisesSpanishFiles() {
        XCTAssertEqual(WhoopExport.kind(of: Self.esCycles), .cycles)
        XCTAssertEqual(WhoopExport.kind(of: Self.esSleeps), .sleeps)
        XCTAssertEqual(WhoopExport.kind(of: Self.esWorkouts), .workouts)
        XCTAssertEqual(WhoopExport.kind(of: Self.esJournal), .journal)
        XCTAssertNil(WhoopExport.kind(of: "fecha,importe\n2026-01-01,3"))
    }

    func testWhoopExportAllFilesTogether() throws {
        // Deliberately out of order, plus a file that is not WHOOP's.
        let b = WhoopExport.read([
            .init(name: "entrenamientos.csv", text: Self.esWorkouts),
            .init(name: "journal_entries.csv", text: Self.esJournal),
            .init(name: "sueño.csv", text: Self.esSleeps),
            .init(name: "notas.csv", text: "a,b\n1,2"),
            .init(name: "physiological_cycles.csv", text: Self.esCycles),
        ], calendar: calendar)
        XCTAssertEqual(b.files.map(\.name), ["entrenamientos.csv", "journal_entries.csv", "sueño.csv", "notas.csv", "physiological_cycles.csv"])
        XCTAssertEqual(b.files.map(\.kind), [.workouts, .journal, .sleeps, nil, .cycles])
        XCTAssertEqual(b.files.map(\.used), [3, 3, 3, 0, 2])

        XCTAssertEqual(b.days.map(\.day), ["2026-10-20", "2026-10-25", "2026-10-26"])
        let d25 = try XCTUnwrap(b.days.first { $0.day == "2026-10-25" })
        XCTAssertEqual(d25.recovery, 69)
        XCTAssertEqual(d25.hrv, 93)
        XCTAssertEqual(d25.rhr, 48)
        XCTAssertEqual(d25.strain, 14.1)
        XCTAssertEqual(d25.kcal, 2582)
        XCTAssertEqual(d25.deepMinutes, 103)
        XCTAssertEqual(d25.remMinutes, 89)
        XCTAssertEqual(d25.sleepDebtMinutes, 78)
        XCTAssertEqual(d25.sleepEfficiency ?? 0, 0.84, accuracy: 1e-9)
        XCTAssertEqual(d25.sleepPerformance ?? 0, 0.78, accuracy: 1e-9)
        XCTAssertEqual(d25.napMinutes, 22, "the nap is counted, not taken for the night")
        XCTAssertEqual(d25.source, "whoop")
        XCTAssertNotNil(d25.cycleEnd, "cycle end is kept so the day can list its workouts")
        XCTAssertEqual(d25.workoutCount, 1, "the HIIT of that cycle; the swim belonged to the previous one")
        XCTAssertNil(b.days.last?.cycleEnd, "the current cycle has no end yet")
        // 09:16:58 at UTC+01:00 = 08:16:58 UTC.
        XCTAssertEqual(d25.sleepEnd, Int(ISO8601DateFormatter().date(from: "2026-10-25T08:16:58Z")!.timeIntervalSince1970))
        // A night only in the sleep file still becomes a day.
        XCTAssertEqual(b.days.first?.sleepMinutes, 420)
        XCTAssertNil(b.days.first?.recovery)

        XCTAssertEqual(b.workouts.count, 3)
        let hiit = try XCTUnwrap(b.workouts.first { $0.sport == "HIIT" })
        XCTAssertEqual(hiit.source, .whoop)
        XCTAssertEqual(hiit.start, Int(ISO8601DateFormatter().date(from: "2026-10-25T10:01:00Z")!.timeIntervalSince1970))
        XCTAssertEqual(hiit.durationMinutes, 43)
        XCTAssertEqual(hiit.strain, 9.4)
        XCTAssertEqual(hiit.maxHR, 125)
        XCTAssertEqual(hiit.zoneMinutes[0], 43 * 0.08, accuracy: 1e-9)
        XCTAssertEqual(hiit.externalID("whoop"), String(hiit.start))
        XCTAssertTrue(hiit.source.isExternal)
        XCTAssertEqual(b.workouts.first { $0.durationMinutes == 30 }?.sport, "Actividad")
        XCTAssertEqual(b.workouts.first { $0.durationMinutes == 30 }?.notes, "Importado: Paracaidismo")
        XCTAssertEqual(WhoopExport.sportName("Driving"), "Conducir")
        XCTAssertEqual(WhoopExport.sportName("Ice Bath"), "Baño de hielo")
        XCTAssertEqual(WhoopExport.sportName("Spin"), "Spinning")
        XCTAssertEqual(WhoopExport.sportName("Table Tennis"), "Pimpón")
        XCTAssertEqual(WhoopExport.sportName("Functional Fitness"), "Entrenamiento funcional")
        XCTAssertEqual(b.workouts.first { $0.strain == 6.6 }?.sport, "Natación")

        XCTAssertEqual(Set(b.journal.map(\.day)), ["2026-10-24"])
        XCTAssertEqual(b.journal.first { $0.key == "alcohol" }?.value, 1)
        XCTAssertEqual(b.journal.first { $0.key == "screens_bed" }?.value, 0)
        XCTAssertEqual(b.journal.first { $0.key.hasPrefix("whoop:") }?.key, "whoop:¿Desayunaste?")
    }

    func testWhoopExportAnySubsetWorks() {
        // Only the workouts: no days, no journal, nothing breaks.
        let w = WhoopExport.read([.init(name: "entrenamientos.csv", text: Self.esWorkouts)], calendar: calendar)
        XCTAssertEqual(w.workouts.count, 3)
        XCTAssertTrue(w.days.isEmpty)
        // Only the sleep file: days with sleep but no recovery.
        let s = WhoopExport.read([.init(name: "sueño.csv", text: Self.esSleeps)], calendar: calendar)
        XCTAssertEqual(s.days.count, 2)
        XCTAssertTrue(s.days.allSatisfy { $0.recovery == nil && $0.sleepMinutes != nil })
        // Nothing at all, an empty file, a header with no rows.
        XCTAssertTrue(WhoopExport.read([], calendar: calendar).files.isEmpty)
        let headerOnly = String(Self.esCycles.prefix { $0 != "\n" })
        let empty = WhoopExport.read([.init(name: "vacío.csv", text: ""), .init(name: "cab.csv", text: headerOnly)], calendar: calendar)
        XCTAssertEqual(empty.files.map(\.kind), [nil, .cycles])
        XCTAssertEqual(empty.files.map(\.rows), [0, 0])
        XCTAssertTrue(empty.days.isEmpty)
        // Windows line endings and a BOM.
        let crlf = "\u{FEFF}" + Self.esCycles.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(WhoopExport.read([.init(name: "c.csv", text: crlf)], calendar: calendar).days.count, 2)
    }

    func testWhoopImportTwiceChangesNothing() throws {
        let db = try tempDB()
        // Something the user logged in Pulso and a strap-detected bout over the HIIT.
        try db.setJournal(day: "2026-10-24", key: "alcohol", value: 0)
        let hiitStart = Int(ISO8601DateFormatter().date(from: "2026-10-25T10:01:00Z")!.timeIntervalSince1970)
        try db.save(Workout(start: hiitStart + 60, end: hiitStart + 40 * 60, sport: "Actividad", source: .auto))
        let files: [WhoopExport.File] = [
            .init(name: "c.csv", text: Self.esCycles), .init(name: "w.csv", text: Self.esWorkouts), .init(name: "j.csv", text: Self.esJournal),
        ]
        let first = try WhoopExport.store(WhoopExport.read(files, calendar: calendar), in: db)
        XCTAssertEqual(first.days, 2)
        XCTAssertEqual(first.workoutsNew, 3, "the automatic bout is replaced by WHOOP's HIIT")
        XCTAssertEqual(first.journal, 2, "the alcohol answer logged in Pulso is not overwritten")
        XCTAssertEqual(try db.journal(day: "2026-10-24")["alcohol"], 0)
        let all = try db.workouts(from: 0, to: Int.max / 2)
        XCTAssertEqual(all.count, 3)
        XCTAssertFalse(all.contains { $0.source == .auto })

        let second = try WhoopExport.store(WhoopExport.read(files, calendar: calendar), in: db)
        XCTAssertEqual(second.workoutsNew, 0)
        XCTAssertEqual(second.workoutsKnown, 3)
        XCTAssertEqual(second.journal, 0)
        XCTAssertEqual(try db.workouts(from: 0, to: Int.max / 2).count, 3)
        XCTAssertEqual(try db.importedDays().count, 2)

        // Adding the sleep file later fills sleep-only nights and naps without losing the cycle values.
        _ = try WhoopExport.store(WhoopExport.read([.init(name: "s.csv", text: Self.esSleeps)], calendar: calendar), in: db)
        let days = try db.importedDays()
        XCTAssertEqual(days.count, 3)
        let d25 = try XCTUnwrap(days.first { $0.day == "2026-10-25" })
        XCTAssertEqual(d25.recovery, 69)
        XCTAssertEqual(d25.napMinutes, 22)
    }

    func testWhoopTimeZones() {
        XCTAssertEqual(WhoopExport.zone("UTC+01:00")?.secondsFromGMT(), 3600)
        XCTAssertEqual(WhoopExport.zone("UTC-05:30")?.secondsFromGMT(), -(5 * 3600 + 1800))
        XCTAssertEqual(WhoopExport.zone("+0200")?.secondsFromGMT(), 7200)
        XCTAssertEqual(WhoopExport.zone("UTC")?.secondsFromGMT(), 0)
        XCTAssertNotNil(WhoopExport.zone("Europe/Madrid"))
        XCTAssertNil(WhoopExport.zone("mañana"))
    }

    /// Runs against a real export when PULSO_WHOOP_EXPORT points at its folder (never committed).
    func testRealWhoopExportIfAvailable() throws {
        guard let dir = ProcessInfo.processInfo.environment["PULSO_WHOOP_EXPORT"] else { throw XCTSkip("PULSO_WHOOP_EXPORT not set") }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.lowercased().hasSuffix(".csv") }
        let files = try names.sorted().map { WhoopExport.File(name: $0, text: try String(contentsOfFile: dir + "/" + $0, encoding: .utf8)) }
        let b = WhoopExport.read(files, calendar: calendar)
        for f in b.files {
            print("WHOOP real: \(f.name) -> \(f.kind?.rawValue ?? "?") filas=\(f.rows) usadas=\(f.used)")
            XCTAssertNotNil(f.kind, f.name)
            XCTAssertGreaterThan(f.used, 0, f.name)
        }
        print("WHOOP real: dias=\(b.days.count) entrenos=\(b.workouts.count) diario=\(b.journal.count)")
        print("WHOOP real: deportes=\(Dictionary(grouping: b.workouts, by: \.sport).mapValues(\.count))")
        print("WHOOP real: primero=\(b.days.first?.day ?? "-") ultimo=\(b.days.last?.day ?? "-") con recuperacion=\(b.days.filter { $0.recovery != nil }.count)")
        let db = try tempDB()
        let first = try WhoopExport.store(b, in: db)
        let second = try WhoopExport.store(WhoopExport.read(files, calendar: calendar), in: db)
        print("WHOOP real: guardado 1a vez=\(first) 2a vez=\(second)")
        XCTAssertEqual(second.workoutsNew + second.workoutsLinked + second.journal, 0, "a second import adds nothing")
        XCTAssertEqual(try db.workouts(from: 0, to: Int.max / 2).count, first.workoutsNew)
    }

    func testInsights() {
        var days: [DaySummary] = []
        var journal: [JournalEntry] = []
        for i in 1...20 {
            let key = String(format: "2026-03-%02d", i)
            var d = DaySummary(day: key)
            let drankYesterday = i > 1 && (i - 1) % 2 == 0
            d.recovery = drankYesterday ? 40 : 70
            d.hrv = drankYesterday ? 45 : 65
            days.append(d)
            journal.append(JournalEntry(day: key, key: "alcohol", value: i % 2 == 0 ? 1 : 0))
        }
        let ins = Insights.compute(journal: journal, days: days, calendar: calendar)
        let alcohol = ins.first { $0.key == "alcohol" }
        XCTAssertNotNil(alcohol)
        XCTAssertEqual(alcohol?.recoveryDelta ?? 0, -30, accuracy: 0.1)
    }
}
