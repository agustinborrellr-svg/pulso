import Foundation
import PulsoStore
import PulsoAnalytics

// MARK: - Configuration

public enum WakeMode: String, Codable, CaseIterable, Sendable {
    /// Exactly at the set time.
    case fixed
    /// In the best moment (light sleep) of the window ending at the set time.
    case smart
    /// As soon as you've slept what you need (in light sleep), never later than the set time.
    case sleepGoal

    public var label: String {
        switch self {
        case .fixed: return "Hora fija"
        case .smart: return "Inteligente (sueño ligero)"
        case .sleepGoal: return "Cuando haya dormido lo necesario"
        }
    }
}

public enum VibrationStyle: String, Codable, CaseIterable, Sendable {
    case gentle, normal, strong, progressive

    public var label: String {
        switch self {
        case .gentle: return "Suave"
        case .normal: return "Normal"
        case .strong: return "Fuerte"
        case .progressive: return "Progresiva"
        }
    }
}

public enum AlarmDoubleTap: String, Codable, CaseIterable, Sendable {
    case snooze, stop

    public var label: String { self == .snooze ? "Posponer" : "Apagar" }
}

/// One alarm. `hour:minute` is the latest wake time; smart modes may wake you earlier inside the window.
public struct AlarmConfig: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var enabled: Bool
    public var label: String
    public var hour: Int
    public var minute: Int
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty = one-off (next occurrence, then disables).
    public var weekdays: [Int]
    public var mode: WakeMode
    public var windowMinutes: Int
    public var vibration: VibrationStyle
    /// iPhone alarm as a backup if the strap doesn't wake you.
    public var phoneBackup: Bool
    /// Minutes after the latest time before the iPhone rings (gives the strap the first go).
    public var phoneBackupDelay: Int
    public var snoozeMinutes: Int
    public var maxSnoozes: Int
    public var doubleTap: AlarmDoubleTap
    /// Notification with recovery and sleep after waking.
    public var morningReport: Bool
    /// Day key (yyyy-MM-dd) to skip once.
    public var skipDay: String?

    public init(id: String = UUID().uuidString, enabled: Bool = true, label: String = "Despertador", hour: Int = 7,
                minute: Int = 0, weekdays: [Int] = [2, 3, 4, 5, 6], mode: WakeMode = .smart, windowMinutes: Int = 30,
                vibration: VibrationStyle = .progressive, phoneBackup: Bool = true, phoneBackupDelay: Int = 2,
                snoozeMinutes: Int = 9, maxSnoozes: Int = 3, doubleTap: AlarmDoubleTap = .snooze,
                morningReport: Bool = true, skipDay: String? = nil) {
        self.id = id
        self.enabled = enabled
        self.label = label
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.mode = mode
        self.windowMinutes = windowMinutes
        self.vibration = vibration
        self.phoneBackup = phoneBackup
        self.phoneBackupDelay = phoneBackupDelay
        self.snoozeMinutes = snoozeMinutes
        self.maxSnoozes = maxSnoozes
        self.doubleTap = doubleTap
        self.morningReport = morningReport
        self.skipDay = skipDay
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, label, hour, minute, weekdays, mode, windowMinutes, vibration, phoneBackup, phoneBackupDelay
        case snoozeMinutes, maxSnoozes, doubleTap, morningReport, skipDay
    }

    /// Tolerant decoding: alarms saved by older versions keep working when fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlarmConfig()
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? d.label
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? d.hour
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? d.minute
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? d.weekdays
        mode = try c.decodeIfPresent(WakeMode.self, forKey: .mode) ?? d.mode
        windowMinutes = try c.decodeIfPresent(Int.self, forKey: .windowMinutes) ?? d.windowMinutes
        vibration = try c.decodeIfPresent(VibrationStyle.self, forKey: .vibration) ?? d.vibration
        phoneBackup = try c.decodeIfPresent(Bool.self, forKey: .phoneBackup) ?? d.phoneBackup
        phoneBackupDelay = try c.decodeIfPresent(Int.self, forKey: .phoneBackupDelay) ?? d.phoneBackupDelay
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? d.snoozeMinutes
        maxSnoozes = try c.decodeIfPresent(Int.self, forKey: .maxSnoozes) ?? d.maxSnoozes
        doubleTap = try c.decodeIfPresent(AlarmDoubleTap.self, forKey: .doubleTap) ?? d.doubleTap
        morningReport = try c.decodeIfPresent(Bool.self, forKey: .morningReport) ?? d.morningReport
        skipDay = try c.decodeIfPresent(String.self, forKey: .skipDay)
    }

    public var isRepeating: Bool { !weekdays.isEmpty }

    public var timeText: String { String(format: "%02d:%02d", hour, minute) }

    /// "L M X J V", "Todos los días", "Fines de semana", "Una vez".
    public var daysText: String {
        let set = Set(weekdays)
        if set.isEmpty { return "Una vez" }
        if set.count == 7 { return "Todos los días" }
        if set == [2, 3, 4, 5, 6] { return "Entre semana" }
        if set == [1, 7] { return "Fines de semana" }
        let names = [2: "L", 3: "M", 4: "X", 5: "J", 6: "V", 7: "S", 1: "D"]
        return [2, 3, 4, 5, 6, 7, 1].filter(set.contains).compactMap { names[$0] }.joined(separator: " ")
    }
}

