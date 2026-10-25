import Foundation
import PulsoStore
import PulsoAnalytics

public enum AlertKind: String, Codable, CaseIterable, Sendable {
    case morningReport, bedtime, caffeine, illness, trend, batteryLow, offWrist, syncStale
    case strainReached, overreaching, inactivity, stress, weekly

    public var label: String {
        switch self {
        case .morningReport: return "Informe al despertar"
        case .bedtime: return "Hora de acostarse"
        case .caffeine: return "Última cafeína"
        case .illness: return "Posible enfermedad"
        case .trend: return "Tendencias (VFC, FC, deuda)"
        case .batteryLow: return "Batería baja"
        case .offWrist: return "Pulsera fuera de la muñeca"
        case .syncStale: return "Sin sincronizar"
        case .strainReached: return "Objetivo de esfuerzo"
        case .overreaching: return "Te estás pasando"
        case .inactivity: return "Mucho rato quieto"
        case .stress: return "Estrés alto"
        case .weekly: return "Resumen semanal"
        }
    }

    public var icon: String {
        switch self {
        case .morningReport: return "sunrise"
        case .bedtime: return "bed.double"
        case .caffeine: return "cup.and.saucer"
        case .illness: return "thermometer.medium"
        case .trend: return "chart.line.downtrend.xyaxis"
        case .batteryLow: return "battery.25"
        case .offWrist: return "hand.raised"
        case .syncStale: return "arrow.triangle.2.circlepath"
        case .strainReached: return "target"
        case .overreaching: return "exclamationmark.triangle"
        case .inactivity: return "figure.walk"
        case .stress: return "wind"
        case .weekly: return "calendar"
        }
    }

    /// Can wait until the end of quiet hours.
    var deferrable: Bool {
        switch self {
        case .morningReport, .bedtime, .caffeine: return false
        default: return true
        }
    }
}

/// What the user wants to be told, and how.
public struct AlertPreferences: Codable, Equatable, Sendable {
    public var enabled: [AlertKind: Bool]
    /// Kinds that also vibrate the strap.
    public var strapBuzz: [AlertKind: Bool]
    public var bedtimeLeadMinutes: Int
    public var offWristMinutes: Int
    public var inactivityMinutes: Int
    public var batteryThreshold: Int
    /// Quiet hours in minutes after midnight (start > end wraps midnight).
    public var quietStart: Int
    public var quietEnd: Int

    public static let defaultEnabled: [AlertKind: Bool] = [
        .morningReport: true, .bedtime: true, .caffeine: false, .illness: true, .trend: true, .batteryLow: true,
        .offWrist: true, .syncStale: true, .strainReached: true, .overreaching: true, .inactivity: false,
        .stress: true, .weekly: true,
    ]
    public static let defaultBuzz: [AlertKind: Bool] = [.inactivity: true, .stress: true, .bedtime: true]

    public init() {
        enabled = Self.defaultEnabled
        strapBuzz = Self.defaultBuzz
        bedtimeLeadMinutes = 30
        offWristMinutes = 60
        inactivityMinutes = 60
        batteryThreshold = 20
        quietStart = 23 * 60
        quietEnd = 7 * 60
    }

    public func isOn(_ k: AlertKind) -> Bool { enabled[k] ?? Self.defaultEnabled[k] ?? false }
    public func buzzes(_ k: AlertKind) -> Bool { strapBuzz[k] ?? false }

