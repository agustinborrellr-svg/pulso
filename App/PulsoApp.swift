import SwiftUI
import Combine
import BackgroundTasks
import PulsoFeatures

@main
struct PulsoApp: App {
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    static let refreshTaskID = "es.gusborrell.pulso.refresh"

    init() {
        // A background launch (refresh task, a notification button) connects no scene, so the lazy @StateObject
        // would never build the model and its notification delegate. Deferred a turn: UIApplication is up by then.
        Task { @MainActor in _ = AppModel.shared }
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            PulsoApp.handleRefresh(task)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.appBecameActive()
                    case .background:
                        model.appEnteredBackground()
                        PulsoApp.scheduleRefresh()
                    default:
                        break
                    }
                }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Background refresh: iOS gives us ~30 s. Reconnecting is cheap (the pending connection is already
    /// armed); the strap offload + analysis then run as soon as the link is up.
    /// The work runs here and not in a view: on a cold background launch no view exists.
    static func handleRefresh(_ task: BGTask) {
        scheduleRefresh()
        Task { @MainActor in
            let model = AppModel.shared
            model.connect()
            model.syncNow()
            model.refreshAlarmSchedule()
            model.evaluateAlerts(force: false)
            model.importExternalIfDue()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var router = Router()
    @State private var showOnboarding = false
    @State private var showGuide = false
    @State private var shot: ShotScreen?

    var body: some View {
        AppTabs()
            .environmentObject(router)
            .tint(.white)
        .onAppear {
            if AppMode.screenshots {
                startScreenshots()
                return
            }
            showOnboarding = !model.hasOnboarded
            if model.hasOnboarded { model.connect() }
        }
        .onOpenURL { url in
            // Fallback for the Strava OAuth redirect if it arrives outside the auth session.
            if url.scheme == "pulso", url.path.contains("strava") {
                Task {
                    await model.strava.complete(callback: url)
                    if model.strava.connected { model.importExternalIfDue(force: true) }
                }
            }
        }
        .fullScreenCover(item: $shot) { screen in
            ShotDestination(screen: screen).environmentObject(model)
        }
        .sheet(isPresented: $showOnboarding, onDismiss: {
            // First run: the welcome screens set the strap up, the guide explains the app.
            if !UserDefaults.standard.bool(forKey: GuideView.seenKey) { showGuide = true }
        }) {
            OnboardingView { showOnboarding = false }
                .environmentObject(model)
                .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $showGuide) { GuideView() }
        .alert("Pulso", isPresented: Binding(get: { model.errorMessage != nil && !AppMode.screenshots },
                                             set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    /// CI screenshot run: demo data, then open the requested screen: a tab root (`tab.<name>`), a route
    /// (`r.<area>.<name>`, see `Route.named`) or one of the older named screens (`ShotScreen`).
    private func startScreenshots() {
        let name = AppMode.screen ?? "today"
        if let t = name.hasPrefix("tab.") ? AppTab(rawValue: String(name.dropFirst(4))) : nil {
            model.prepareScreenshots { router.tab = t }
            return
        }
        if let route = Route.named(name) {
            model.prepareScreenshots {
                // A moment for the tab's stack to appear before pushing / presenting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.openInItsTab(route) }
            }
            return
        }
        let screen = ShotScreen(rawValue: name) ?? .today
        model.prepareScreenshots {
            if let t = screen.tab {
                router.tab = t
            } else {
                shot = screen
            }
            if screen == .live {
                model.startWorkout(sport: "Carrera", plan: IntervalPlan.presets.first)
                model.setTargetZone(3)
                model.startDemoLiveFeed()
            }
            if [.scan, .coherence, .poincare, .orthostatic].contains(screen) { model.startDemoLiveFeed(resting: true) }
        }
    }
}
