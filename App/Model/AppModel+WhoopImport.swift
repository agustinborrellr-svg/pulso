import Foundation
import PulsoStore
import PulsoAnalytics

/// What one WHOOP import did, shown in the import screen.
struct WhoopImportSummary {
    var files: [WhoopExport.FileReport] = []
    var stored = WhoopExport.Stored()
    var error: String?

    var nothingDone: Bool { stored.days + stored.workoutsNew + stored.workoutsLinked + stored.journal == 0 }
}

extension AppModel {
    /// Imports any subset of a WHOOP export's CSV files (see `WhoopExport.store`: importing the same
    /// files again changes nothing).
    func importWhoop(_ files: [WhoopExport.File]) -> WhoopImportSummary {
        let bundle = WhoopExport.read(files)
        safetyBackup(reason: "importar")
        var s = WhoopImportSummary(files: bundle.files)
        do {
            s.stored = try WhoopExport.store(bundle, in: db)
        } catch {
            s.error = "No se pudo guardar: \(error.localizedDescription)"
        }
        if s.stored.days > 0 {
            // Baselines of the recent days change with the imported history.
            recompute(fromDay: DayKey.shift(DayKey.string(Date()), days: -30))
        } else {
            reload()
        }
        return s
    }
}
