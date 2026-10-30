import Foundation
import PulsoStore
import PulsoAnalytics
import PulsoIntelligence

extension AppModel {
    /// Cached 60-s heart-rate recovery of one workout. Only final answers are stored: a workout whose
    /// strap data hasn't been downloaded yet is retried once it is, instead of keeping a −1 forever.
    struct HRRCache: Codable {
        enum State: String, Codable { case ok, noCurve, noHeartData }
        var state: State
        var drop: Double?
    }

    nonisolated static func hrrKey(_ w: Workout) -> String { "hrr.v2.\(w.start)" }

    /// Recomputes the Inteligencia report off the main thread (after each analysis).
    func refreshIntelligence() {
        let db = self.db
        let hr = heartRateModel
        let measuredMax = profile.maxHROverride != nil
        let profile = self.profile
        let currentDay = currentDayKey
        // "Anoche" = the night that should already be in: today's once it's expected but missing.
        let lastNight = nightStatus == .ok ? currentDay : DayKey.string(Date())
        let lastSample = lastSampleTs
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
                let key = Self.hrrKey(w)
                var cached = db.get(HRRCache.self, for: key)
                if cached == nil, nowTs - w.end > 1800 {
                    let windowEnd = w.end + 1800
                    let downloaded = (lastSample ?? 0) >= windowEnd
                    let samples = (try? db.samples(from: w.start - 60, to: windowEnd)) ?? []
                    let beats = samples.filter { ($0.hr ?? 0) > 0 }.count
                    if beats < 60 {
                        // Nothing from the strap here: final for imported workouts or once later data exists.
                        if w.source.isExternal || downloaded { cached = HRRCache(state: .noHeartData) }
                    } else if downloaded {
                        let r = WorkoutAnalysis.analyze(workout: w, samples: samples, restingHR: hr.restingHR, maxHR: hr.maxHR,
                                                        maxHRMeasured: measuredMax)
                        cached = r.recovery?.drop60.map { HRRCache(state: .ok, drop: $0) } ?? HRRCache(state: .noCurve)
                    }
                    if let c = cached { try? db.set(c, for: key) }
                }
                if let d = cached?.drop, d > 0 { drops.append((DayKey.string(ts: w.start), d)) }
            }
            let report = Intelligence.report(days: days, sleeps: sleeps, workouts: workouts, journal: journal, hrrDrops: drops, now: now,
                                             currentDay: currentDay, lastNight: lastNight)
            Task { @MainActor in self.intelligence = report }
        }
    }

    /// Whether the strap recorded this workout at all (imported ones often have no pulse behind them).
    func workoutHasHeartData(_ w: Workout) -> Bool {
        if db.get(HRRCache.self, for: Self.hrrKey(w))?.state == .noHeartData { return false }
        let samples = (try? db.samples(from: w.start, to: w.end)) ?? []
        return samples.filter { ($0.hr ?? 0) > 0 }.count >= 60
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