// MARK: - Planning

public struct PlannedAlarm: Equatable, Sendable {
    public var alarm: AlarmConfig
    /// Latest wake time (the set time).
    public var latest: Date
    /// Start of the smart window (== latest for fixed alarms).
    public var earliest: Date
    public var dayKey: String

    public var isSmart: Bool { alarm.mode != .fixed }
}

public enum AlarmPlanner {
    /// Next time `alarm` goes off strictly after `now`, or nil if disabled.
    public static func next(_ alarm: AlarmConfig, after now: Date, calendar: Calendar = .current) -> PlannedAlarm? {
        guard alarm.enabled else { return nil }
        var probe = now
        for _ in 0..<15 {
            guard let date = calendar.nextDate(after: probe, matching: DateComponents(hour: alarm.hour, minute: alarm.minute, second: 0),
                                               matchingPolicy: .nextTime) else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            let key = DayKey.string(date, calendar: calendar)
            let dayOK = alarm.weekdays.isEmpty || alarm.weekdays.contains(weekday)
            if dayOK && key != alarm.skipDay {
                let window = alarm.mode == .fixed ? 0 : max(0, alarm.windowMinutes)
                return PlannedAlarm(alarm: alarm, latest: date, earliest: date.addingTimeInterval(-Double(window) * 60), dayKey: key)
            }
            probe = date.addingTimeInterval(60)
        }
        return nil
    }

    /// The soonest upcoming alarm among `alarms` (by window start).
    public static func next(_ alarms: [AlarmConfig], after now: Date, calendar: Calendar = .current) -> PlannedAlarm? {
        alarms.compactMap { next($0, after: now, calendar: calendar) }.min { $0.earliest < $1.earliest }
    }

    /// Upcoming occurrences of all alarms within `days` (for scheduling backups ahead of time).
    public static func upcoming(_ alarms: [AlarmConfig], after now: Date, days: Int = 7, calendar: Calendar = .current) -> [PlannedAlarm] {
        let limit = now.addingTimeInterval(Double(days) * 86400)
        var out: [PlannedAlarm] = []
        for a in alarms {
            var t = now
            while let p = next(a, after: t, calendar: calendar), p.latest <= limit {
                out.append(p)
                if !a.isRepeating { break }
                t = p.latest.addingTimeInterval(60)
            }
        }
        return out.sorted { $0.latest < $1.latest }
    }

    /// What to store after an occurrence has run: one-off alarms switch off, skips are consumed.
    public static func afterFiring(_ alarm: AlarmConfig, dayKey: String) -> AlarmConfig {
        var a = alarm
        if !a.isRepeating { a.enabled = false }
        if a.skipDay == dayKey { a.skipDay = nil }
        return a
    }
}

// MARK: - Haptics

/// One buzz of the strap: `loops` repetitions of the notification waveform, `at` seconds after the
/// ring started.
public struct HapticStep: Equatable, Sendable {
    public var at: Double
    public var loops: UInt8
}

