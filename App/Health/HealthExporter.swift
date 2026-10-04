import Foundation
import HealthKit
import PulsoStore

/// Writes Pulso's measurements into Apple Health. Every sample carries a stable sync identifier,
/// so re-exporting the same night or minute replaces instead of duplicating.
final class HealthExporter {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var shareTypes: Set<HKSampleType> {
        var set = Set<HKSampleType>()
        let quantities: [HKQuantityTypeIdentifier] = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate,
            .oxygenSaturation, .activeEnergyBurned,
        ]
        for id in quantities {
            if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        return set
    }

    func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        guard isAvailable else {
            done(false)
            return
        }
        store.requestAuthorization(toShare: shareTypes, read: nil) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    private func meta(_ id: String) -> [String: Any] {
        [HKMetadataKeySyncIdentifier: "pulso.\(id)", HKMetadataKeySyncVersion: 1]
    }

    private func quantity(_ id: HKQuantityTypeIdentifier, _ value: Double, _ unit: HKUnit, at date: Date, key: String) -> HKQuantitySample? {
        guard let type = HKObjectType.quantityType(forIdentifier: id), value.isFinite else { return nil }
        return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                                start: date, end: date, metadata: meta(key))
    }

    func export(days: [DaySummary], sleeps: [SleepSession], samples: [Sample], workouts: [Workout]) {
        guard isAvailable else { return }
        var objects: [HKObject] = []
        let bpm = HKUnit.count().unitDivided(by: .minute())

        for d in days {
            guard let wake = d.sleepEnd.map({ Date(timeIntervalSince1970: TimeInterval($0)) }) else { continue }
            if let v = d.rhr, let s = quantity(.restingHeartRate, v, bpm, at: wake, key: "rhr.\(d.day)") { objects.append(s) }
            if let v = d.respRate, let s = quantity(.respiratoryRate, v, bpm, at: wake, key: "resp.\(d.day)") { objects.append(s) }
            if let v = d.spo2, let s = quantity(.oxygenSaturation, v / 100, .percent(), at: wake, key: "spo2.\(d.day)") { objects.append(s) }
        }

        for s in sleeps {
            let key = "sleep.\(s.start)"
            if let v = s.hrvSDNN, let q = quantity(.heartRateVariabilitySDNN, v, .secondUnit(with: .milli),
                                                   at: Date(timeIntervalSince1970: TimeInterval(s.end)), key: "sdnn.\(s.start)") {
                objects.append(q)
            }
            guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { continue }
            let inBed = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                                         start: Date(timeIntervalSince1970: TimeInterval(s.start)),
                                         end: Date(timeIntervalSince1970: TimeInterval(s.end)), metadata: meta("\(key).inbed"))
            objects.append(inBed)
            // Contiguous stage segments.
            var i = 0
            while i < s.stages.count {
                let stage = s.stages[i]
                var j = i
                while j + 1 < s.stages.count && s.stages[j + 1] == stage { j += 1 }
                let value: HKCategoryValueSleepAnalysis
                switch stage {
                case .awake: value = .awake
                case .light: value = .asleepCore
                case .deep: value = .asleepDeep
                case .rem: value = .asleepREM
                }
                let a = Date(timeIntervalSince1970: TimeInterval(s.start + i * 60))
                let b = Date(timeIntervalSince1970: TimeInterval(min(s.end, s.start + (j + 1) * 60)))
                if b > a {
                    objects.append(HKCategorySample(type: type, value: value.rawValue, start: a, end: b,
                                                    metadata: meta("\(key).\(i)")))
                }
                i = j + 1
            }
        }

        // Heart rate as one-minute averages (plenty for Health, far fewer objects than 1 Hz).
        var minute: [Int: (sum: Double, n: Int)] = [:]
        for s in samples where s.worn {
            guard let hr = s.hr else { continue }
            let m = s.ts - s.ts % 60
            let cur = minute[m] ?? (0, 0)
            minute[m] = (cur.sum + Double(hr), cur.n + 1)
        }
        for (m, v) in minute where v.n >= 20 {
            if let q = quantity(.heartRate, v.sum / Double(v.n), bpm, at: Date(timeIntervalSince1970: TimeInterval(m)), key: "hr.\(m)") {
                objects.append(q)
            }
        }

        for w in workouts {
            let start = Date(timeIntervalSince1970: TimeInterval(w.start))
            let end = Date(timeIntervalSince1970: TimeInterval(w.end))
            if w.kcal > 0, end > start, let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
                objects.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: w.kcal),
                                                start: start, end: end, metadata: meta("kcal.\(w.start)")))
            }
        }

        guard !objects.isEmpty else { return }
        // Save in batches to keep each call small.
        var batch: [HKObject] = []
        for o in objects {
            batch.append(o)
            if batch.count >= 500 {
                store.save(batch) { _, _ in }
                batch.removeAll()
            }
        }
        if !batch.isEmpty { store.save(batch) { _, _ in } }
    }
}