    private enum CodingKeys: String, CodingKey {
        case enabled, strapBuzz, bedtimeLeadMinutes, offWristMinutes, inactivityMinutes, batteryThreshold, quietStart, quietEnd
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertPreferences()
        func kinds(_ k: CodingKeys) throws -> [AlertKind: Bool]? {
            guard let raw = try c.decodeIfPresent([String: Bool].self, forKey: k) else { return nil }
            var out: [AlertKind: Bool] = [:]
            for (key, v) in raw { if let kind = AlertKind(rawValue: key) { out[kind] = v } }
            return out
        }
        enabled = try kinds(.enabled) ?? d.enabled
        strapBuzz = try kinds(.strapBuzz) ?? d.strapBuzz
        bedtimeLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .bedtimeLeadMinutes) ?? d.bedtimeLeadMinutes
        offWristMinutes = try c.decodeIfPresent(Int.self, forKey: .offWristMinutes) ?? d.offWristMinutes
        inactivityMinutes = try c.decodeIfPresent(Int.self, forKey: .inactivityMinutes) ?? d.inactivityMinutes
        batteryThreshold = try c.decodeIfPresent(Int.self, forKey: .batteryThreshold) ?? d.batteryThreshold
        quietStart = try c.decodeIfPresent(Int.self, forKey: .quietStart) ?? d.quietStart
        quietEnd = try c.decodeIfPresent(Int.self, forKey: .quietEnd) ?? d.quietEnd
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Dictionary(uniqueKeysWithValues: enabled.map { ($0.key.rawValue, $0.value) }), forKey: .enabled)
        try c.encode(Dictionary(uniqueKeysWithValues: strapBuzz.map { ($0.key.rawValue, $0.value) }), forKey: .strapBuzz)
        try c.encode(bedtimeLeadMinutes, forKey: .bedtimeLeadMinutes)
        try c.encode(offWristMinutes, forKey: .offWristMinutes)
        try c.encode(inactivityMinutes, forKey: .inactivityMinutes)
        try c.encode(batteryThreshold, forKey: .batteryThreshold)
        try c.encode(quietStart, forKey: .quietStart)
        try c.encode(quietEnd, forKey: .quietEnd)
    }

    public func isQuiet(minuteOfDay m: Int) -> Bool {
        if quietStart == quietEnd { return false }
        return quietStart < quietEnd ? (m >= quietStart && m < quietEnd) : (m >= quietStart || m < quietEnd)
    }
}

/// A notification to deliver now (`fireAt == nil`) or schedule.
public struct PlannedAlert: Equatable, Sendable, Identifiable {
    /// Stable key: the same alert is never delivered twice (e.g. "morning.2026-10-25").
    public var id: String
    public var kind: AlertKind
    public var title: String
    public var body: String
    public var fireAt: Int?
    public var buzzStrap: Bool
    public var timeSensitive: Bool

    public init(id: String, kind: AlertKind, title: String, body: String, fireAt: Int?, buzzStrap: Bool, timeSensitive: Bool) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.fireAt = fireAt
        self.buzzStrap = buzzStrap
        self.timeSensitive = timeSensitive
    }
}

/// Everything the rules look at.
public struct AlertContext {
    public var now: Int
    public var calendar: Calendar
    /// Daily summaries, oldest first (at least the last ~3 weeks for baselines).
    public var days: [DaySummary]
    public var profile: Profile
    public var battery: Double?
    public var charging: Bool?
    public var lastSync: Int?
    /// Since when the strap has been off the wrist (nil = on the wrist / unknown).
    public var offWristSince: Int?
    /// Next wake time (from the alarms, else the usual one).
    public var nextWake: Int?
    /// Raw seconds of the last ~2 hours (inactivity); may be empty.
    public var recentSamples: [Sample]

    public init(now: Int, calendar: Calendar = .current, days: [DaySummary], profile: Profile, battery: Double? = nil,
                charging: Bool? = nil, lastSync: Int? = nil, offWristSince: Int? = nil, nextWake: Int? = nil,
                recentSamples: [Sample] = []) {
        self.now = now
        self.calendar = calendar
        self.days = days
        self.profile = profile
        self.battery = battery
        self.charging = charging
        self.lastSync = lastSync
        self.offWristSince = offWristSince
        self.nextWake = nextWake
        self.recentSamples = recentSamples
    }
}

public enum AlertEngine {
    static func hm(_ minutes: Double) -> String {
        let t = Int(minutes.rounded())
        return "\(t / 60) h \(String(format: "%02d", t % 60)) min"
    }

