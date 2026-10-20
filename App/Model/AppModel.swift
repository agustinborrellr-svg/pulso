import Foundation
import SwiftUI
import Combine
import UserNotifications
import WhoopProtocol
import PulsoStore
import PulsoAnalytics

struct LivePoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let hr: Int
}

struct LiveWorkout: Equatable {
    var start: Date
    var sport: String
    var load: Double = 0
    var kcal: Double = 0
    var maxHR: Int = 0
    var hrSum: Double = 0
    var hrCount: Int = 0
}

/// App-wide state. All published properties live on the main actor; heavy analysis runs on a
/// background queue and publishes the results back.
@MainActor
final class AppModel: ObservableObject {
    // Strap
    @Published var strapState: StrapState = .noStrap
    @Published var identity = StrapIdentity()
    @Published var battery: Double?
    @Published var charging: Bool?
    @Published var lastSync: Date?
    @Published var log: [String] = []

    // Data
    @Published var days: [DaySummary] = []
    @Published var selectedDay: String = DayKey.string(Date())
    @Published var profile: Profile
    @Published var analyzing = false
    @Published var analysisProgress: Double = 0
    @Published var insights: [Insight] = []
    @Published var errorMessage: String?
    @Published var rawSampleCount = 0

    // Live
    @Published var liveHR: Int?
    @Published var liveRMSSD: Double?
    @Published var livePoints: [LivePoint] = []
    @Published var liveWorkout: LiveWorkout?
    private var liveRR: [Double] = []
    private var lastLiveAt: Date?

    // Alarm
    @Published var alarmEnabled: Bool = UserDefaults.standard.bool(forKey: "pulso.alarm.enabled")
    @Published var alarmTime: Date = (UserDefaults.standard.object(forKey: "pulso.alarm.time") as? Date)
        ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()

    let db: PulsoDatabase
    let strap = StrapManager()
    let health = HealthExporter()
    private let analysisQueue = DispatchQueue(label: "pulso.analysis", qos: .utility)
    private lazy var engine = DayEngine(db: db)