public enum HapticPlan {
    /// Buzz schedule for one ringing period of `duration` seconds.
    public static func ring(_ style: VibrationStyle, duration: Double = 180) -> [HapticStep] {
        var out: [HapticStep] = []
        var t = 0.0
        while t < duration {
            let (loops, gap): (UInt8, Double)
            switch style {
            case .gentle: (loops, gap) = (1, 6)
            case .normal: (loops, gap) = (2, 4)
            case .strong: (loops, gap) = (4, 2.5)
            case .progressive:
                switch t {
                case ..<30: (loops, gap) = (1, 8)
                case ..<75: (loops, gap) = (2, 5)
                case ..<120: (loops, gap) = (4, 3)
                default: (loops, gap) = (6, 2)
                }
            }
            out.append(HapticStep(at: t, loops: loops))
            t += gap
        }
        return out
    }

    /// Paced-breathing guide on the strap: a short buzz to start each inhale, a double one to start
    /// each exhale (4 s in, 6 s out by default ≈ 6 breaths/min).
    public static func breathing(cycles: Int = 6, inhale: Double = 4, exhale: Double = 6) -> [HapticStep] {
        var out: [HapticStep] = []
        for c in 0..<max(1, cycles) {
            let base = Double(c) * (inhale + exhale)
            out.append(HapticStep(at: base, loops: 1))
            out.append(HapticStep(at: base + inhale, loops: 2))
        }
        return out
    }
}

// MARK: - Wake session (state machine)

/// Runs one alarm occurrence: watches the smart window, rings, snoozes and stops.
///
/// It is driven by `tick(now:)`, which the app calls from every Bluetooth notification (the live
/// heart-rate stream arrives ~1 Hz and keeps the app running in the background) and from timers
/// when in the foreground. After each sync during the window the app calls `evaluate(samples:now:)`.
/// Pure logic: it only returns actions for the app to perform.
public final class WakeSession {
    public enum State: Equatable {
        case waiting
        case monitoring
        case ringing(since: Int)
        case snoozed(until: Int)
        case finished
    }

    public enum Action: Equatable {
        /// Turn the strap's live heart-rate stream on (keeps the app awake in the background).
        case startLiveStream
        case stopLiveStream
        /// Pull the latest seconds off the strap, then call `evaluate`.
        case requestSync
        case buzz(loops: UInt8)
        /// Show a notification / in-app banner.
        case alert(title: String, body: String)
        /// Move the iPhone backup alarm to this time (or cancel it with nil).
        case backup(at: Int?)
        case finished(reason: String)
    }

    public let planned: PlannedAlarm
    public private(set) var state: State = .waiting
    public private(set) var snoozeCount = 0
    public private(set) var lastDecision: SmartWake.Decision?
    public private(set) var wokeEarlyBy: Int?
    private var streamStarted = false
    private var lastSyncRequest: Int?
    private var lastPlayedIndex = -1
    private var ringSteps: [HapticStep]
    private let needMinutes: Double?

    /// Seconds of continuous ringing before an automatic snooze.
    public var ringDuration: Double = 180
    /// Seconds between strap syncs inside the window.
    public var syncInterval = 150
    /// Lead before the window when the live stream is switched on.
    public var streamLead = 15 * 60

    public init(planned: PlannedAlarm, needMinutes: Double? = nil) {
        self.planned = planned
        self.needMinutes = needMinutes
        self.ringSteps = HapticPlan.ring(planned.alarm.vibration, duration: 180)
    }

    var earliest: Int { Int(planned.earliest.timeIntervalSince1970) }
    var latest: Int { Int(planned.latest.timeIntervalSince1970) }

    public var isActive: Bool {
        switch state {
        case .ringing, .snoozed: return true
        default: return false
        }
    }

    /// After this long past the set time, an alarm that never rang counts as missed (the app was
    /// asleep): it must not start vibrating hours late.
    public var missedAfter = 30 * 60

