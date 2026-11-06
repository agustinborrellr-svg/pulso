import Foundation
import WidgetKit
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntegrations

extension AppModel {
    // MARK: - Workout tracks & files

    /// The workout plus its heart rate (stored seconds, gaps filled with live readings) and laps.
    func workoutTrack(_ w: Workout, laps: [Int]? = nil) -> WorkoutTrack {
        let samples = (try? db.samples(from: w.start, to: w.end)) ?? []
        let live = (try? db.liveHR(from: w.start, to: w.end)) ?? []
        let lapList = laps ?? ((try? db.events(kind: EventKind.lap, since: w.start)) ?? []).filter { $0.ts < w.end }.map { $0.ts }
        return WorkoutTrack.from(workout: w, samples: samples, live: live.map { (ts: $0.ts, hr: $0.hr) }, laps: lapList)
    }

    /// FIT + TCX files of a workout for the share sheet (Garmin Connect, TrainingPeaks, Intervals.icu…).
    func exportWorkoutFiles(_ w: Workout) -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PulsoWorkout", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let track = workoutTrack(w)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        let base = "pulso_\(SportCatalog.named(w.sport).strava.first?.lowercased() ?? "workout")_\(f.string(from: Date(timeIntervalSince1970: TimeInterval(w.start))))"
        var urls: [URL] = []
        let fit = dir.appendingPathComponent(base + ".fit")
        if (try? Data(FITEncoder.encode(track)).write(to: fit)) != nil { urls.append(fit) }
        let tcx = dir.appendingPathComponent(base + ".tcx")
        if (try? TCXEncoder.encode(track).write(to: tcx, atomically: true, encoding: .utf8)) != nil { urls.append(tcx) }
        return urls
    }

    private func updateWorkout(start: Int, _ change: (inout Workout) -> Void) {
        guard var w = ((try? db.workouts(from: start, to: start + 1)) ?? []).first(where: { $0.start == start }) else { return }
        change(&w)
        _ = try? db.save(w)
    }

    // MARK: - After a workout

    /// Sends a finished workout to Apple Health and Strava according to the settings.
    func afterWorkoutSaved(_ w: Workout, laps: [Int]) {
        let track = workoutTrack(w, laps: laps)
        if profile.healthKitEnabled, settings.healthWorkouts, w.externalID("health") == nil {
            health.saveWorkout(w, heartRate: track.heartRate) { [weak self] uuid in
                guard let uuid else { return }
                self?.updateWorkout(start: w.start) { $0.setExternalID(uuid, for: "health") }
            }
        }
        if settings.stravaAutoUpload, strava.connected, w.externalID("strava") == nil {
            uploadToStrava(w)
        }
    }

    func uploadToStrava(_ w: Workout) {
        guard SportCatalog.named(w.sport).shareable else {
            importStatus = "«\(w.sport)» se queda solo en tu iPhone."
            return
        }
        guard strava.connected else {
            importStatus = "Conecta Strava en Más → Conexiones."
            return
        }
        importStatus = "Subiendo «\(w.sport)» a Strava…"
        let track = workoutTrack(w)
        let client = strava.client
        Task { @MainActor in
            do {
                let activity = try await client.uploadAndWait(track)
                updateWorkout(start: w.start) { $0.setExternalID(String(activity), for: "strava") }
                importStatus = "Subido a Strava ✓"
                NotificationService.shared.now("Subido a Strava", "\(w.sport) · \(Fmt.hm(w.durationMinutes))", sound: false)
            } catch {
                importStatus = "Strava: \(error)"
            }
        }
    }

    func saveWorkoutToHealth(_ w: Workout) {
        guard SportCatalog.named(w.sport).shareable else {
            importStatus = "«\(w.sport)» se queda solo en tu iPhone."
            return
        }
        let track = workoutTrack(w)
        health.requestAuthorization { [weak self] _ in
            self?.health.saveWorkout(w, heartRate: track.heartRate) { uuid in
                guard let uuid else {
                    self?.importStatus = "Apple Salud no aceptó el entreno"
                    return
                }
                self?.updateWorkout(start: w.start) { $0.setExternalID(uuid, for: "health") }
                self?.importStatus = "Guardado en Apple Salud ✓"
            }
        }
    }

    // MARK: - Imports (Health, Strava)

    /// Pulls workouts recorded by other apps (Apple Health and Strava). Every 3 h unless forced.
    func importExternalIfDue(force: Bool = false) {
        if !force, let last = lastImport, Date().timeIntervalSince(last) < 3 * 3600 { return }
        lastImport = Date()
        let since = (db.get(Date.self, for: "import.since") ?? Date().addingTimeInterval(-30 * 86400)).addingTimeInterval(-2 * 86400)
        var pending = 0
        func done() {
            pending -= 1
            if pending == 0 { try? db.set(Date(), for: "import.since") }
        }
        if profile.healthKitEnabled, settings.healthImport {
            pending += 1
            health.importWorkouts(since: since) { [weak self] list in
                self?.applyImports(list, service: "health")
                done()
            }
            importAppleWatchECGs(since: since)
        }
        if strava.connected, settings.stravaImport {
            pending += 1
            let client = strava.client
            Task { @MainActor in
                do {
                    let acts = try await client.activities(after: Int(since.timeIntervalSince1970))
                    // Pulso's own uploads are already linked; never import them back.
                    let list = acts.filter { !($0.external_id ?? "").hasPrefix("pulso-") }.compactMap { $0.asWorkout() }
                    applyImports(list, service: "strava")
                } catch {
                    importStatus = "Strava: \(error)"
                }
                done()
            }
        }
        if force && pending == 0 { importStatus = "Nada que importar: activa Apple Salud o conecta Strava." }
    }

    /// Merges imported workouts: links duplicates, replaces automatic bouts, inserts the rest.
    func applyImports(_ list: [Workout], service: String) {
        var inserted = 0, linked = 0
        var earliest: Int?
        for inc in list {
            let nearby = (try? db.workouts(from: inc.start - 3 * 3600, to: inc.end + 3 * 3600)) ?? []
            switch WorkoutMerge.decide(inc, service: service, existing: nearby) {
            case .duplicate:
                continue
            case .insert:
                _ = try? db.save(inc)
                inserted += 1
            case .link(let i):
                _ = try? db.save(WorkoutMerge.link(inc, into: nearby[i], service: service))
                linked += 1
            case .replaceAuto(let i):
                if let id = nearby[i].id { try? db.deleteWorkout(id: id) }
                _ = try? db.save(inc)
                inserted += 1
            }
            earliest = min(earliest ?? inc.start, inc.start)
        }
        let name = service == "strava" ? "Strava" : "Apple Salud"
        if inserted + linked > 0 {
            importStatus = "\(name): \(inserted) entreno\(inserted == 1 ? "" : "s") nuevo\(inserted == 1 ? "" : "s"), \(linked) enlazado\(linked == 1 ? "" : "s")"
            if let e = earliest { recompute(fromDay: DayKey.shift(DayKey.string(ts: e), days: -1)) }
        } else if importStatus == nil || importStatus?.hasPrefix(name) == true {
            importStatus = "\(name): todo al día"
        }
    }

    // MARK: - Database backup / restore

    static var restorePath: String? {
        (try? PulsoDatabase.defaultPath()).map { $0 + ".restore" }
    }

    /// Copies a pending restore over the live database. Called before the database is opened.
    static func applyPendingRestore() {
        guard let live = try? PulsoDatabase.defaultPath(), let pending = restorePath,
              FileManager.default.fileExists(atPath: pending) else { return }
        let fm = FileManager.default
        // The live database is set aside under its own name, never dropped here: its per-second data is merged
        // into the restored one (`resumeRestoreMerge`), which deletes it only once that worked. Its -wal goes
        // with it, as it may hold the last writes; without both, nothing is restored.
        let aside = live + ".before-restore-\(Int(Date().timeIntervalSince1970))"
        var setAside = false
        if fm.fileExists(atPath: live) {
            guard (try? fm.moveItem(atPath: live, toPath: aside)) != nil else { return }
            if fm.fileExists(atPath: live + "-wal"), (try? fm.moveItem(atPath: live + "-wal", toPath: aside + "-wal")) == nil {
                try? fm.moveItem(atPath: aside, toPath: live)
                return
            }
            try? fm.removeItem(atPath: live + "-shm")
            setAside = true
        } else if fm.fileExists(atPath: live + "-wal") {
            // Killed between moving the database and its -wal last time: that -wal belongs with the newest set-aside
            // database (never applied to the restored one, never deleted).
            let home = setAsideDatabases().last { !fm.fileExists(atPath: $0 + "-wal") } ?? live + ".orphan-\(Int(Date().timeIntervalSince1970))"
            guard (try? fm.moveItem(atPath: live + "-wal", toPath: home + "-wal")) != nil else { return }
            try? fm.removeItem(atPath: live + "-shm")
        }
        do {
            try fm.moveItem(atPath: pending, toPath: live)
        } catch {
            if setAside {
                try? fm.moveItem(atPath: aside, toPath: live)
                try? fm.moveItem(atPath: aside + "-wal", toPath: live + "-wal")
            }
        }
    }

    /// A compact copy of everything (to keep in Files / iCloud Drive).
    func makeBackup() -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pulso-copia-\(f.string(from: Date())).sqlite")
        do {
            try db.backup(to: url.path)
            return url
        } catch {
            errorMessage = "No se pudo crear la copia: \(error)"
            return nil
        }
    }

    /// Validates a backup and stages it; it replaces the data the next time Pulso starts.
    func stageRestore(from url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("restore-check.sqlite")
        try? FileManager.default.removeItem(at: tmp)
        guard (try? FileManager.default.copyItem(at: url, to: tmp)) != nil, PulsoDatabase.isValidBackup(path: tmp.path),
              let dest = Self.restorePath else {
            errorMessage = "Ese archivo no es una copia de Pulso válida."
            return false
        }
        // A month archive only holds per-second data: restoring it would leave every summary empty. It is merged
        // on its own into whatever copy is restored.
        if PulsoDatabase.monthArchiveInfo(path: tmp.path) != nil {
            try? FileManager.default.removeItem(at: tmp)
            errorMessage = "Ese archivo solo guarda los datos por segundo de un mes y Pulso lo usa por su cuenta al restaurar. Elige una copia diaria, semanal o «antes de»."
            return false
        }
        // A copy of the current data first (everything but the archived months' seconds, which come back on
        // their own); without it nothing is staged.
        guard safetyBackup(reason: "restaurar", content: .month) else {
            try? FileManager.default.removeItem(at: tmp)
            errorMessage = "No se pudo hacer la copia de seguridad previa (¿falta espacio?). No se ha preparado la restauración: tus datos siguen igual."
            return false
        }
        try? FileManager.default.removeItem(atPath: dest)
        do {
            try FileManager.default.moveItem(at: tmp, to: URL(fileURLWithPath: dest))
            errorMessage = "Copia lista. Cierra Pulso del todo y vuelve a abrirla para restaurarla. Los datos por segundo que no estén en la copia se recuperan solos."
            return true
        } catch {
            errorMessage = "No se pudo preparar la restauración: \(error)"
            return false
        }
    }

    // MARK: - Widgets

    func updateWidget() {
        let d = today ?? days.last
        var snap = WidgetSnapshot(updated: Date(), day: d?.day ?? "", recovery: d?.recovery, strain: d?.strain, strainTarget: nil,
                                  sleepPerformance: d?.sleepPerformance, sleepMinutes: d?.sleepMinutes, hrv: d?.hrv, rhr: d?.rhr,
                                  battery: battery, nextAlarm: nextAlarm?.latest, headline: nil)
        if let d, d.recovery != nil {
            let advice = coachAdvice(for: d)
            snap.strainTarget = "\(Int(advice.strainTarget.lowerBound))–\(Int(advice.strainTarget.upperBound))"
            snap.headline = advice.headline
        }
        if var old = WidgetSnapshot.load() {
            old.updated = snap.updated
            if old == snap { return }
        }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
