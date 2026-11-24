import SwiftUI
import PulsoStore
import PulsoFeatures
import PulsoAnalytics

// Navigation registry of the redesign.
//
// Every screen you can open is a `Route`. Each area has its own case group, defined in its own file
// (`Routes+Hoy.swift`, `Routes+Sueno.swift`, `Routes+Actividad.swift`, `Routes+Salud.swift`, `Routes+Tu.swift`), with
// the view each case opens. Metric details are `.metric(MetricKind)` and are drawn by the area that owns the metric.
//
// Open a route from anywhere inside a tab:
//   NavigationLink(value: Route.metric(.hrv)) { … }      // push (only for `.push` routes)
//   RouteLink(.sueno(.alarmas)) { … }                     // push, sheet or cover, as the route says
//   router.open(.hoy(.anadirActividad))                   // in code (`@EnvironmentObject var router: Router`)
//
// Screenshots: `-PulsoScreen r.<area>.<name>` (e.g. `r.hoy.monitor`, `r.metric.hrv`) opens the route in its tab;
// the names are the `shots` lists of each area (and `MetricKind.shots`). `tab.<hoy|sueno|actividad|salud|tu>` opens a
// tab root.

enum Route: Hashable, Identifiable {
    case hoy(HoyRoute)
    case sueno(SuenoRoute)
    case actividad(ActividadRoute)
    case salud(SaludRoute)
    case tu(TuRoute)
    case metric(MetricKind)

    var id: Self { self }

    /// The tab this route belongs to (where a screenshot or a deep link opens it).
    var tab: AppTab {
        switch self {
        case .hoy: return .hoy
        case .sueno: return .sueno
        case .actividad: return .actividad
        case .salud: return .salud
        case .tu: return .tu
        case .metric(let k): return k.tab
        }
    }

    var presentation: RoutePresentation {
        switch self {
        case .hoy(let r): return r.presentation
        case .sueno(let r): return r.presentation
        case .actividad(let r): return r.presentation
        case .salud(let r): return r.presentation
        case .tu(let r): return r.presentation
        case .metric: return .push
        }
    }

    /// Screenshot / deep-link name: "r.hoy.monitor", "r.metric.hrv".
    static func named(_ name: String) -> Route? {
        let parts = name.split(separator: ".", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "r" else { return nil }
        let key = parts[2]
        switch parts[1] {
        case "hoy": return HoyRoute.shots.first { $0.0 == key }.map { Route.hoy($0.1) }
        case "sueno": return SuenoRoute.shots.first { $0.0 == key }.map { Route.sueno($0.1) }
        case "actividad": return ActividadRoute.shots.first { $0.0 == key }.map { Route.actividad($0.1) }
        case "salud": return SaludRoute.shots.first { $0.0 == key }.map { Route.salud($0.1) }
        case "tu": return TuRoute.shots.first { $0.0 == key }.map { Route.tu($0.1) }
        case "metric": return MetricKind.shots.first { $0.0 == key }.map { Route.metric($0.1) }
        default: return nil
        }
    }

    /// Every screenshot name of the registry.
    static var shotNames: [String] {
        HoyRoute.shots.map { "r.hoy.\($0.0)" } + SuenoRoute.shots.map { "r.sueno.\($0.0)" }
            + ActividadRoute.shots.map { "r.actividad.\($0.0)" } + SaludRoute.shots.map { "r.salud.\($0.0)" }
            + TuRoute.shots.map { "r.tu.\($0.0)" } + MetricKind.shots.map { "r.metric.\($0.0)" }
    }
}

enum RoutePresentation {
    /// Pushed on the tab's NavigationStack.
    case push
    /// A sheet over the current tab.
    case sheet
    /// Full screen (pairing, guided breathing, ECG recording…).
    case cover
}

/// What each area's case group provides.
protocol AreaRoute: Hashable {
    var presentation: RoutePresentation { get }
    /// Named sample routes for the screenshot run (`r.<area>.<name>`).
    static var shots: [(String, Self)] { get }
}

// MARK: - Metric details

/// Every metric that has its own detail screen (the template in `DSMetricDetail`). The owner area draws it in its
/// `…MetricDestination`.
enum MetricKind: Hashable {
    // A · Hoy
    case recarga, esfuerzo, hrv, rhr, resp, spo2, temp, estres, edadPulso
    // B · Sueño
    case calificacion, necesidadSueno, regularidad, eficiencia, reparador, latencia, fase(SleepStage)
    // C · Actividad
    case pasos, calorias, carga, vo2max, zonas
    // D · Salud
    case ritmoEnvejecimiento
    /// One of the 8 habits of Edad Pulso (`PulsoAge.Item.key`: sleepHours, regularity, zonesLight, zonesHard, strength,
    /// steps, vo2max, rhr).
    case habito(String)
    /// One of the Análisis metrics (`MetricResult.id`: coherence, physDebt…).
    case intel(String)
    // E · Tú
    case bateria

