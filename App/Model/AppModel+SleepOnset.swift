import Foundation
import PulsoStore
import PulsoAnalytics

/// Silent sleep-onset test (`SleepOnsetWatch`): after «Respiración para dormir» or a test nap, keeps the live stream
/// on for a while, notes when the beats say you fell asleep and lets the stream go. Nothing vibrates or notifies.
/// The trials are set against the downloaded sleep in Laboratorio → Dormirse (prueba).
extension AppModel {
    static let onsetTrialsKey = "sleepOnset.trials"
    static let onsetAfterBreathingKey = "sleepOnset.afterBreathing"
    private static let onsetClient = "onsetWatch"

    var onsetTrials: [SleepOnsetWatch.Trial] { db.get([SleepOnsetWatch.Trial].self, for: Self.onsetTrialsKey) ?? [] }

    /// On by default: it only costs the strap the live stream for up to 45 min after a 4-7-8 session.
    var onsetAfterBreathing: Bool {
        get { UserDefaults.standard.object(forKey: Self.onsetAfterBreathingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.onsetAfterBreathingKey); objectWillChange.send() }
    }

    func startOnsetTrial(_ kind: SleepOnsetWatch.Kind, napMinutes: Int? = nil) {
        if onsetTrial != nil { finishOnsetTrial() }
        let now = Int(Date().timeIntervalSince1970)
        onsetTrial = SleepOnsetWatch.Trial(kind: kind, start: now, end: now, napMinutes: kind == .nap ? (napMinutes ?? 20) : nil)
        onsetBeats = []
        onsetLastCheck = 0
        // Its own client, not screen-only: it has to keep going with the phone locked.
        setLive(true, client: Self.onsetClient)
    }

    /// Called when a guided breathing session ends.
    func breathingFinished(_ kind: Breathwork.Kind) {
        guard kind == .sleep, onsetAfterBreathing, liveWorkout == nil, onsetTrial?.kind != .nap else { return }
        startOnsetTrial(.breathing)
    }

    /// Every live notification: keeps the trial's beats and, every 30 s, looks for the onset.
    func checkOnsetTrial(at date: Date) {
        guard var trial = onsetTrial else { return }
        let last = onsetBeats.last?.t ?? Double(trial.start)
        onsetBeats += liveBeats.filter { $0.t > last }
        let now = date.timeIntervalSince1970
        guard now - onsetLastCheck >= 30 else { return }
        onsetLastCheck = now
        if trial.liveOnset == nil, let onset = SleepOnsetWatch.detect(onsetBeats, from: Double(trial.start)) {
            trial.liveOnset = Int(onset)
            if let m = trial.napMinutes { trial.wouldWakeAt = Int(onset) + m * 60 }
        }
        onsetTrial = trial
        if SleepOnsetWatch.shouldStop(trial, now: now) { finishOnsetTrial() }
    }

    /// Saves the trial and lets the live stream go.
    func finishOnsetTrial() {
        guard var trial = onsetTrial else { return }
        trial.end = Int(Date().timeIntervalSince1970)
        onsetTrial = nil
        onsetBeats = []
        setLive(false, client: Self.onsetClient)
        // Shorter than the 3-min baseline: nothing to compare.
        guard trial.end - trial.start >= 4 * 60 else { return }
        var all = onsetTrials
        all.append(trial)
        try? db.set(Array(all.suffix(200)), for: Self.onsetTrialsKey)
        objectWillChange.send()
    }

    /// Onset from the downloaded sleep for a trial (nil until that sleep has been downloaded and analysed).
    func downloadedOnset(_ trial: SleepOnsetWatch.Trial) -> Int? {
        let sleeps = ((try? db.sleeps(from: trial.start - 3 * 3600, to: trial.start + 6 * 3600)) ?? [])
            .map { (start: $0.start, stages: $0.stages.map(\.rawValue)) }
        return SleepOnsetWatch.downloadedOnset(trial, sleeps: sleeps)
    }
}
