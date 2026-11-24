import SwiftUI
import PulsoStore

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
    @Environment(\.dismiss) private var dismiss
    let route: HoyRoute

    var body: some View {
        switch route {
        case .monitor:
            HealthMonitorView()
        case .tendencias:
            TrendsView(initialMode: 0)
        case .workout(let start):
            if let w = workout(start) {
                WorkoutDetailView(workout: w)
            } else {
                DSScreen("Entreno", back: "Hoy") {
                    DSEmptyState(icon: "figure.run", title: "Sin entrenos", message: "Aún no hay ningún entreno guardado.")
                }
            }
        case .actividadesDia(let key):
            if let d = key.flatMap({ model.day($0) }) ?? model.selected {
                DayActivitiesView(day: d)
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
            StartActivitySheet(isPresented: Binding(get: { true }, set: { if !$0 { dismiss() } }))
        case .calendario:
            CalendarRecordsView()
        }
    }

    private func workout(_ start: Int?) -> Workout? {
        let all = model.days.reversed().lazy.flatMap { model.workouts(for: $0) }
        if let start { return all.first { $0.start == start } }
        return all.first
    }
}

struct HoyMetricDestination: View {
    let kind: MetricKind

    var body: some View {
        switch kind {
        case .recarga:
            DSTrendMetricDetail(metric: .recovery, title: "Recarga", back: "Hoy", color: DS.recarga, score: true, yDomain: 0...100)
        case .esfuerzo:
            DSTrendMetricDetail(metric: .strain, title: "Esfuerzo", back: "Hoy", color: DS.act, yDomain: 0...21)
        case .hrv:
            DSTrendMetricDetail(metric: .hrv, title: "VFC", back: "Monitor", color: DS.cor, night: true)
        case .rhr:
            DSTrendMetricDetail(metric: .rhr, title: "FC en reposo", back: "Monitor", color: DS.cor, night: true)
        case .resp:
            DSTrendMetricDetail(metric: .respRate, title: "Respiración", back: "Monitor", color: DS.cons, night: true)
        case .spo2:
            DSTrendMetricDetail(metric: .spo2, title: "SpO₂", back: "Monitor", color: DS.cons, night: true)
        case .temp:
            DSTrendMetricDetail(metric: .skinTemp, title: "Temp. piel", back: "Monitor", color: DS.cons, night: true)
        case .estres:
            DSTrendMetricDetail(metric: .stress, title: "Estrés", back: "Hoy", color: DS.bien, yDomain: 0...3)
        case .edadPulso:
            PulsoAgeDetailView()
        default:
            EmptyView()
        }
    }
}