    init() {
        let path = (try? PulsoDatabase.defaultPath()) ?? NSTemporaryDirectory() + "pulso.sqlite"
        do {
            db = try PulsoDatabase(path: path)
        } catch {
            // Last resort: an in-temp database so the app still opens.
            db = try! PulsoDatabase(path: NSTemporaryDirectory() + "pulso-fallback.sqlite")
        }
        profile = db.profile
        lastSync = db.get(Date.self, for: "lastSync")
        strap.delegate = self
        let database = db
        strap.persist = { samples in try database.insert(samples) }
        reload()
    }

    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "pulso.onboarded") }
        set {
            UserDefaults.standard.set(newValue, forKey: "pulso.onboarded")
            objectWillChange.send()
        }
    }

    // MARK: - Derived

    var today: DaySummary? { days.last { $0.day == DayKey.string(Date()) } }

    var selected: DaySummary? { days.first { $0.day == selectedDay } }

    func day(_ key: String) -> DaySummary? { days.first { $0.day == key } }

    var baselines: Baselines {
        Baselines.from(history: days.filter { $0.day < selectedDay })
    }

    var heartRateModel: HeartRateModel {
        let rhr = Baseline.from(days.suffix(30).compactMap { $0.rhr }, floor: 1)?.center ?? 60
        let observed = days.suffix(180).compactMap { $0.maxHR }.max() ?? 0
        let maxHR = Double(profile.maxHROverride ?? Int(max(HeartRateModel.tanakaMax(age: profile.age), observed)))
        return HeartRateModel(restingHR: rhr, maxHR: maxHR)
    }

    func shiftSelectedDay(_ delta: Int) {
        let next = DayKey.shift(selectedDay, days: delta)
        guard next <= DayKey.string(Date()) else { return }
        selectedDay = next
    }

    // MARK: - Loading

    func reload() {
        do {
            let from = DayKey.shift(DayKey.string(Date()), days: -400)
            days = try db.days(from: from, to: "9999-12-31")
            let journal = try db.allJournal()
            insights = Insights.compute(journal: journal, days: days)
            if rawSampleCount == 0, (try? db.hasSamples()) == true { rawSampleCount = 1 }
            refreshSampleCount()
        } catch {
            errorMessage = "No se pudieron leer los datos: \(error)"
        }
    }

    /// Counting every stored second scans the table, so it runs off the main thread.
    func refreshSampleCount() {
        let db = self.db
        analysisQueue.async {
            let n = (try? db.sampleCount()) ?? 0
            Task { @MainActor in self.rawSampleCount = n }
        }
    }

    func sleep(for day: DaySummary) -> SleepSession? {
        guard let id = day.sleepId else { return nil }
        return try? db.sleep(id: id)
    }

    func naps(on day: String) -> [SleepSession] {
        guard let d = DayKey.date(day) else { return [] }
        let a = Int(d.timeIntervalSince1970)
        return ((try? db.sleeps(from: a, to: a + 86400)) ?? []).filter { $0.isNap }
    }

    func workouts(for day: DaySummary) -> [Workout] {
        guard let a = day.cycleStart, let b = day.cycleEnd else { return [] }
        return (try? db.workouts(from: a, to: b)) ?? []
    }

    func samples(from: Date, to: Date) -> [Sample] {
        (try? db.samples(from: Int(from.timeIntervalSince1970), to: Int(to.timeIntervalSince1970))) ?? []
    }

    // MARK: - Analysis

    /// Recomputes from `fromDay` (default: two days before the oldest new data) through today.
    private var pendingRecompute: String??

    func recompute(fromDay: String? = nil) {
        guard !analyzing else {
            // Queue it: keep the earliest requested start (nil = everything).
            if let pending = pendingRecompute {
                if let a = pending, let b = fromDay { pendingRecompute = .some(min(a, b)) } else { pendingRecompute = .some(nil) }
            } else {
                pendingRecompute = .some(fromDay)
            }
            return
        }
        analyzing = true
        lastRecompute = Date()
        analysisProgress = 0
        let engine = self.engine
        analysisQueue.async {
            var failure: String?
            do {
                try engine.recompute(fromDay: fromDay, progress: { p in
                    Task { @MainActor in self.analysisProgress = p }
                })
            } catch {
                failure = "\(error)"
            }
            let message = failure
            Task { @MainActor in
                self.analyzing = false
                if let message { self.errorMessage = "Error analizando: \(message)" }
                self.reload()
                self.exportToHealthIfEnabled()
                if let next = self.pendingRecompute {
                    self.pendingRecompute = nil
                    self.recompute(fromDay: next)
                }
            }
        }
    }

    // MARK: - Strap actions

    func connect() { strap.connect() }
    func pairNew() { strap.pairNew() }
    func forgetStrap() { strap.forget() }
    func syncNow() { strap.sync(force: true) }
    func buzz() { strap.buzz() }

    func setLive(_ on: Bool) {
        strap.setLive(on)
        if !on && liveWorkout == nil {
            liveHR = nil
        }
    }

    private var lastRecompute: Date?

    func appBecameActive() {
        strap.connect()
        strap.sync(force: false)
        let stale = lastRecompute.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true
        if rawSampleCount > 0 && stale {
            recompute(fromDay: DayKey.shift(DayKey.string(Date()), days: -1))
        }
    }

    // MARK: - Live workouts

    func startWorkout(sport: String) {
        liveWorkout = LiveWorkout(start: Date(), sport: sport)
        setLive(true)
    }

    func stopWorkout(save: Bool) {
        guard let w = liveWorkout else { return }
        liveWorkout = nil
        guard save, Date().timeIntervalSince(w.start) >= 60 else { return }
        let workout = Workout(start: Int(w.start.timeIntervalSince1970), end: Int(Date().timeIntervalSince1970),
                              sport: w.sport, source: .live,
                              strain: Strain.score(load: w.load),
                              avgHR: w.hrCount > 0 ? w.hrSum / Double(w.hrCount) : 0,
                              maxHR: Double(w.maxHR), kcal: w.kcal)
        do {
            try db.save(workout)
        } catch {
            errorMessage = "No se pudo guardar el entreno"
        }
        strap.sync(force: true)
    }

    func saveWorkout(_ w: Workout) {
        _ = try? db.save(w)
        recompute(fromDay: DayKey.shift(DayKey.string(ts: w.start), days: -1))
    }

    func deleteWorkout(_ w: Workout) {
        guard let id = w.id else { return }
        try? db.deleteWorkout(id: id)
        recompute(fromDay: DayKey.shift(DayKey.string(ts: w.start), days: -1))
    }

    // MARK: - Sleep editing

    func saveSleepEdit(_ session: SleepSession, start: Date, end: Date) {
        var s = session
        s.start = Int(start.timeIntervalSince1970)
        s.end = Int(end.timeIntervalSince1970)
        s.manual = true
        _ = try? db.save(s)
        recompute(fromDay: DayKey.shift(DayKey.string(ts: s.end), days: -1))
    }

    func addManualSleep(start: Date, end: Date, nap: Bool) {
        let s = SleepSession(start: Int(start.timeIntervalSince1970), end: Int(end.timeIntervalSince1970), isNap: nap, manual: true)
        _ = try? db.save(s)
        recompute(fromDay: DayKey.shift(DayKey.string(ts: s.end), days: -1))
    }

    func deleteSleep(_ s: SleepSession) {
        guard let id = s.id else { return }
        try? db.deleteSleep(id: id)
        recompute(fromDay: DayKey.shift(DayKey.string(ts: s.end), days: -1))
    }

    // MARK: - Journal

    func journal(for day: String) -> [String: Double] {
        (try? db.journal(day: day)) ?? [:]
    }

    func setJournal(day: String, key: String, on: Bool) {
        try? db.setJournal(day: day, key: key, value: on ? 1 : nil)
        insights = Insights.compute(journal: (try? db.allJournal()) ?? [], days: days)
        objectWillChange.send()
    }

    // MARK: - Profile

    func saveProfile(_ p: Profile) {
        let needsRecompute = p.birthYear != profile.birthYear || p.sex != profile.sex || p.weightKg != profile.weightKg
            || p.heightCm != profile.heightCm || p.maxHROverride != profile.maxHROverride || p.sleepNeedHours != profile.sleepNeedHours
        profile = p
        db.profile = p
        if needsRecompute { recompute(fromDay: DayKey.shift(DayKey.string(Date()), days: -30)) }
        if p.healthKitEnabled { health.requestAuthorization { _ in } }
    }

    // MARK: - Alarm

    func saveAlarm(enabled: Bool, time: Date) {
        alarmEnabled = enabled
        alarmTime = time
        UserDefaults.standard.set(enabled, forKey: "pulso.alarm.enabled")
        UserDefaults.standard.set(time, forKey: "pulso.alarm.time")
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["pulso.alarm"])
        guard enabled else {
            strap.setAlarm(nil)
            return
        }
        let next = nextOccurrence(of: time)
        strap.setAlarm(next)
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Buenos días"
            content.body = "Tu despertador de Pulso."
            content.sound = .default
            let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: "pulso.alarm", content: content, trigger: trigger))
        }
    }

    func nextOccurrence(of time: Date) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: time)
        return cal.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime) ?? time
    }

    // MARK: - Import / export

    func importWhoopCSV(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let imported = WhoopExportImporter.parse(csv: text)
            guard !imported.isEmpty else {
                errorMessage = "No he encontrado días válidos. Usa el archivo physiological_cycles.csv de tu exportación de WHOOP."
                return
            }
            for d in imported { try db.saveImported(d) }
            errorMessage = "Importados \(imported.count) días de WHOOP como referencia para tus líneas base."
            recompute(fromDay: DayKey.shift(DayKey.string(Date()), days: -30))
        } catch {
            errorMessage = "No se pudo importar: \(error.localizedDescription)"
        }
    }

    /// Writes CSV exports to a temporary folder and returns their URLs (for the share sheet).
    func exportFiles(rawDays: Int = 7) -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PulsoExport", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        let stamp = DayKey.string(Date())
        let daysURL = dir.appendingPathComponent("pulso_dias_\(stamp).csv")
        if (try? Exporter.daysCSV((try? db.allDays()) ?? days).write(to: daysURL, atomically: true, encoding: .utf8)) != nil {
            urls.append(daysURL)
        }
        let wURL = dir.appendingPathComponent("pulso_entrenos_\(stamp).csv")
        let workouts = (try? db.workouts(from: 0, to: Int(Date().timeIntervalSince1970) + 86400)) ?? []
        if (try? Exporter.workoutsCSV(workouts).write(to: wURL, atomically: true, encoding: .utf8)) != nil {
            urls.append(wURL)
        }
        let rawURL = dir.appendingPathComponent("pulso_segundos_\(rawDays)d_\(stamp).csv")
        let raw = samples(from: Date().addingTimeInterval(-Double(rawDays) * 86400), to: Date())
        if !raw.isEmpty, (try? Exporter.samplesCSV(raw).write(to: rawURL, atomically: true, encoding: .utf8)) != nil {
            urls.append(rawURL)
        }
        return urls
    }

    func eraseEverything() {
        try? db.eraseAll()
        profile = db.profile
        lastSync = nil
        reload()
    }

    // MARK: - HealthKit

    /// Exports the last three days to Apple Health. The heavy reads run off the main thread.
    func exportToHealthIfEnabled() {
        guard profile.healthKitEnabled else { return }
        let recent = Array(days.suffix(3))
        let db = self.db
        let health = self.health
        analysisQueue.async {
            var sleeps: [SleepSession] = []
            for d in recent {
                if let id = d.sleepId, let s = try? db.sleep(id: id) { sleeps.append(s) }
            }
            let to = Int(Date().timeIntervalSince1970)
            let from = to - 3 * 86400
            let hr = (try? db.samples(from: from, to: to)) ?? []
            let workouts = (try? db.workouts(from: from, to: to)) ?? []
            health.export(days: recent, sleeps: sleeps, samples: hr, workouts: workouts)
        }
    }

    fileprivate func appendLog(_ line: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        log.append("\(f.string(from: Date()))  \(line)")
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}