    var area: AppTab {
        switch self {
        case .recarga, .esfuerzo, .hrv, .rhr, .resp, .spo2, .temp, .estres, .edadPulso: return .hoy
        case .calificacion, .necesidadSueno, .regularidad, .eficiencia, .reparador, .latencia, .fase: return .sueno
        case .pasos, .calorias, .carga, .vo2max, .zonas: return .actividad
        case .ritmoEnvejecimiento, .habito, .intel: return .salud
        case .bateria: return .tu
        }
    }

    var tab: AppTab { area }

    static let shots: [(String, MetricKind)] = [
        ("recarga", .recarga), ("esfuerzo", .esfuerzo), ("hrv", .hrv), ("rhr", .rhr), ("resp", .resp), ("spo2", .spo2),
        ("temp", .temp), ("estres", .estres), ("edadPulso", .edadPulso),
        ("calificacion", .calificacion), ("necesidadSueno", .necesidadSueno), ("regularidad", .regularidad),
        ("eficiencia", .eficiencia), ("reparador", .reparador), ("latencia", .latencia),
        ("faseProfundo", .fase(.deep)), ("faseREM", .fase(.rem)), ("faseLigero", .fase(.light)), ("faseDespierto", .fase(.awake)),
        ("pasos", .pasos), ("calorias", .calorias), ("carga", .carga), ("vo2max", .vo2max), ("zonas", .zonas),
        ("ritmoEnvejecimiento", .ritmoEnvejecimiento), ("habitoZonas", .habito("zonesLight")), ("habitoSueno", .habito("sleepHours")),
        ("intelCoherencia", .intel("coherence")), ("intelDeuda", .intel("physDebt")),
        ("bateria", .bateria),
    ]
}

// MARK: - Router

/// The app's navigation state: the selected tab, one path per tab, and the route shown as a sheet or full screen.
@MainActor
final class Router: ObservableObject {
    @Published var tab: AppTab = .hoy
    @Published var paths: [AppTab: [Route]] = [:]
    @Published var sheet: Route?
    @Published var cover: Route?

    func path(_ tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// Opens a route in the current tab, as its presentation says.
    func open(_ route: Route) {
        switch route.presentation {
        case .push: paths[tab, default: []].append(route)
        case .sheet: sheet = route
        case .cover: cover = route
        }
    }

    /// Switches to the route's own tab and opens it there (screenshots, notifications, deep links).
    func openInItsTab(_ route: Route) {
        tab = route.tab
        if route.presentation == .push { paths[route.tab] = [route] } else { open(route) }
    }

    /// Tapping the selected tab again goes back to its root.
    func select(_ t: AppTab) {
        if t == tab { paths[t] = [] } else { tab = t }
    }
}

/// A tappable label that opens a route the right way (push, sheet or cover).
struct RouteLink<Label: View>: View {
    @EnvironmentObject private var router: Router
    let route: Route
    @ViewBuilder var label: Label

    init(_ route: Route, @ViewBuilder label: () -> Label) {
        self.route = route
        self.label = label()
    }

    var body: some View {
        if route.presentation == .push {
            NavigationLink(value: route) { label }.buttonStyle(.plain)
        } else {
            Button { router.open(route) } label: { label }.buttonStyle(.plain)
        }
    }
}

// MARK: - Dispatch

/// The screen of a route. Each area draws its own cases (its `…Destination` view, in its `Routes+….swift` file).
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .hoy(let r): HoyDestination(route: r)
        case .sueno(let r): SuenoDestination(route: r)
        case .actividad(let r): ActividadDestination(route: r)
        case .salud(let r): SaludDestination(route: r)
        case .tu(let r): TuDestination(route: r)
        case .metric(let k):
            switch k.area {
            case .hoy: HoyMetricDestination(kind: k)
            case .sueno: SuenoMetricDestination(kind: k)
            case .actividad: ActividadMetricDestination(kind: k)
            case .salud: SaludMetricDestination(kind: k)
            case .tu: TuMetricDestination(kind: k)
            }
        }
    }
}

extension View {
    /// Registers the route destinations on a NavigationStack (every tab root and every sheet that pushes).
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { RouteView(route: $0) }
    }
}

/// A sheet / cover route. Sheet views bring their own NavigationStack when they need one (most existing sheets
/// already have it); a sheet that pushes routes adds `.routeDestinations()` to its stack.
struct PresentedRoute: View {
    let route: Route

    var body: some View {
        RouteView(route: route)
            .toggleStyle(DSSwitchStyle())
            .preferredColorScheme(.dark)
    }
}
