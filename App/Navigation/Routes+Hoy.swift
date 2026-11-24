import SwiftUI
import PulsoStore
import PulsoFeatures
import PulsoAnalytics

// A · Hoy drill-downs (studio APP/A-hoy, mapa.md). Owned by the Hoy area: add cases here, map them in
// `HoyDestination`, list them in `shots` for the screenshot run (`-PulsoScreen r.hoy.<name>`).
// Metric details of this area (`.metric(.recarga …)`) are drawn in `HoyMetricDestination`.

enum HoyRoute: AreaRoute {
    /// 03 Monitor de salud (04 = same screen with a vital out of range).
    case monitor
    /// 11 Tendencias de tu cuerpo.
    case tendencias
    /// 13 Detalle de entreno (start time; nil = the latest workout).
    case workout(start: Int?)
    /// 14 Actividades del día (day key; nil = the selected day).
    case actividadesDia(day: String?)
    /// 15 Agregar actividad (sheet).
    case anadirActividad
    /// 16 Elegir actividad.
    case elegirActividad
    /// 17 Iniciar actividad (sheet).
    case iniciarActividad
    /// 18 Calendario y récords.
    case calendario

    var presentation: RoutePresentation {
        switch self {
        case .anadirActividad, .iniciarActividad: return .sheet
        default: return .push
        }
    }

    static let shots: [(String, HoyRoute)] = [
        ("monitor", .monitor), ("tendencias", .tendencias), ("workout", .workout(start: nil)),
        ("actividadesDia", .actividadesDia(day: nil)), ("anadirActividad", .anadirActividad),
        ("elegirActividad", .elegirActividad), ("iniciarActividad", .iniciarActividad), ("calendario", .calendario),
    ]
}

struct HoyDestination: View {
    @EnvironmentObject var model: AppModel
    let route: HoyRoute

    var body: some View {
        switch route {
        case .monitor:
            HoyMonitorView()
        case .tendencias:
            HoyTendenciasView()
        case .workout(let start):
            if let w = workout(start) {
                HoyWorkoutView(workout: w).id(w.start)
            } else {
                DSScreen("Entreno", back: "Hoy") {
                    DSEmptyState(icon: "figure.run", title: "Sin entrenos", message: "Aún no hay ningún entreno guardado.")
                }
            }
        case .actividadesDia(let key):
            if let d = key.flatMap({ model.day($0) }) ?? model.selected {
                HoyActividadesDiaView(day: d)
            } else {
                DSScreen("Actividades", back: "Hoy") {
                    DSEmptyState(icon: "calendar", title: "Sin datos este día")
                }
            }
        case .anadirActividad:
            AddActivitySheet()
        case .elegirActividad:
            ActivityPickerView(selection: .constant(nil))
        case .iniciarActividad:
            HoyStartActivitySheet()
        case .calendario:
            HoyCalendarOpener()
        }
    }

    private func workout(_ start: Int?) -> Workout? {
        let all = model.days.reversed().lazy.flatMap { model.workouts(for: $0) }
        if let start { return all.first { $0.start == start } }
        // The latest real workout (not a breathing session).
        return all.first { !Breathwork.activityNames.contains($0.sport) } ?? all.first
    }
}

/// 18 Calendario: the month drops down from Hoy's day pill, so the route goes back to Hoy and opens it there.
struct HoyCalendarOpener: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router

    var body: some View {
        Color.clear.dsBackground()
            .onAppear {
                router.paths[.hoy] = []
                withAnimation(.easeInOut(duration: 0.28)) { model.showDayPicker = true }
            }
    }
}

struct HoyMetricDestination: View {
    let kind: MetricKind

    var body: some View {
        switch kind {
        case .recarga:
            HoyRecargaView()
        case .esfuerzo:
            HoyEsfuerzoView()
        case .hrv, .rhr, .resp, .spo2, .temp:
            HoyVitalDetail(id: HoyVital.id(kind))
        case .estres:
            HoyEstresView()
        case .edadPulso:
            HoyEdadPulsoView()
        default:
            EmptyView()
        }
    }
}
