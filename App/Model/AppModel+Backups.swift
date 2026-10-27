import Foundation
import PulsoStore

/// Automatic copies so nothing is ever lost: daily light, weekly full and a safety copy before anything that
/// replaces or deletes data. They live in Documents/Copias de seguridad, visible in the Files app
/// («En mi iPhone → Pulso») and included in the iPhone's own iCloud or computer backup.
extension AppModel {
    static var backupsFolder: URL? {
        guard let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        let dir = docs.appendingPathComponent(BackupPolicy.folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Runs at launch and when the app comes back; does nothing if the copies are recent.
    func autoBackupIfDue() {
        guard !AppMode.screenshots, !demoActive, let dir = Self.backupsFolder else { return }
        let db = self.db
        analysisQueue.async {
            let fm = FileManager.default
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            let now = Date()
            let plan = BackupPolicy.plan(existing: names, now: now)
            guard (try? db.hasSamples()) == true || (try? db.allDays().isEmpty) == false else { return }
            if plan.makeDaily { try? db.backupLight(to: dir.appendingPathComponent(BackupPolicy.fileName(.daily, at: now)).path) }
            if plan.makeWeekly { try? db.backup(to: dir.appendingPathComponent(BackupPolicy.fileName(.weekly, at: now)).path) }
            for name in plan.delete { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
        }
    }

    /// A full copy taken synchronously right before data is replaced or deleted.
    func safetyBackup(reason: String) {
        guard !AppMode.screenshots, let dir = Self.backupsFolder else { return }
        try? db.backup(to: dir.appendingPathComponent(BackupPolicy.fileName(.safety, reason: reason, at: Date())).path)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in BackupPolicy.plan(existing: names, now: Date()).delete where BackupPolicy.parse(name)?.kind == .safety {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Size of the database and of the automatic copies, for Más → Datos.
    var storageSummary: String {
        let dbBytes = (try? PulsoDatabase.defaultPath()).map(PulsoDatabase.diskSize) ?? 0
        var copies = 0
        var copiesBytes: Int64 = 0
        if let dir = Self.backupsFolder, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in names where BackupPolicy.parse(name) != nil {
                copies += 1
                copiesBytes += PulsoDatabase.diskSize(path: dir.appendingPathComponent(name).path)
            }
        }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "Datos: \(f.string(fromByteCount: dbBytes)) · \(copies) copias automáticas (\(f.string(fromByteCount: copiesBytes)))"
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
