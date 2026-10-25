import Foundation
import SwiftUI
import Combine
import UserNotifications
import WhoopProtocol
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntegrations
import PulsoECG
import PulsoIntelligence

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
    /// Lap timestamps (unix seconds).
    var laps: [Int] = []
    /// Interval plan being followed, if any.
    var planID: String?
}

/// App-wide state. All published properties live on the main actor; heavy analysis runs on a
/// background queue and publishes the results back.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // Strap
    @Published var strapState: StrapState = .noStrap
    @Published var identity = StrapIdentity()
    @Published var battery: Double?
    @Published var charging: Bool?
    @Published var lastSync: Date?
    @Published var log: [String] = []
    /// Since when the strap has been off the wrist (nil = on the wrist / unknown).
    @Published var offWristSince: Date?

    // Data
    @Published var days: [DaySummary] = []
    @Published var selectedDay: String = DayKey.string(Date())
    @Published var profile: Profile
    @Published var analyzing = false
    @Published var analysisProgress: Double = 0
    @Published var insights: [Insight] = []
    @Published var errorMessage: String?
    @Published var rawSampleCount = 0
    @Published var trainingLoad: [TrainingLoad.Point] = []

    // Live
    @Published var liveHR: Int?
    @Published var liveRMSSD: Double?
    @Published var livePoints: [LivePoint] = []
    @Published var liveWorkout: LiveWorkout?
    var liveRR: [Double] = []
    var lastLiveAt: Date?

    // Features
    @Published var settings: FeatureSettings
    @Published var alarms: [AlarmConfig]
    @Published var alertPrefs: AlertPreferences
    /// Human-readable state of tonight's alarm ("Vigilando sueño ligero…", "Sonando", …).
    @Published var alarmStatus: String?
    @Published var alarmRinging = false
    @Published var intervalStatus: (step: String, remaining: Int, next: String?)?
    @Published var broadcastStatus = "Apagado"
    @Published var ecgRecordings: [ECGRecording] = []
    @Published var ecgSession: ECGSessionBuilder?
    @Published var ecgProgress: Double = 0
    @Published var importStatus: String?
    @Published var breathingGuideActive = false
    /// Derived metrics, patterns and forecast (recomputed after each analysis).
    @Published var intelligence: IntelligenceReport?
    /// Straps found by the last scan (nothing connects until one is chosen).
    @Published var discoveredStraps: [DiscoveredStrap] = []

    let db: PulsoDatabase
    let strap = StrapManager()
    let health = HealthExporter()
    let strava = StravaService()
    let broadcaster = HRBroadcaster()
    let alarmBackup = AlarmBackup()
    let voice = VoiceCoach()
    let analysisQueue = DispatchQueue(label: "pulso.analysis", qos: .utility)
    lazy var engine = DayEngine(db: db)

    // Runtime (not published)
    var wakeSession: WakeSession?
    var intervalRunner: IntervalRunner?
    var hapticQueue: [(at: Date, loops: UInt8)] = []
    var ticker: Timer?
    var mgDecoder = MGECGDecoder()
    var lastAlertEvaluation: Date?
    var lastImport: Date?
    var lastActivityUpdate: Date?
    var ecgSimulatedSamples: [Float]?
    var ecgSimulatedStart: Date?
    @Published var lastFinishedECG: Int64?

    init() {
        AppModel.applyPendingRestore()
        let path = (try? PulsoDatabase.defaultPath()) ?? NSTemporaryDirectory() + "pulso.sqlite"
        do {
            db = try PulsoDatabase(path: path)
        } catch {
            // Last resort: an in-temp database so the app still opens.
            db = try! PulsoDatabase(path: NSTemporaryDirectory() + "pulso-fallback.sqlite")
        }
        profile = db.profile
        settings = db.get(FeatureSettings.self, for: "settings") ?? FeatureSettings()
        alarms = db.get([AlarmConfig].self, for: "alarms") ?? []
        alertPrefs = db.get(AlertPreferences.self, for: "alertPrefs") ?? AlertPreferences()
        lastSync = db.get(Date.self, for: "lastSync")
        strap.delegate = self
        let database = db
        strap.persist = { samples in try database.insert(samples) }
        migrateLegacyAlarm()
        reload()
        startTicker()
        NotificationService.shared.setup()
        NotificationService.shared.onAction = { [weak self] action, category, id in
            self?.handleNotificationAction(action, category: category, id: id)
        }
        broadcaster.onState = { [weak self] s in self?.broadcastStatus = s }
        if settings.hrBroadcast {
            broadcaster.start()
            setLive(true, client: "broadcast")
        }
        ecgRecordings = (try? db.ecgRecordings(withSamples: false)) ?? []
        refreshIntelligence()
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

    /// Illness / vital-signs check of the selected day against the days before it.
    func healthAssessment(for day: DaySummary) -> HealthMonitor.Assessment {
        HealthMonitor.assess(day, history: days.filter { $0.day < day.day })
    }

    /// Strain target and advice for the selected day.
    func coachAdvice(for day: DaySummary) -> DailyCoach.Advice {
        let load = trainingLoad.filter { $0.day <= day.day }
        return DailyCoach.advice(recovery: day.recovery, load: load, health: healthAssessment(for: day),
                                 sleepDebtMinutes: day.sleepDebtMinutes)
    }

    /// Tonight's bedtime plan for the next wake time (alarm, else the usual wake time).
    var tonightPlan: SleepPlanner.Plan? {
        guard let wake = nextWakeDate else { return nil }
        let need = SleepPlanner.tonightNeed(profile: profile, today: today, recent: days)
        return SleepPlanner.plan(wake: wake, needMinutes: need, recent: days)
    }

    var nextWakeDate: Date? {
        if let a = AlarmPlanner.next(alarms, after: Date()) { return a.latest }
        guard let m = SleepPlanner.typicalWakeMinutes(days) else { return nil }
        return Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: Int(m) / 60, minute: Int(m) % 60),
                                         matchingPolicy: .nextTime)
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
            trainingLoad = TrainingLoad.series(days, through: DayKey.string(Date()))
            if rawSampleCount == 0, (try? db.hasSamples()) == true { rawSampleCount = 1 }
            refreshSampleCount()
            updateWidget()
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

    /// Markers (double tap) and laps of a day.
    func markers(for day: DaySummary) -> [StoredEvent] {
        guard let a = day.cycleStart else { return [] }
        let b = day.cycleEnd ?? Int(Date().timeIntervalSince1970)
        let m = (try? db.events(kind: EventKind.marker, since: a)) ?? []
        let l = (try? db.events(kind: EventKind.lap, since: a)) ?? []
        return (m + l).filter { $0.ts < b }.sorted { $0.ts < $1.ts }
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
                self.refreshIntelligence()
                self.exportToHealthIfEnabled()
                self.evaluateAlerts(force: true)
                if let next = self.pendingRecompute {
                    self.pendingRecompute = nil
                    self.recompute(fromDay: next)
                }
            }
        }
    }

    // MARK: - Strap actions

    func connect() { strap.connect() }
    /// Lists nearby straps. Never connects by itself.
    func scanForStraps() {
        discoveredStraps = []
        strap.scan()
    }

    func stopScan() { strap.stopScan() }

    /// Pairs with the strap the user picked.
    func chooseStrap(_ s: DiscoveredStrap) {
        strap.choose(s.id)
        discoveredStraps = []
    }
    func forgetStrap() { strap.forget() }
    func syncNow() { strap.sync(force: true) }
    func buzz() { strap.buzz() }

    /// Screens that want the live stream (live view, workout, alarm window, breathing, broadcast).
    private var liveClients = Set<String>()

    func setLive(_ on: Bool, client: String = "view") {
        if on { liveClients.insert(client) } else { liveClients.remove(client) }
        let wanted = !liveClients.isEmpty || liveWorkout != nil || settings.hrBroadcast
        strap.setLive(wanted)
        if !wanted {
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
        refreshAlarmSchedule()
        evaluateAlerts(force: true)
        importExternalIfDue()
    }

    func appEnteredBackground() {
        refreshAlarmSchedule()
        updateNightGuard()
        updateWidget()
    }

    // MARK: - Ticker

    /// 1 Hz in the foreground. In the background the same work is driven by Bluetooth callbacks.
    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Advances the alarm, the interval plan and the haptic queue. Safe to call often.
    func tick() {
        let now = Date()
        alarmTick(now: now)
        intervalTick(now: now)
        drainHaptics(now: now)
        ecgTick(now: now)
    }

    // MARK: - Live workouts

    func startWorkout(sport: String, plan: IntervalPlan? = nil) {
        guard liveWorkout == nil else { return }
        var w = LiveWorkout(start: Date(), sport: sport)
        w.planID = plan?.id
        liveWorkout = w
        if let plan { intervalRunner = IntervalRunner(plan: plan, start: Int(w.start.timeIntervalSince1970)) }
        setLive(true, client: "workout")
        startWorkoutActivity(sport: sport, start: w.start)
    }

    func stopWorkout(save: Bool) {
        guard let w = liveWorkout else { return }
        liveWorkout = nil
        intervalRunner = nil
        intervalStatus = nil
        voice.finish()
        setLive(false, client: "workout")
        endWorkoutActivity()
        guard save, Date().timeIntervalSince(w.start) >= 60 else { return }
        var workout = Workout(start: Int(w.start.timeIntervalSince1970), end: Int(Date().timeIntervalSince1970),
                              sport: w.sport, source: .live,
                              strain: Strain.score(load: w.load),
                              avgHR: w.hrCount > 0 ? w.hrSum / Double(w.hrCount) : 0,
                              maxHR: Double(w.maxHR), kcal: w.kcal)
        if let p = w.planID, let plan = IntervalPlan.presets.first(where: { $0.id == p }) { workout.notes = plan.name }
        do {
            workout.id = try db.save(workout)
            for lap in w.laps { try? db.insertEvent(StoredEvent(ts: lap, kind: EventKind.lap, value: nil)) }
            afterWorkoutSaved(workout, laps: w.laps)
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

    // MARK: - Profile & settings

    func saveProfile(_ p: Profile) {
        let needsRecompute = p.birthYear != profile.birthYear || p.sex != profile.sex || p.weightKg != profile.weightKg
            || p.heightCm != profile.heightCm || p.maxHROverride != profile.maxHROverride || p.sleepNeedHours != profile.sleepNeedHours
        profile = p
        db.profile = p
        if needsRecompute { recompute(fromDay: DayKey.shift(DayKey.string(Date()), days: -30)) }
        if p.healthKitEnabled { health.requestAuthorization { _ in } }
    }

    func saveSettings(_ s: FeatureSettings) {
        let broadcastChanged = s.hrBroadcast != settings.hrBroadcast
        settings = s
        try? db.set(s, for: "settings")
        if broadcastChanged {
            if s.hrBroadcast {
                broadcaster.start()
            } else {
                broadcaster.stop()
            }
            setLive(s.hrBroadcast, client: "broadcast")
        }
    }

    func saveAlertPrefs(_ p: AlertPreferences) {
        alertPrefs = p
        try? db.set(p, for: "alertPrefs")
        NotificationService.shared.requestAuthorization()
        evaluateAlerts(force: true)
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
        alarms = []
        settings = FeatureSettings()
        alertPrefs = AlertPreferences()
        ecgRecordings = []
        refreshAlarmSchedule()
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

    func appendLog(_ line: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        log.append("\(f.string(from: Date()))  \(line)")
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}

/// Kinds used in the `events` table for app-generated events.
enum EventKind {
    static let marker = 1000
    static let lap = 1001
    static let bedtime = 1002
}

// MARK: - StrapManagerDelegate

extension AppModel: StrapManagerDelegate {
    nonisolated func strapStateChanged(_ state: StrapState) {
        MainActor.assumeIsolated {
            let wasReady = self.strapState.isConnected
            self.strapState = state
            if state == .ready && !wasReady {
                // The strap's own alarm is one-shot: re-arm it on every new session, once the clock
                // has been set (a few seconds after "ready").
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.armStrapAlarm() }
                self.updateNightGuard()
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
            self.updateWidget()
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
            case .wristOff:
                self.appendLog("Pulsera fuera de la muñeca")
                self.offWristSince = Date()
                self.evaluateAlerts(force: true)
            case .wristOn:
                self.appendLog("Pulsera en la muñeca")
                self.offWristSince = nil
                NotificationService.shared.cancelPending(prefix: "offwrist.")
            case .doubleTap:
                self.appendLog("Doble toque en la pulsera")
                self.handleDoubleTap()
            case .strapAlarmExecuted:
                self.appendLog("La pulsera ha hecho sonar su alarma")
            default: break
            }
            self.tick()
        }
    }

    nonisolated func strapSyncFinished(newRecords: Int, firstTs: Int?, lastTs: Int?) {
        MainActor.assumeIsolated {
            self.lastSync = Date()
            try? self.db.set(Date(), for: "lastSync")
            NotificationService.shared.cancelPending(prefix: "stale.")
            self.refreshSampleCount()
            self.alarmSyncFinished()
            if newRecords > 0 || self.today == nil {
                let from = firstTs.map { DayKey.shift(DayKey.string(ts: $0), days: -1) }
                    ?? DayKey.shift(DayKey.string(Date()), days: -1)
                self.recompute(fromDay: from)
            } else {
                self.evaluateAlerts(force: false)
            }
        }
    }

    nonisolated func strapLog(_ line: String) {
        MainActor.assumeIsolated { self.appendLog(line) }
    }

    nonisolated func strapDiscovered(_ straps: [DiscoveredStrap]) {
        MainActor.assumeIsolated { self.discoveredStraps = straps }
    }

    nonisolated func strapUnhandledFrame(_ frame: Frame) {
        DispatchQueue.main.async { self.handleECGFrame(frame) }
    }

    func handleLive(heartRate: Int, rr: [Int], at date: Date) {
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
        broadcaster.send(heartRate: heartRate, rr: rr)

        if var w = liveWorkout {
            let dt = min(5, lastLiveAt.map { date.timeIntervalSince($0) } ?? 1)
            let model = heartRateModel
            w.load += Strain.weight(reserveFraction: model.reserveFraction(Double(heartRate))) * dt / 60
            w.kcal += max(Calories.bmrPerDay(profile) / 1440, Calories.keytelPerMinute(hr: Double(heartRate), profile)) * dt / 60
            w.maxHR = max(w.maxHR, heartRate)
            w.hrSum += Double(heartRate)
            w.hrCount += 1
            liveWorkout = w
            updateWorkoutActivity()
        }
        lastLiveAt = date
        // Live notifications arrive ~1 Hz and keep the app running in the background: drive timers from them.
        tick()
    }
}
