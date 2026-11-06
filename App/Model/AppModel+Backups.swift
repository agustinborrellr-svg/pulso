import Foundation
import PulsoStore

/// Automatic copies so nothing is ever lost (see `BackupPolicy`): a light copy every day, an archive per closed
/// month with its per-second data, a weekly copy with the current month, and a safety copy before anything that
/// replaces or deletes data. They live in Documents/Copias de seguridad, visible in the Files app
/// («En mi iPhone → Pulso»). Light copies also go into the iPhone's own iCloud or computer backup; the big
/// files don't (the live database, with every second, already does).
extension AppModel {
    static var backupsFolder: URL? {
        guard let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        let dir = docs.appendingPathComponent(BackupPolicy.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Runs at launch and when the app comes back; does nothing if the copies are recent.
    func autoBackupIfDue() {
        guard !AppMode.screenshots, let dir = Self.backupsFolder else { return }
        let db = self.db
        analysisQueue.async {
            let fm = FileManager.default
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            let now = Date()
            let plan = BackupPolicy.plan(existing: names, now: now)
            // Leftovers of a copy interrupted by a crash (an hour old, so never one being written right now).
            for name in names where BackupPolicy.isUnfinished(name) {
                let url = dir.appendingPathComponent(name)
                let modified = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? now
                if now.timeIntervalSince(modified) > 3600 { try? fm.removeItem(at: url) }
            }
            guard (try? db.holdsData()) == true else { return }
            let calendar = db.archiveCalendar()
            // Each copy is written aside, checked and only then named (see `PulsoDatabase.writeCopy`). Older
            // copies of a kind are rotated out only once the new one of that kind exists.
            var rotate: Set<BackupPolicy.Kind> = [.safety]
            if !plan.makeDaily || (try? db.backupLight(to: dir.appendingPathComponent(BackupPolicy.fileName(.daily, at: now)).path)) != nil {
                rotate.insert(.daily)
            }
            let weekly = dir.appendingPathComponent(BackupPolicy.fileName(.weekly, at: now)).path
            if !plan.makeWeekly || (try? db.backupRecent(to: weekly, since: BackupPolicy.monthStart(now, calendar: calendar))) != nil {
                rotate.insert(.weekly)
            }
            for name in plan.delete where BackupPolicy.parse(name).map({ rotate.contains($0.kind) }) == true {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
            // Month archives: at most one per pass (a first run with a long history catches up a month each
            // time the app opens); once a day, also rewrite one whose month got late seconds. A failure (no
            // space) leaves nothing behind and is retried next time.
            _ = try? db.archiveNextMonth(in: dir.path, now: now, calendar: calendar, refresh: plan.makeDaily)
            // The retention limit (if any) never deletes seconds whose month has no archive yet.
            _ = try? db.updateArchiveCoverage(in: dir.path, now: now, calendar: calendar)
            Self.excludeBigCopiesFromDeviceBackup(in: dir)
        }
    }

    /// A copy taken synchronously right before data is replaced or deleted: light before an import (it never
    /// touches the per-second data), light + current month before a restore (older months are archived and
    /// every second is merged back afterwards), full before erasing everything. It is written aside, checked
    /// with `quick_check` and only then named, and older safety copies are rotated only after it exists.
    /// Returns false when the copy could not be written: callers that delete data must then stop.
    @discardableResult
    func safetyBackup(reason: String, content: BackupPolicy.Content) -> Bool {
        guard !AppMode.screenshots else { return true }
        guard let dir = Self.backupsFolder else { return false }
        // A database with nothing but settings has no seconds to copy: a light copy holds all of it.
        var content = content
        if content != .light, (try? db.holdsData()) == false { content = .light }
        let now = Date()
        let path = dir.appendingPathComponent(BackupPolicy.fileName(.safety, reason: reason, content: content, at: now)).path
        do {
            switch content {
            case .light: try db.backupLight(to: path)
            case .month: try db.backupRecent(to: path, since: BackupPolicy.monthStart(now, calendar: db.archiveCalendar()))
            case .full: try db.backup(to: path)
            }
        } catch {
            return false
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in BackupPolicy.plan(existing: names, now: now).delete where BackupPolicy.parse(name)?.kind == .safety {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        Self.excludeBigCopiesFromDeviceBackup(in: dir)
        return true
    }

    /// Archives, weekly and full copies stay out of the iPhone's iCloud/computer backup (they would make it
    /// gigabytes bigger for data the live database already carries there). Copies from older versions too.
    static func excludeBigCopiesFromDeviceBackup(in dir: URL) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
            guard let copy = BackupPolicy.parse(name), BackupPolicy.excludedFromDeviceBackup(copy) else { continue }
            var url = dir.appendingPathComponent(name)
            if (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
    }

    // MARK: - Restore: every second comes back

    private static let restoreMergeDayKey = "restore.mergeFromDay"
    private static let restoreMergeEarliestKey = "restore.mergeEarliest"

    /// Databases a restore set aside (`applyPendingRestore`), oldest first.
    static func setAsideDatabases() -> [String] {
        guard let live = try? PulsoDatabase.defaultPath() else { return [] }
        let url = URL(fileURLWithPath: live)
        let dir = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".before-restore"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { name in name.hasPrefix(prefix) && !["-wal", "-shm", "-journal"].contains { name.hasSuffix($0) } }
            .sorted()
            .map { dir.appendingPathComponent($0).path }
    }

    /// After a restore, the per-second data the restored copy lacks is merged back from the database it
    /// replaced and from every month archive (the copy's own values win; raw seconds are facts, never undone).
    /// The replaced database is deleted only once its merge worked; an interrupted merge resumes at the next
    /// launch. Days from the copy's last one on are then recomputed. Called at launch before any recompute,
    /// on the analysis queue so the UI never waits. Returns true if a merge was queued.
    @discardableResult
    func resumeRestoreMerge() -> Bool {
        let asides = Self.setAsideDatabases()
        let db = self.db
        guard !AppMode.screenshots, !asides.isEmpty || db.get(String.self, for: Self.restoreMergeDayKey) != nil else { return false }
        if db.get(String.self, for: Self.restoreMergeDayKey) == nil {
            try? db.set((try? db.latestDay()) ?? "", for: Self.restoreMergeDayKey)
        }
        let dir = Self.backupsFolder
        analysisQueue.async {
            var sources = asides.map { (path: $0, isAside: true) }
            if let dir, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                sources += names.filter { BackupPolicy.parse($0)?.kind == .archive }.sorted()
                    .map { (path: dir.appendingPathComponent($0).path, isAside: false) }
            }
            var complete = true
            for source in sources {
                do {
                    if let changed = try db.mergeSeconds(from: source.path) {
                        let earliest = min(db.get(Int.self, for: Self.restoreMergeEarliestKey) ?? changed, changed)
                        try? db.set(earliest, for: Self.restoreMergeEarliestKey)
                    }
                    if source.isAside {
                        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: source.path + suffix) }
                    }
                } catch {
                    complete = false // kept and retried at the next launch; nothing is deleted meanwhile
                }
            }
            guard complete else { return }
            let copyLastDay = db.get(String.self, for: Self.restoreMergeDayKey) ?? ""
            let earliest = db.get(Int.self, for: Self.restoreMergeEarliestKey)
            for key in [Self.restoreMergeDayKey, Self.restoreMergeEarliestKey] {
                try? db.sql.run("DELETE FROM kv WHERE key = ?", [.text(key)])
            }
            guard let earliest else { return }
            // Days the restored copy already has keep its numbers; from its last day on they are recomputed.
            var from = DayKey.shift(DayKey.string(ts: earliest), days: -1)
            if !copyLastDay.isEmpty { from = max(from, DayKey.shift(copyLastDay, days: -1)) }
            Task { @MainActor in self.recompute(fromDay: from) }
        }
        return true
    }

    /// Size of the database and of the automatic copies, for Más → Datos.
    var storageSummary: String {
        let dbBytes = (try? PulsoDatabase.defaultPath()).map(PulsoDatabase.diskSize) ?? 0
        var copies = 0, months = 0
        var copiesBytes: Int64 = 0, monthsBytes: Int64 = 0
        if let dir = Self.backupsFolder, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in names {
                guard let copy = BackupPolicy.parse(name) else { continue }
                let bytes = PulsoDatabase.diskSize(path: dir.appendingPathComponent(name).path)
                if copy.kind == .archive {
                    months += 1
                    monthsBytes += bytes
                } else {
                    copies += 1
                    copiesBytes += bytes
                }
            }
        }
        let f = ByteCountFormatter()
        f.countStyle = .file
        var text = "Datos: \(f.string(fromByteCount: dbBytes)) · \(copies) copias automáticas (\(f.string(fromByteCount: copiesBytes)))"
        if months > 0 {
            text += " · \(months) \(months == 1 ? "mes archivado" : "meses archivados") (\(f.string(fromByteCount: monthsBytes)))"
        }
        return text
    }

    /// Profiles saved before «Siempre» became the default kept only 120 days of per-second data: move them
    /// to «Siempre» once (a later explicit choice is respected).
    func migrateRetentionDefault() {
        let key = "migration.retentionForever"
        guard db.get(Bool.self, for: key) != true else { return }
        if profile.rawRetentionDays == 120 {
            var p = profile
            p.rawRetentionDays = 0
            saveProfile(p)
        }
        try? db.set(true, for: key)
    }
}