// MARK: - StrapManagerDelegate

extension AppModel: StrapManagerDelegate {
    nonisolated func strapStateChanged(_ state: StrapState) {
        MainActor.assumeIsolated {
            let wasReady = self.strapState.isConnected
            self.strapState = state
            // The strap's own alarm is one-shot: re-arm it for the next morning on every new session.
            if state == .ready && !wasReady && self.alarmEnabled {
                self.strap.setAlarm(self.nextOccurrence(of: self.alarmTime))
            }
        }
    }

    nonisolated func strapIdentityChanged(_ identity: StrapIdentity) {
        MainActor.assumeIsolated { self.identity = identity }
    }

    nonisolated func strapBattery(percent: Double, charging: Bool?) {
        MainActor.assumeIsolated {
            self.battery = percent
            if let charging { self.charging = charging }
        }
    }

    nonisolated func strapLive(heartRate: Int, rr: [Int], at date: Date) {
        MainActor.assumeIsolated { self.handleLive(heartRate: heartRate, rr: rr, at: date) }
    }

    nonisolated func strapEvent(_ event: StrapEvent) {
        MainActor.assumeIsolated {
            switch event.kind {
            case .chargingOn: self.charging = true
            case .chargingOff: self.charging = false
            case .wristOff: self.appendLog("Pulsera fuera de la muñeca")
            case .wristOn: self.appendLog("Pulsera en la muñeca")
            case .doubleTap: self.appendLog("Doble toque en la pulsera")
            default: break
            }
        }
    }

