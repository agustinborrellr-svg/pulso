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
    case scan, coherence, poincare, orthostatic, explorer, calendar, monthly, storage, monitor
    case behaviors, cycle, pressure, doubleTap, trendHRV6M, trendsList
    case liveIdle, vitals, vitalDetail, startActivity, intelToday, intelLoad, intelSleep, intelHabits, intelMore
    case breathDetail, breathPrep, breathSession, breathResult
    case todayScrolled, healthMonitor, panelHRV, panelTemp, panelSpO2, activityPicker, dayActivities, report1, report2, report3, report4

    var id: String { rawValue }

    var tab: Int? {
        switch self {
        case .today, .todayScrolled: return 0
        case .health: return 1
        case .trends: return 2
        case .live, .liveIdle: return 3
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
        if cycleStarts.isEmpty { addCycleStart(DayKey.shift(DayKey.string(Date()), days: -19)) }
        if bloodPressure.isEmpty {
            let now = Int(Date().timeIntervalSince1970)
            for (i, v) in [(118, 78), (122, 80), (116, 76), (125, 82), (130, 84), (121, 79), (119, 77)].enumerated() {
                addBloodPressure(BloodPressureReading(ts: now - (6 - i) * 86400 - 3600, systolic: v.0, diastolic: v.1, pulse: 64))
            }
        }
        charging = false
        if breathworkRecords.isEmpty { saveBreathwork(Self.demoBreathwork()) }
        let finish = {
            try? Data("ok".utf8).write(to: AppMode.readyFlagURL)
            if let extra = ProcessInfo.processInfo.environment["PULSO_READY_PATH"] {
                try? Data("ok".utf8).write(to: URL(fileURLWithPath: extra))
            }
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

extension AppModel {
    /// A plausible alertness session two hours ago, for the screenshots.
    static func demoBreathwork() -> Breathwork.Summary {
        let end = Int(Date().timeIntervalSince1970) - 7200
        let start = end - 288
        let hr = (0..<58).map { i in 62 + 12 * sin(Double(i) / 4) * (i % 19 < 12 ? 1 : 0.3) }
        let stress = (0..<17).map { i in 0.4 + 0.03 * Double(i) - (i > 14 ? 0.1 : 0) }
        return Breathwork.Summary(kind: .alert, start: start, end: end, inhaleSeconds: 144, exhaleSeconds: 101, holdSeconds: 42,
                                  retentions: [21, 38, 52], hrMin: 54, hrAvg: 61, hrMax: 79, stressBefore: 0.4, stressAfter: 0.6,
                                  rmssdBefore: 58, rmssdAfter: 49, hrSeries: hr, stressSeries: stress)
    }
}

/// A vital's panel over the health monitor, as after tapping its tile.
struct ShotVitalPanel: View {
    @EnvironmentObject var model: AppModel
    let id: String

    var body: some View {
        ZStack {
            HealthMonitorView()
            if let r = model.vitalReadings().first(where: { $0.id == id }) {
                VitalPanel(reading: r, close: {}, trends: {})
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// One page of the health report PDF, fitted to the screen width.
struct ShotReportPage: View {
    @EnvironmentObject var model: AppModel
    let screen: ShotScreen

    var body: some View {
        let kinds: [ShotScreen: HealthReportPage.Kind] = [.report1: .summary, .report2: .recent, .report3: .months, .report4: .monthsMore]
        GeometryReader { g in
            HealthReportPage(report: model.healthReport(), profile: model.profile, kind: kinds[screen] ?? .summary)
                .frame(width: HealthReportPDF.page.width, height: HealthReportPDF.page.height)
                .scaleEffect(g.size.width / HealthReportPDF.page.width, anchor: .topLeading)
                .environment(\.colorScheme, .light)
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
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
                case .behaviors: BehaviorsView()
                case .trendsList: TrendsView(initialMode: 0)
                case .cycle: CycleCalendarView()
                case .pressure: BloodPressureView()
                case .doubleTap: DoubleTapView()
                case .trendHRV6M: TrendDetailView(metric: .hrv, initialPeriod: .halfYear)
                case .monitor: MonitorView()
                case .vitals: VitalsView()
                case .vitalDetail: VitalDetailView(id: "hrv")
                case .startActivity: StartActivityPreview()
                case .healthMonitor: HealthMonitorView()
                case .breathDetail: BreathworkDetailView(kind: .alert)
                case .breathPrep: BreathworkPrepView(kind: .alert, settings: .init(breaths: 30, rounds: 3))
                case .breathSession: BreathworkSessionView(kind: .alert, settings: .init(breaths: 30, rounds: 3), completed: .constant(false))
                case .breathResult: BreathworkResultView(record: model.breathworkRecords.last ?? BreathworkRecord(summary: AppModel.demoBreathwork()))
                case .panelHRV: ShotVitalPanel(id: "hrv")
                case .panelTemp: ShotVitalPanel(id: "temp")
                case .panelSpO2: ShotVitalPanel(id: "spo2")
                case .activityPicker: ActivityPickerView(selection: .constant(nil))
                case .dayActivities:
                    if let d = model.today { DayActivitiesView(day: d) } else { Text("Sin datos") }
                case .report1, .report2, .report3, .report4: ShotReportPage(screen: screen)
                case .intelToday: IntelTodayView()
                case .intelLoad: IntelSectionView(title: "Respuesta a la carga")
                case .intelSleep: IntelSectionView(title: "Sueño y ritmo")
                case .intelHabits: IntelSectionView(title: "Hábitos y predicción")
                case .intelMore: IntelMoreView()
                case .intelDetail:
                    if let m = model.intelligence?.metric("forecast") { MetricDetailView(metric: m) } else { Text("Calculando…") }
                default: EmptyView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
