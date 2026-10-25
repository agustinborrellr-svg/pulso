import SwiftUI
import Combine
import BackgroundTasks

@main
struct PulsoApp: App {
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    static let refreshTaskID = "es.gusborrell.pulso.refresh"

    init() {
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
    static func handleRefresh(_ task: BGTask) {
        scheduleRefresh()
        NotificationCenter.default.post(name: .pulsoBackgroundRefresh, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }
}

extension Notification.Name {
    static let pulsoBackgroundRefresh = Notification.Name("pulso.background.refresh")
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = 0
    @State private var showOnboarding = false

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Hoy", systemImage: "circle.circle") }
                .tag(0)
            SleepView()
                .tabItem { Label("Sueño", systemImage: "moon.zzz") }
                .tag(1)
            TrendsView()
                .tabItem { Label("Tendencias", systemImage: "chart.xyaxis.line") }
                .tag(2)
            LiveView()
                .tabItem { Label("En vivo", systemImage: "heart.text.square") }
                .tag(3)
            MoreView()
                .tabItem { Label("Más", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(.white)
        .onAppear {
            showOnboarding = !model.hasOnboarded
            if model.hasOnboarded { model.connect() }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }
                .environmentObject(model)
                .interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pulsoBackgroundRefresh)) { _ in
            model.connect()
            model.syncNow()
            model.refreshAlarmSchedule()
            model.evaluateAlerts(force: false)
            model.importExternalIfDue()
        }
        .alert("Pulso", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