    nonisolated func strapSyncFinished(newRecords: Int, firstTs: Int?, lastTs: Int?) {
        MainActor.assumeIsolated {
            self.lastSync = Date()
            try? self.db.set(Date(), for: "lastSync")
            self.refreshSampleCount()
            if newRecords > 0 || self.today == nil {
                let from = firstTs.map { DayKey.shift(DayKey.string(ts: $0), days: -1) }
                    ?? DayKey.shift(DayKey.string(Date()), days: -1)
                self.recompute(fromDay: from)
            }
        }
    }

    nonisolated func strapLog(_ line: String) {
        MainActor.assumeIsolated { self.appendLog(line) }
    }

    private func handleLive(heartRate: Int, rr: [Int], at date: Date) {
        guard heartRate > 25 && heartRate < 240 else { return }
        liveHR = heartRate
        livePoints.append(LivePoint(date: date, hr: heartRate))
        let cutoff = date.addingTimeInterval(-600)
        if let firstKeep = livePoints.firstIndex(where: { $0.date >= cutoff }), firstKeep > 0 {
            livePoints.removeFirst(firstKeep)
        }
        liveRR += rr.map(Double.init)
        if liveRR.count > 120 { liveRR.removeFirst(liveRR.count - 120) }
        let runs = HRV.clean([Array(liveRR.suffix(60))])
        liveRMSSD = HRV.rmssd(runs, minPairs: 20)
        try? db.insertLive(ts: Int(date.timeIntervalSince1970), hr: heartRate, rr: rr)

        if var w = liveWorkout {
            let dt = min(5, lastLiveAt.map { date.timeIntervalSince($0) } ?? 1)
            let model = heartRateModel
            w.load += Strain.weight(reserveFraction: model.reserveFraction(Double(heartRate))) * dt / 60
            w.kcal += max(Calories.bmrPerDay(profile) / 1440, Calories.keytelPerMinute(hr: Double(heartRate), profile)) * dt / 60
            w.maxHR = max(w.maxHR, heartRate)
            w.hrSum += Double(heartRate)
            w.hrCount += 1
            liveWorkout = w
        }
        lastLiveAt = date
    }
}
