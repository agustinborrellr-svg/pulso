import Foundation
import PulsoStore
import PulsoAnalytics
import PulsoIntelligence

extension AppModel {
    /// Recomputes the Inteligencia report off the main thread (after each analysis).
    func refreshIntelligence() {
        let db = self.db
        let hr = heartRateModel
        let measuredMax = profile.maxHROverride != nil
        let profile = self.profile
        analysisQueue.async {
            let now = Date()
            let nowTs = Int(now.timeIntervalSince1970)
            let from = nowTs - 150 * 86400
            let today = DayKey.string(now)
            // The strap's days plus the WHOOP history: without a strap yet, the import alone feeds the analysis.
            let measured = (try? db.days(from: DayKey.shift(today, days: -150), to: today)) ?? []
            let imported = ((try? db.importedDays()) ?? []).filter { $0.day >= DayKey.shift(today, days: -150) }
            let days = HistoryMerge.days(measured: measured, imported: imported, profile: profile)
            let sleeps = ((try? db.sleeps(from: from, to: nowTs + 3600)) ?? [])
                + HistoryMerge.sleeps(from: imported, excluding: Set(measured.map(\.day)))
            let workouts = (try? db.workouts(from: from, to: nowTs + 3600)) ?? []
            let journal = (try? db.allJournal()) ?? []
            var drops: [(day: String, drop: Double)] = []
            for w in workouts.suffix(25) {
                let key = "hrr.v1.\(w.start)"
                var drop = db.get(Double.self, for: key)
                if drop == nil, nowTs - w.end > 1800 {
                    let samples = (try? db.samples(from: w.start - 60, to: w.end + 1800)) ?? []
                    let r = WorkoutAnalysis.analyze(workout: w, samples: samples, restingHR: hr.restingHR, maxHR: hr.maxHR,
                                                    maxHRMeasured: measuredMax)
                    drop = r.recovery?.drop60 ?? -1
                    try? db.set(drop!, for: key)
                }
                if let d = drop, d > 0 { drops.append((DayKey.string(ts: w.start), d)) }
            }
            let report = Intelligence.report(days: days, sleeps: sleeps, workouts: workouts, journal: journal, hrrDrops: drops, now: now)
            Task { @MainActor in self.intelligence = report }
        }
    }

    /// Full cardiac analysis of one workout (samples up to 30 min after it).
    func workoutAnalysis(_ w: Workout) -> WorkoutAnalysis.Result {
        let samples = (try? db.samples(from: w.start - 60, to: w.end + 1800)) ?? []
        let hr = heartRateModel
        return WorkoutAnalysis.analyze(workout: w, samples: samples, restingHR: hr.restingHR, maxHR: hr.maxHR,
                                       maxHRMeasured: profile.maxHROverride != nil)
    }

    /// The load-response event of a workout's day, if it counted as a hard day.
    func loadEvent(for w: Workout) -> LoadResponse.Event? {
        guard let report = intelligence else { return nil }
        let day = days.first { d in (d.cycleStart ?? .max) <= w.start && w.start < (d.cycleEnd ?? .min) }?.day
        return report.events.first { $0.day == day }
    }

    /// CSV with every metric of the current report (for the share sheet).
    func exportIntelligence() -> URL? {
        guard let r = intelligence else { return nil }
        var lines = ["seccion,metrica,valor,unidad,ic_inferior,ic_superior,confianza,muestras,estado,version,formula,resumen"]
        func esc(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        for s in r.sections {
            for m in s.metrics {
                let status: String
                if case .insufficient(let why) = m.status { status = "insuficiente: \(why)" } else { status = "ok" }
                lines.append([esc(s.title), esc(m.name), m.value.map { String(format: "%.2f", $0) } ?? "", esc(m.unit),
                              m.interval.map { String(format: "%.2f", $0.lowerBound) } ?? "", m.interval.map { String(format: "%.2f", $0.upperBound) } ?? "",
                              m.confidence.label, String(m.sampleSize), esc(status), m.version, esc(m.formula), esc(m.summary)].joined(separator: ","))
            }
        }
        lines.append("")
        lines.append("dia,distancia_mahalanobis,desviacion_desfavorable,coherencia,deuda_fisiologica,noches_base")
        for p in r.deviation {
            lines.append(String(format: "%@,%.3f,%.3f,%.1f,%.3f,%d", p.day, p.mahalanobis, p.strain, p.coherence, p.debt, p.baselineNights))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulso-inteligencia-\(DayKey.string(Date())).csv")
        return (try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}
