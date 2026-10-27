import Foundation
import PulsoStore
import PulsoAnalytics

/// "¿Te acabas de echar una siesta o era tu sueño?": daytime sleeps waiting for an answer.
extension AppModel {
    /// After this long without an answer Pulso keeps its own classification and stops asking.
    static let sleepQuestionWindow: TimeInterval = 12 * 3600
    private static let notifiedKey = "pulso.sleepQuestion.notified"

    /// Daytime sleeps detected in the last hours that the user hasn't classified yet, newest first.
    var pendingSleepQuestions: [SleepSession] {
        let now = Date()
        let from = Int(now.addingTimeInterval(-Self.sleepQuestionWindow).timeIntervalSince1970)
        let mainIDs = Set(days.compactMap(\.sleepId))
        let list = (try? db.sleeps(from: from - 16 * 3600, to: Int(now.timeIntervalSince1970))) ?? []
        return list.filter { s in
            guard !s.manual, !s.kindConfirmed, s.end >= from else { return false }
            if let id = s.id, mainIDs.contains(id) && !s.isNap { return false }
            let hour = Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(s.start)))
            return (10..<22).contains(hour)
        }
        .sorted { $0.start > $1.start }
    }

    /// Records the answer and recomputes that day so it counts the right way.
    func answerSleepQuestion(_ s: SleepSession, isNap: Bool) {
        try? db.saveSleepDecision(SleepDecision(start: s.start, end: s.end, kind: isNap ? .nap : .sleep))
        NotificationService.shared.remove([Self.questionID(s)])
        let day = DayKey.string(ts: s.end)
        recompute(fromDay: DayKey.shift(day, days: -1))
    }

    /// Sends one notification per new daytime sleep (called after every reload).
    func notifySleepQuestions() {
        guard !AppMode.screenshots, !demoActive else { return }
        var done = Set(UserDefaults.standard.stringArray(forKey: Self.notifiedKey) ?? [])
        for s in pendingSleepQuestions where !done.contains(Self.questionID(s)) {
            let minutes = s.asleepMinutes
            let what = s.isNap ? "una siesta" : "tu sueño"
            NotificationService.shared.now("¿Siesta o sueño?",
                                           "Has dormido \(Fmt.hm(minutes)) (\(Fmt.time(s.start))–\(Fmt.time(s.end))). Lo he contado como \(what): ¿es correcto?",
                                           id: Self.questionID(s), category: NotificationService.Category.sleepQuestion, sound: false)
            done.insert(Self.questionID(s))
        }
        UserDefaults.standard.set(Array(done.suffix(100)), forKey: Self.notifiedKey)
    }

    static func questionID(_ s: SleepSession) -> String { "pulso.sleepq.\(s.start).\(s.end)" }

    /// Notification button → answer.
    func handleSleepQuestionAction(_ action: String, id: String) {
        let parts = id.split(separator: ".")
        guard parts.count == 4, let start = Int(parts[2]), let end = Int(parts[3]) else { return }
        let s = pendingSleepQuestions.first { $0.start == start && $0.end == end }
            ?? SleepSession(start: start, end: end)
        switch action {
        case NotificationService.Action.wasNap: answerSleepQuestion(s, isNap: true)
        case NotificationService.Action.wasSleep: answerSleepQuestion(s, isNap: false)
        default: break
        }
    }
}
