import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntegrations

extension AppModel {
    // MARK: - Double tap

    /// Last double tap received from the strap: the 5.0's event isn't documented, so this is the proof it works.
    var lastDoubleTapAt: Date? {
        get { UserDefaults.standard.object(forKey: "pulso.doubleTap.last") as? Date }
        set {
            UserDefaults.standard.set(newValue, forKey: "pulso.doubleTap.last")
            objectWillChange.send()
        }
    }

    func handleDoubleTap() {
        // The strap may repeat the event: one gesture, one action.
        if let last = lastDoubleTapAt, Date().timeIntervalSince(last) < 1.5 { return }
        lastDoubleTapAt = Date()
        let alarmActive = wakeSession?.isActive == true
        switch GestureRouter.route(action: settings.doubleTap, alarmActive: alarmActive, workoutActive: liveWorkout != nil) {
        case .alarm:
            if let s = wakeSession {
                strap.stopHaptics()
                perform(s.doubleTap(now: Int(Date().timeIntervalSince1970)), session: s)
            }
        case .marker:
            addMarker()
        case .startWorkout:
            startWorkout(sport: settings.quickSport)
            strap.buzz(loops: 2)
            NotificationService.shared.now("Entreno iniciado", "\(settings.quickSport). Doble toque otra vez para terminarlo.", sound: false)
        case .stopWorkout:
            let sport = liveWorkout?.sport ?? ""
            stopWorkout(save: true)
            strap.buzz(loops: 3)
            NotificationService.shared.now("Entreno guardado", sport, sound: false)
        case .lap:
            markLap()
        case .breathing:
            startBreathingGuide()
        case .ignored:
            break
        }
    }

    func addMarker(note: String = "") {
        try? db.insertEvent(StoredEvent(ts: Int(Date().timeIntervalSince1970), kind: EventKind.marker, value: nil))
        strap.buzz(loops: 1)
        appendLog("Marca guardada")
        objectWillChange.send()
    }

    func markLap() {
        guard var w = liveWorkout else { return addMarker() }
        let now = Int(Date().timeIntervalSince1970)
        w.lapStats.append(lapSummary(from: w.laps.last ?? Int(w.start.timeIntervalSince1970), to: now))
        w.laps.append(now)
        liveWorkout = w
        strap.buzz(loops: 1)
        if settings.voiceCues { voice.say("Vuelta \(w.laps.count)") }
    }

    // MARK: - Haptic sequences (breathing guide)

    func enqueueHaptics(_ steps: [HapticStep], from start: Date = Date().addingTimeInterval(0.5)) {
        hapticQueue += steps.map { (at: start.addingTimeInterval($0.at), loops: $0.loops) }
        hapticQueue.sort { $0.at < $1.at }
    }

    func drainHaptics(now: Date) {
        var played = false
        while let first = hapticQueue.first, first.at <= now {
            hapticQueue.removeFirst()
            // Never fire a burst after a pause: only the latest due step plays.
            if hapticQueue.first.map({ $0.at <= now }) != true { strap.buzz(loops: first.loops) }
            played = true
        }
        if played, hapticQueue.isEmpty, breathingGuideActive {
            breathingGuideActive = false
            setLive(false, client: "breathing")
        }
    }

    /// One minute of resonance breathing guided only by the strap (short buzz = inhale, double = exhale).
    func startBreathingGuide(cycles: Int = 6) {
        guard !breathingGuideActive else { return }
        breathingGuideActive = true
        setLive(true, client: "breathing") // keeps the app ticking with the screen off
        enqueueHaptics(HapticPlan.breathing(cycles: cycles))
    }

    func stopBreathingGuide() {
        hapticQueue.removeAll()
        breathingGuideActive = false
        setLive(false, client: "breathing")
    }

    // MARK: - Intervals

    func intervalTick(now: Date) {
        guard let r = intervalRunner, liveWorkout != nil else { return }
        let t = Int(now.timeIntervalSince1970)
        for cue in r.tick(now: t, heartRate: liveHR.map(Double.init), model: heartRateModel) {
            if let loops = cue.buzzLoops { strap.buzz(loops: loops) }
            if settings.voiceCues { voice.say(cue.phrase) }
            if case .finished = cue {
                intervalStatus = nil
                NotificationService.shared.now("Plan completado", r.plan.name, sound: false)
            }
        }
        let pos = r.position(at: t)
        if pos.index < r.plan.steps.count {
            let step = r.plan.steps[pos.index]
            let next = pos.index + 1 < r.plan.steps.count ? r.plan.steps[pos.index + 1] : nil
            intervalStatus = (step: step.kind.label + (step.zoneText.map { " · \($0)" } ?? ""), remaining: pos.remaining,
                              next: next.map { "\($0.kind.label) \(LiveView.duration(TimeInterval($0.seconds)))" })
        }
        updateWorkoutActivity()
    }

    // MARK: - Live Activity

    func startWorkoutActivity(sport: String, start: Date) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = WorkoutActivityAttributes(sport: sport, symbol: SportCatalog.named(sport).symbol, start: start)
        let state = WorkoutActivityAttributes.ContentState(heartRate: liveHR ?? 0, zone: 0, strain: 0, kcal: 0, step: nil, stepEnds: nil)
        _ = try? Activity.request(attributes: attrs, content: ActivityContent(state: state, staleDate: nil), pushType: nil)
        #endif
    }

    func updateWorkoutActivity() {
        #if canImport(ActivityKit)
        guard let w = liveWorkout, let activity = Activity<WorkoutActivityAttributes>.activities.first else { return }
        // At most every 5 s (the system throttles anyway).
        if let last = lastActivityUpdate, Date().timeIntervalSince(last) < 5 { return }
        lastActivityUpdate = Date()
        let hr = liveHR ?? 0
        let status = intervalStatus
        let state = WorkoutActivityAttributes.ContentState(
            heartRate: hr, zone: hr > 0 ? heartRateModel.zone(Double(hr)) : 0, strain: Strain.score(load: w.load),
            kcal: Int(w.kcal), step: status?.step, stepEnds: status.map { Date().addingTimeInterval(TimeInterval($0.remaining)) })
        Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))) }
        #endif
    }

    func endWorkoutActivity() {
        #if canImport(ActivityKit)
        for activity in Activity<WorkoutActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }
}
