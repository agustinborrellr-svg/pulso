import SwiftUI

/// The app's five tabs (Hoy · Sueño · Actividad · Salud · Tú) with the floating DS tab bar. Each tab owns a
/// NavigationStack whose path lives in the `Router`, with every `Route` registered; sheets and full-screen routes
/// are presented here.
struct AppTabs: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router

    var body: some View {
        TabView(selection: $router.tab) {
            ForEach(AppTab.allCases) { t in
                stack(t)
                    .tag(t)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .overlay(alignment: .bottom) { bar }
        .sheet(item: $router.sheet) { r in
            PresentedRoute(route: r).environmentObject(model).environmentObject(router)
        }
        .fullScreenCover(item: $router.cover) { r in
            PresentedRoute(route: r).environmentObject(model).environmentObject(router)
        }
    }

    private func stack(_ t: AppTab) -> some View {
        NavigationStack(path: router.path(t)) {
            root(t).routeDestinations()
        }
        // The content ends above the floating bar (scrolls under it).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: DSTabBar.contentInset - 34).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func root(_ t: AppTab) -> some View {
        switch t {
        case .hoy: HomeView()
        case .sueno: SleepTab()
        case .actividad: ActivityTab()
        case .salud: HealthTab(part: AppMode.screenshots && AppMode.screen == "trends" ? 1 : 0)
        case .tu: YouTab()
        }
    }

    private var bar: some View {
        GeometryReader { g in
            let bottom = g.safeAreaInsets.bottom
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                DSTabBar(selection: $router.tab) { router.select($0) }
                    .padding(.bottom, bottom > 0 ? max(bottom - 4, 8) : 12)
                    .background(alignment: .bottom) {
                        // The background fades in behind the bar so content scrolls away under it.
                        LinearGradient(stops: [.init(color: DS.bg.opacity(0), location: 0), .init(color: DS.bg, location: 0.62)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: DSTabBar.height + 42 + bottom)
                            .allowsHitTesting(false)
                    }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(.keyboard)
    }
}