    static func clock(_ ts: Int, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// The alerts that should go out (or be scheduled) now. `sent` holds the ids already delivered.
    public static func evaluate(_ ctx: AlertContext, prefs: AlertPreferences, sent: Set<String>) -> [PlannedAlert] {
        var out: [PlannedAlert] = []
        let cal = ctx.calendar
        let nowDate = Date(timeIntervalSince1970: TimeInterval(ctx.now))
        let todayKey = DayKey.string(nowDate, calendar: cal)
        let minuteOfDay = SleepCoach.minutesAfterMidnight(ts: ctx.now, calendar: cal)
        let days = ctx.days.sorted { $0.day < $1.day }
        let today = days.last { $0.day == todayKey }
        let history = days.filter { $0.day < todayKey }

        func add(_ kind: AlertKind, _ id: String, _ title: String, _ body: String, at: Int? = nil, timeSensitive: Bool = false) {
            guard prefs.isOn(kind), !sent.contains(id), !out.contains(where: { $0.id == id }) else { return }
            var fire = at
            // Non-urgent alerts wait for the end of quiet hours.
            if kind.deferrable, !timeSensitive {
                let t = at ?? ctx.now
                let m = Int(SleepCoach.minutesAfterMidnight(ts: t, calendar: cal))
                if prefs.isQuiet(minuteOfDay: m) {
                    let end = cal.nextDate(after: Date(timeIntervalSince1970: TimeInterval(t)),
                                           matching: DateComponents(hour: prefs.quietEnd / 60, minute: prefs.quietEnd % 60),
                                           matchingPolicy: .nextTime)
                    fire = end.map { Int($0.timeIntervalSince1970) }
                }
            }
            out.append(PlannedAlert(id: id, kind: kind, title: title, body: body, fireAt: fire,
                                    buzzStrap: prefs.buzzes(kind), timeSensitive: timeSensitive))
        }

        let health = today.map { HealthMonitor.assess($0, history: history) }
        let load = TrainingLoad.series(days, through: todayKey, calendar: cal)
        let advice = DailyCoach.advice(recovery: today?.recovery, load: load, health: health,
                                       sleepDebtMinutes: today?.sleepDebtMinutes)

        // Morning report: once the night is analysed, within 6 h of waking.
        if let d = today, let wake = d.sleepEnd, ctx.now - wake < 6 * 3600, ctx.now >= wake {
            var parts: [String] = []
            if let r = d.recovery { parts.append("Recuperación \(Int(r)) %") }
            else if d.calibrating { parts.append("Recuperación calibrando") }
            if let s = d.sleepMinutes {
                parts.append("dormiste \(hm(s))" + (d.sleepPerformance.map { " (\(Int(($0 * 100).rounded())) %)" } ?? ""))
            }
            if d.recovery != nil {
                parts.append("esfuerzo recomendado \(Int(advice.strainTarget.lowerBound))–\(Int(advice.strainTarget.upperBound))")
            }
            var body = parts.joined(separator: " · ")
            if let h = health, h.level == .watch { body += ". " + h.message }
            if !parts.isEmpty {
                add(.morningReport, "morning.\(d.day)", advice.headline, body)
            }
        }

        // Illness early warning.
        if let h = health, h.level == .alert {
            add(.illness, "illness.\(h.day)", h.title, h.message, timeSensitive: true)
        }

        // Multi-day trends, in the morning.
        if minuteOfDay >= 6 * 60, minuteOfDay < 13 * 60 {
            for s in HealthMonitor.trends(days) {
                add(.trend, "trend.\(s.key).\(todayKey)", "Ojo con la tendencia", s.detail.prefix(1).uppercased() + s.detail.dropFirst() + ".")
            }
        }

        // Bedtime (scheduled) and caffeine cut-off.
        if let wake = ctx.nextWake, wake > ctx.now {
            let need = SleepPlanner.tonightNeed(profile: ctx.profile, today: today, recent: days)
            let plan = SleepPlanner.plan(wake: Date(timeIntervalSince1970: TimeInterval(wake)), needMinutes: need, recent: days)
            let bed = Int(plan.bedtime.timeIntervalSince1970)
            let remind = bed - prefs.bedtimeLeadMinutes * 60
            let bedKey = DayKey.string(plan.bedtime, calendar: cal)
            if remind > ctx.now, remind - ctx.now < 20 * 3600 {
                var body = "Para dormir \(hm(need)) y despertar a las \(clock(wake, cal)), acuéstate a las \(clock(bed, cal))."
                if let b = ctx.battery, b < 35, ctx.charging != true {
                    body += " Carga antes la pulsera (\(Int(b)) %)."
                }
                add(.bedtime, "bedtime.\(bedKey)", "Prepárate para dormir", body, at: remind)
            }
            let caffeine = Int(plan.caffeineCutoff.timeIntervalSince1970)
            if caffeine > ctx.now, caffeine - ctx.now < 20 * 3600 {
                add(.caffeine, "caffeine.\(bedKey)", "Última cafeína",
                    "Si quieres acostarte a las \(clock(bed, cal)), mejor no tomes más cafeína a partir de ahora.", at: caffeine)
            }
        }

        // Battery.
        if let b = ctx.battery, ctx.charging != true, Int(b) < prefs.batteryThreshold {
            let bucket = b < 5 ? 5 : (b < 10 ? 10 : prefs.batteryThreshold)
            add(.batteryLow, "battery.\(todayKey).\(bucket)", "Batería baja de la pulsera",
                "Queda un \(Int(b)) %. Conecta el cargador para no perder datos.")
        }

        // Off the wrist for a while (scheduled when it was taken off; the app cancels it on wrist-on).
        if let since = ctx.offWristSince, ctx.charging != true {
            add(.offWrist, "offwrist.\(since)", "La pulsera no está en tu muñeca",
                "Lleva \(prefs.offWristMinutes) min sin datos. Póntela para no perder tu esfuerzo y tu sueño.",
                at: max(ctx.now, since + prefs.offWristMinutes * 60))
        }

        // No sync for a day (scheduled from the last sync; rescheduled on every sync).
        if let last = ctx.lastSync {
            add(.syncStale, "stale.\(last)", "Pulso no sincroniza desde hace un día",
                "Abre la app con la pulsera cerca para descargar tus datos.", at: max(ctx.now, last + 24 * 3600))
        }

        // Strain target reached / overreaching (only with a recovery to compare against).
        if let d = today, d.recovery != nil, let strain = d.strain, minuteOfDay < 22 * 60 {
            if strain >= advice.strainTarget.upperBound + 1.5, let r = d.recovery, r < 67 {
                add(.overreaching, "over.\(d.day)", "Te estás pasando hoy",
                    String(format: "Esfuerzo %.1f con una recuperación del %d %%. Mejor parar aquí.", strain, Int(r)))
            } else if strain >= advice.strainTarget.lowerBound {
                add(.strainReached, "strain.\(d.day)", "Objetivo de esfuerzo conseguido",
                    String(format: "Llevas %.1f (objetivo %d–%d).", strain, Int(advice.strainTarget.lowerBound), Int(advice.strainTarget.upperBound)))
            }
        }

        // Inactivity: awake, worn, still and no steps for the configured time.
        if !ctx.recentSamples.isEmpty, !prefs.isQuiet(minuteOfDay: Int(minuteOfDay)) {
            let span = prefs.inactivityMinutes * 60
            let window = ctx.recentSamples.filter { $0.ts >= ctx.now - span && $0.ts < ctx.now }
            let covered = window.count >= Int(Double(span) * 0.8)
            let worn = window.filter { $0.worn }
            let asleep = window.filter { $0.sleepState == 2 }.count > window.count / 3
            if covered, worn.count >= Int(Double(window.count) * 0.9), !asleep {
                let steps = worn.compactMap { $0.steps }
                let stepDelta = steps.count >= 2 ? (steps.last! - steps.first! + 65536) % 65536 : 0
                let moving = worn.filter { ($0.dyn ?? 0) > 0.12 }.count
                if stepDelta < 30, moving < worn.count / 20 {
                    let hourKey = "\(todayKey).\(Int(minuteOfDay) / 60)"
                    add(.inactivity, "inactive.\(hourKey)", "Llevas \(prefs.inactivityMinutes) min quieto",
                        "Levántate y camina un par de minutos.")
                }
            }
        }

        // Sustained stress this hour and the last.
        if let d = today, d.stressHourly.count == 24 {
            let h = Int(minuteOfDay) / 60
            if h >= 1, let a = d.stressHourly[h - 1], let b = d.stressHourly[h], a >= 2, b >= 2 {
                add(.stress, "stress.\(d.day).\(h)", "Estrés alto un buen rato",
                    "Tu pulso y tu VFC llevan más de una hora en modo estrés. Prueba 2 minutos de respiración guiada.")
            }
        }

        // Weekly summary on Monday mornings.
        if cal.component(.weekday, from: nowDate) == 2, minuteOfDay >= 8 * 60, minuteOfDay < 14 * 60 {
            let s = WeeklySummary.compute(days, endDay: DayKey.shift(todayKey, days: -1, calendar: cal), calendar: cal)
            if s.recovery != nil || s.sleepMinutes != nil {
                add(.weekly, "weekly.\(todayKey)", "Tu semana", s.text.prefix(1).uppercased() + s.text.dropFirst() + ".")
            }
        }
        return out
    }
}