    public func tick(now: Int) -> [Action] {
        var out: [Action] = []
        if state == .waiting || state == .monitoring, now >= latest + missedAfter {
            state = .finished
            return [.stopLiveStream, .finished(reason: "Perdida (la app estaba dormida)")]
        }
        switch state {
        case .waiting:
            if planned.isSmart, !streamStarted, now >= earliest - streamLead {
                streamStarted = true
                out.append(.startLiveStream)
            }
            if now >= latest {
                out += ring(now: now, reason: "Hora de despertar")
            } else if planned.isSmart, now >= earliest {
                state = .monitoring
                lastSyncRequest = now
                out.append(.requestSync)
            }
        case .monitoring:
            if now >= latest {
                out += ring(now: now, reason: "Final de la ventana")
            } else if now - (lastSyncRequest ?? 0) >= syncInterval {
                lastSyncRequest = now
                out.append(.requestSync)
            }
        case .ringing(let since):
            let elapsed = Double(now - since)
            if elapsed >= ringDuration {
                if snoozeCount < planned.alarm.maxSnoozes {
                    out += snoozeActions(now: now, auto: true)
                } else {
                    state = .finished
                    out.append(.stopLiveStream)
                    out.append(.finished(reason: "Sin respuesta: suena el iPhone"))
                }
            } else {
                // Play only the latest due step: a late tick never fires a burst of buzzes.
                var k = lastPlayedIndex
                while k + 1 < ringSteps.count, ringSteps[k + 1].at <= elapsed { k += 1 }
                if k > lastPlayedIndex {
                    lastPlayedIndex = k
                    out.append(.buzz(loops: ringSteps[k].loops))
                }
            }
        case .snoozed(let until):
            if now >= until { out += ring(now: now, reason: "Fin de la repetición") }
        case .finished:
            break
        }
        return out
    }

    /// Call after each sync inside the window with the latest seconds (≥ the last hour if possible).
    public func evaluate(samples: [Sample], now: Int, sleepOnset: Int? = nil) -> [Action] {
        guard state == .monitoring else { return [] }
        let mode: SmartWake.Mode = planned.alarm.mode == .sleepGoal ? .sleepGoal(needMinutes: needMinutes ?? 480) : .window
        let onset = sleepOnset ?? SmartWake.onset(samples: samples, now: now)
        let d = SmartWake.decide(.init(now: now, earliest: earliest, latest: latest, mode: mode, samples: samples, sleepOnset: onset))
        lastDecision = d
        guard d.action == .wake else { return [] }
        wokeEarlyBy = max(0, latest - now)
        return ring(now: now, reason: d.reason)
    }

    private func ring(now: Int, reason: String) -> [Action] {
        state = .ringing(since: now)
        lastPlayedIndex = 0
        var out: [Action] = [.buzz(loops: ringSteps.first?.loops ?? 1)]
        if planned.alarm.phoneBackup {
            out.append(.backup(at: now + Int(ringDuration) + planned.alarm.phoneBackupDelay * 60))
        }
        if snoozeCount == 0 {
            out.append(.alert(title: planned.alarm.label, body: reason))
        }
        return out
    }

    private func snoozeActions(now: Int, auto: Bool) -> [Action] {
        snoozeCount += 1
        let until = now + max(1, planned.alarm.snoozeMinutes) * 60
        state = .snoozed(until: until)
        var out: [Action] = []
        if planned.alarm.phoneBackup { out.append(.backup(at: until + Int(ringDuration) + planned.alarm.phoneBackupDelay * 60)) }
        let left = planned.alarm.maxSnoozes - snoozeCount
        out.append(.alert(title: auto ? "Repetición automática" : "Pospuesta",
                          body: "Vuelvo a vibrar en \(planned.alarm.snoozeMinutes) min" + (left > 0 ? " (quedan \(left))." : " (última).")))
        return out
    }

    public func snooze(now: Int) -> [Action] {
        guard case .ringing = state else { return [] }
        guard snoozeCount < planned.alarm.maxSnoozes else { return stop(now: now) }
        return snoozeActions(now: now, auto: false)
    }

    public func stop(now: Int) -> [Action] {
        guard state != .finished else { return [] }
        let wasActive = isActive
        state = .finished
        var out: [Action] = [.stopLiveStream, .backup(at: nil)]
        out.append(.finished(reason: wasActive ? "Apagada" : "Cancelada"))
        return out
    }

    /// Double tap on the strap while this alarm is ringing or snoozed.
    public func doubleTap(now: Int) -> [Action] {
        switch state {
        case .ringing:
            return planned.alarm.doubleTap == .snooze ? snooze(now: now) : stop(now: now)
        case .snoozed:
            return stop(now: now)
        default:
            return []
        }
    }
}
