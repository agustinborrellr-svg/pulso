import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntelligence

/// Screens the CI screenshot run can open with `-PulsoScreen <name>`.
enum ShotScreen: String, Identifiable {
    case today, health, sleep, trends, live, more
    case alarms, alarmEditor, notifications, integrations, ecg, ecgDetail, bedtime, lab, workout, onboarding, whatif, intelDetail
    case guide, guideData, guideRecovery, guideAlarm, whoopImport
    case recovery, strain, stress, trendRecovery, trendStrain, trendHRV, device, pairing, deviceAdvanced
    case sleepQuestion, vo2, plan, addActivity
    case scan, coherence, poincare, orthostatic, explorer, calendar, monthly, storage

    var id: String { rawValue }

    var tab: Int? {
        switch self {
        case .today: return 0
        case .health: return 1
        case .trends: return 2
        case .live: return 3
        case .more: return 4
        default: return nil
        }
    }
}

extension AppModel {
    /// Demo data, sample alarms and a ready flag for the screenshot script.
    func prepareScreenshots(_ done: @escaping () -> Void) {
        hasOnboarded = true
        if planGoals.isEmpty {
            savePlan([PlanGoal(kind: .zonesLight, target: 150), PlanGoal(kind: .zonesHard, target: 30),
                      PlanGoal(kind: .sleepHours, target: 8 * 60), PlanGoal(kind: .steps, target: 8000),
                      PlanGoal(kind: .habitNo, target: 1, habit: "alcohol"), PlanGoal(kind: .habitYes, target: 4, habit: "meditation")])
        }
        if alarms.isEmpty {
            alarms = [
                AlarmConfig(id: "shot-1", label: "Trabajo", hour: 7, minute: 15, weekdays: [2, 3, 4, 5, 6], mode: .smart, windowMinutes: 30,
                            dayTimes: [2: 6 * 60 + 45, 3: 7 * 60 + 15, 4: 7 * 60 + 15, 5: 7 * 60 + 15, 6: 8 * 60]),
                AlarmConfig(id: "shot-2", enabled: false, label: "Fin de semana", hour: 9, minute: 30, weekdays: [1, 7], mode: .sleepGoal,
                            windowMinutes: 45, vibration: .gentle),
            ]
            try? db.set(alarms, for: "alarms")
            refreshAlarmSchedule()
        }
        battery = 72
        charging = false
        let finish = {
            try? Data("ok".utf8).write(to: AppMode.readyFlagURL)
            done()
        }
        if (try? db.hasSamples()) == true {
            reload()
            finish()
        } else {
            loadDemo(days: 35) { finish() }
        }
    }

    /// Feeds a plausible live heart rate (for the live-screen screenshots). `resting`: seated and breathing
    /// slowly, with five minutes of beats already in, so the scan, Poincaré and coherence have something to show.
    func startDemoLiveFeed(resting: Bool = false) {
        func rr(at s: Double) -> Double {
            resting ? 880 + 70 * sin(2 * .pi * 6 / 60 * s) + Double.random(in: -12...12) : 60000 / (152 + 12 * sin(s / 25))
        }
        let now = Date().timeIntervalSince1970
        if resting {
            var t = now - 300
            while t < now {
                let v = rr(at: t)
                t += v / 1000
                liveBeats.append(.init(t: t, rr: v))
            }
        }
        if resting && liveTests.isEmpty {
            saveLiveTest(LiveTestRecord(date: Date().addingTimeInterval(-86400 * 2), kind: .scan, value: 64, hr: 71, rmssd: 38, resp: 14.2, stress: 1.1, detail: "Algo activado"))
            saveLiveTest(LiveTestRecord(date: Date().addingTimeInterval(-86400), kind: .scan, value: 82, hr: 66, rmssd: 52, resp: 13.1, stress: 0.5, detail: "En calma"))
            saveLiveTest(LiveTestRecord(date: Date().addingTimeInterval(-3600 * 20), kind: .orthostatic, value: 17, hr: 79, rmssd: 31, detail: "62→79 lpm"))
        }
        var clock = now
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var beats: [Int] = []
                let end = Date().timeIntervalSince1970
                while clock < end {
                    let v = rr(at: clock)
                    clock += v / 1000
                    beats.append(Int(v))
                }
                let hr = Int(60000 / Double(max(1, beats.last ?? 800)))
                self.handleLive(heartRate: hr, rr: beats, at: Date())
            }
        }
    }
}

/// Sub-screens opened full-screen in screenshot mode.
struct ShotDestination: View {
    @EnvironmentObject var model: AppModel
    let screen: ShotScreen

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .alarms: AlarmsView()
                case .alarmEditor: AlarmEditor(alarm: model.alarms.first ?? AlarmConfig())
                case .notifications: NotificationsView()
                case .integrations: IntegrationsView(strava: model.strava)
                case .ecg: ECGListView()
                case .ecgDetail:
                    if let r = model.ecgRecordings.first { ECGDetailView(recording: r) } else { ECGListView() }
                case .bedtime: BedtimeView()
                case .lab: LabView()
                case .workout:
                    if let w = model.days.reversed().lazy.flatMap({ self.model.workouts(for: $0) }).first {
                        WorkoutDetailView(workout: w)
                    } else {
                        Text("Sin entrenos")
                    }
                case .onboarding: OnboardingView {}
                case .guide: GuideView()
                case .guideData: GuideView(startPage: 1)
                case .guideRecovery: GuideView(startPage: 3)
                case .guideAlarm: GuideView(startPage: 8)
                case .whoopImport: WhoopImportView()
                case .sleep: SleepDetailView()
                case .recovery: RecoveryDetailView()
                case .strain: StrainDetailView()
                case .stress: StressMonitorView()
                case .trendRecovery: TrendDetailView(metric: .recovery)
                case .trendStrain: TrendDetailView(metric: .strain)
                case .trendHRV: TrendDetailView(metric: .hrv)
                case .device, .deviceAdvanced: DeviceView()
                case .pairing: PairingFlowView()
                case .vo2: VO2MaxView()
                case .plan: WeeklyPlanView()
                case .addActivity: AddActivitySheet()
                case .sleepQuestion:
                    let now = Int(Date().timeIntervalSince1970)
                    DetailScreen(title: "Inicio") {
                        SleepQuestionCard(session: SleepSession(start: now - 2 * 3600, end: now - 3600 - 600, isNap: true,
                                                                minutesAwake: 4, minutesLight: 38, minutesDeep: 8))
                    }
                case .whatif: WhatIfView()
                case .scan: ScanView()
                case .coherence: CoherenceView()
                case .poincare: PoincareView()
                case .orthostatic: OrthostaticTestView()
                case .explorer: RelationExplorerView()
                case .calendar: CalendarRecordsView()
                case .monthly: MonthlyReportView()
                case .storage: StorageView()
                case .intelDetail:
                    if let m = model.intelligence?.metric("forecast") { MetricDetailView(metric: m) } else { Text("Calculando…") }
                default: EmptyView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
