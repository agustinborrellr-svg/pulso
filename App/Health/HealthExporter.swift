import Foundation
import HealthKit
import PulsoStore
import PulsoIntegrations

/// Apple Health bridge.
/// - Writes Pulso's measurements (HR, resting HR, HRV, breathing, SpO₂, sleep stages) with stable
///   sync identifiers, so re-exporting replaces instead of duplicating.
/// - Saves workouts as real Health workouts with their heart rate.
/// - Imports workouts recorded by other apps (Garmin, Strava, Nike, Peloton, gym apps…) and Apple
///   Watch ECGs.
final class HealthExporter {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var shareTypes: Set<HKSampleType> {
        var set = Set<HKSampleType>()
        let quantities: [HKQuantityTypeIdentifier] = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate,
            .oxygenSaturation, .activeEnergyBurned, .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
        ]
        for id in quantities {
            if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(sleep) }
        set.insert(HKObjectType.workoutType())
        return set
    }

    private var readTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = [HKObjectType.workoutType(), HKObjectType.electrocardiogramType()]
        for id in [HKQuantityTypeIdentifier.heartRate, .activeEnergyBurned, .distanceWalkingRunning, .distanceCycling, .distanceSwimming] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { set.insert(t) }
        }
        return set
    }

    func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        guard isAvailable else {
            done(false)
            return
        }
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    /// Version of the current export: a higher version makes Health replace the sample with the same
    /// sync identifier (recomputed nights / edited sleep update instead of being ignored).
    private var exportVersion = 1

    private func meta(_ id: String) -> [String: Any] {
        [HKMetadataKeySyncIdentifier: "pulso.\(id)", HKMetadataKeySyncVersion: exportVersion]
    }

    private func quantity(_ id: HKQuantityTypeIdentifier, _ value: Double, _ unit: HKUnit, at date: Date, key: String) -> HKQuantitySample? {
        guard let type = HKObjectType.quantityType(forIdentifier: id), value.isFinite else { return nil }
        return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                                start: date, end: date, metadata: meta(key))
    }

    func export(days: [DaySummary], sleeps: [SleepSession], samples: [Sample], workouts: [Workout]) {
        guard isAvailable else { return }
        exportVersion = Int(Date().timeIntervalSince1970)
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

        // Workouts already saved as full Health workouts carry their own energy; only the rest get a sample.
        for w in workouts where w.externalID("health") == nil && !w.source.isExternal {
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

    // MARK: - Workouts out

    static func activityType(for sport: String) -> HKWorkoutActivityType {
        switch SportCatalog.named(sport).health {
        case "running": return .running
        case "cycling": return .cycling
        case "walking": return .walking
        case "hiking": return .hiking
        case "strength": return .traditionalStrengthTraining
        case "hiit": return .highIntensityIntervalTraining
        case "crossTraining": return .crossTraining
        case "swimming": return .swimming
        case "rowing": return .rowing
        case "yoga": return .yoga
        case "pilates": return .pilates
        case "elliptical": return .elliptical
        case "paddle": return .racquetball
        case "tennis": return .tennis
        case "soccer": return .soccer
        case "basketball": return .basketball
        case "climbing": return .climbing
        case "skiing": return .downhillSkiing
        case "golf": return .golf
        case "dance": return .socialDance
        default: return .other
        }
    }

    static func healthKey(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "running"
        case .cycling, .handCycling: return "cycling"
        case .walking: return "walking"
        case .hiking: return "hiking"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: return "strength"
        case .highIntensityIntervalTraining, .mixedCardio: return "hiit"
        case .crossTraining: return "crossTraining"
        case .swimming: return "swimming"
        case .rowing, .paddleSports: return "rowing"
        case .yoga, .mindAndBody: return "yoga"
        case .pilates, .barre: return "pilates"
        case .elliptical, .stairClimbing, .stairs, .stepTraining: return "elliptical"
        case .tennis, .racquetball, .squash, .badminton, .tableTennis, .pickleball: return "tennis"
        case .soccer: return "soccer"
        case .basketball: return "basketball"
        case .climbing: return "climbing"
        case .downhillSkiing, .crossCountrySkiing, .snowboarding, .snowSports: return "skiing"
        case .golf: return "golf"
        case .socialDance, .cardioDance, .dance: return "dance"
        default: return "other"
        }
    }

    private static func distanceType(for sport: String) -> HKQuantityType? {
        switch SportCatalog.named(sport).health {
        case "running", "walking", "hiking": return HKQuantityType(.distanceWalkingRunning)
        case "cycling": return HKQuantityType(.distanceCycling)
        case "swimming": return HKQuantityType(.distanceSwimming)
        default: return nil
        }
    }

    /// Saves `w` as a Health workout with its heart rate (5-second averages). Returns the workout UUID.
    func saveWorkout(_ w: Workout, heartRate: [(ts: Int, bpm: Int)], completion: @escaping (String?) -> Void) {
        guard isAvailable, w.end > w.start else { return completion(nil) }
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: w.sport)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        let start = Date(timeIntervalSince1970: TimeInterval(w.start))
        let end = Date(timeIntervalSince1970: TimeInterval(w.end))
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var samples: [HKSample] = []
        var bucket: [Int: [Int]] = [:]
        for p in heartRate where p.ts >= w.start && p.ts < w.end { bucket[p.ts - p.ts % 5, default: []].append(p.bpm) }
        for (t, v) in bucket.sorted(by: { $0.key < $1.key }) {
            let d = Date(timeIntervalSince1970: TimeInterval(t))
            samples.append(HKQuantitySample(type: HKQuantityType(.heartRate),
                                            quantity: HKQuantity(unit: bpm, doubleValue: Double(v.reduce(0, +)) / Double(v.count)),
                                            start: d, end: d))
        }
        if w.kcal > 0 {
            samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: w.kcal), start: start, end: end))
        }
        if let dist = w.distanceMeters, dist > 0, let type = Self.distanceType(for: w.sport) {
            samples.append(HKQuantitySample(type: type, quantity: HKQuantity(unit: .meter(), doubleValue: dist), start: start, end: end))
        }
        let metadata: [String: Any] = [HKMetadataKeySyncIdentifier: "pulso.workout.\(w.start)", HKMetadataKeySyncVersion: 1,
                                       HKMetadataKeyWorkoutBrandName: "Pulso"]
        builder.beginCollection(withStart: start) { ok, _ in
            guard ok else { return DispatchQueue.main.async { completion(nil) } }
            let finish = {
                builder.addMetadata(metadata) { _, _ in
                    builder.endCollection(withEnd: end) { _, _ in
                        builder.finishWorkout { workout, _ in
                            DispatchQueue.main.async { completion(workout?.uuid.uuidString) }
                        }
                    }
                }
            }
            if samples.isEmpty {
                finish()
            } else {
                builder.add(samples) { _, _ in finish() }
            }
        }
    }

    // MARK: - Workouts in

    /// Workouts recorded by other apps since `since` (Pulso's own are skipped).
    func importWorkouts(since: Date, completion: @escaping ([Workout]) -> Void) {
        guard isAvailable else { return completion([]) }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        let mine = Bundle.main.bundleIdentifier ?? ""
        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 500, sortDescriptors: sort) { _, samples, _ in
            let list = (samples as? [HKWorkout] ?? [])
                .filter { $0.sourceRevision.source.bundleIdentifier != mine }
                .map { Self.workout(from: $0) }
            DispatchQueue.main.async { completion(list) }
        }
        store.execute(query)
    }

    static func workout(from hk: HKWorkout) -> Workout {
        let sport = SportCatalog.fromHealth(healthKey(for: hk.workoutActivityType)).name
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let kcal = hk.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        let hr = hk.statistics(for: HKQuantityType(.heartRate))
        var distance: Double?
        for id in [HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling, .distanceSwimming] {
            if let d = hk.statistics(for: HKQuantityType(id))?.sumQuantity()?.doubleValue(for: .meter()), d > 0 {
                distance = d
                break
            }
        }
        var w = Workout(start: Int(hk.startDate.timeIntervalSince1970), end: Int(hk.endDate.timeIntervalSince1970), sport: sport,
                        source: .health, avgHR: hr?.averageQuantity()?.doubleValue(for: bpm) ?? 0,
                        maxHR: hr?.maximumQuantity()?.doubleValue(for: bpm) ?? 0, kcal: kcal,
                        externalApp: hk.sourceRevision.source.name, distanceMeters: distance)
        w.setExternalID(hk.uuid.uuidString, for: "health")
        return w
    }

    // MARK: - ECG in (Apple Watch)

    /// Apple Watch ECGs since `since` as Pulso recordings (millivolts, lead I-like).
    func importECGs(since: Date, completion: @escaping ([ECGRecording]) -> Void) {
        guard isAvailable else { return completion([]) }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let query = HKSampleQuery(sampleType: HKObjectType.electrocardiogramType(), predicate: predicate, limit: 30,
                                  sortDescriptors: sort) { [weak self] _, samples, _ in
            guard let self else { return }
            let ecgs = samples as? [HKElectrocardiogram] ?? []
            guard !ecgs.isEmpty else { return DispatchQueue.main.async { completion([]) } }
            let lock = NSLock()
            var out: [ECGRecording] = []
            let group = DispatchGroup()
            for e in ecgs {
                group.enter()
                var volts: [Float] = []
                let q = HKElectrocardiogramQuery(e) { _, result in
                    switch result {
                    case .measurement(let m):
                        if let v = m.quantity(for: .appleWatchSimilarToLeadI)?.doubleValue(for: .voltUnit(with: .milli)) {
                            volts.append(Float(v))
                        }
                    case .done:
                        let rate = e.samplingFrequency?.doubleValue(for: .hertz()) ?? 512
                        let rec = ECGRecording(start: Int(e.startDate.timeIntervalSince1970), sampleRate: rate, samples: volts,
                                               source: .appleWatch, externalID: e.uuid.uuidString)
                        lock.lock(); out.append(rec); lock.unlock()
                        group.leave()
                    case .error:
                        group.leave()
                    @unknown default:
                        group.leave()
                    }
                }
                self.store.execute(q)
            }
            group.notify(queue: .main) { completion(out) }
        }
        store.execute(query)
    }
}
