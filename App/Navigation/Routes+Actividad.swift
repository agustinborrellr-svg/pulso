import SwiftUI
import PulsoStore
import PulsoAnalytics

// C · Actividad (studio APP/C-actividad, mapa.md). Owned by the Actividad area: add cases here, map them in
// `ActividadDestination`, list them in `shots` (`-PulsoScreen r.actividad.<name>`). Its metric details go in
// `ActividadMetricDestination`.

enum ActividadRoute: AreaRoute {
    /// Esfuerzo del día (the strain screen, until the area redraws it).
    case esfuerzoDia
    /// 10 Entreno en vivo (11 with an interval plan; 12/13 are its menus).
    case entrenoVivo
    /// 20 Detalle de un ejercicio de respiración.
    case respiraDetalle(Breathwork.Kind)
    /// 22 Preparación.
    case respiraPreparacion(Breathwork.Kind)
    /// 23–25 Sesión guiada (full screen).
    case respiraSesion(Breathwork.Kind)
    /// 26 Resumen de la última sesión.
    case respiraResumen
    /// 30 Chequeo de 60 s.
    case chequeo60s
    /// Coherencia (Mídete).
    case coherencia
    /// 31 Ortostático.
    case ortostatico
    /// 32 Recuperación de FC.
    case recuperacionFC
    /// 33 FC máxima.
    case fcMaxima
    /// 34 Poincaré.
    case poincare
    /// Monitor en vivo (Mídete).
    case monitorVivo
    /// 40 Plan semanal (42 = empty).
    case planSemanal
    /// 41 Editar plan (sheet).
    case planEditar

    var presentation: RoutePresentation {
        switch self {
        case .planEditar: return .sheet
        case .respiraSesion: return .cover
        default: return .push
        }
    }

    static let shots: [(String, ActividadRoute)] = [
        ("esfuerzoDia", .esfuerzoDia), ("entrenoVivo", .entrenoVivo),
        ("respiraDetalle", .respiraDetalle(.coherence)), ("respiraPreparacion", .respiraPreparacion(.coherence)),
        ("respiraSesion", .respiraSesion(.coherence)), ("respiraResumen", .respiraResumen),
        ("chequeo60s", .chequeo60s), ("coherencia", .coherencia), ("ortostatico", .ortostatico),
        ("recuperacionFC", .recuperacionFC), ("fcMaxima", .fcMaxima), ("poincare", .poincare), ("monitorVivo", .monitorVivo),
        ("planSemanal", .planSemanal), ("planEditar", .planEditar),
    ]
}

struct ActividadDestination: View {
    @EnvironmentObject var model: AppModel
    let route: ActividadRoute

    var body: some View {
        switch route {
        case .esfuerzoDia:
            StrainDetailView()
        case .entrenoVivo:
            LiveView()
        case .respiraDetalle(let k):
            BreathworkDetailView(kind: k)
        case .respiraPreparacion(let k):
            BreathworkPrepView(kind: k, settings: Breathwork.Settings())
        case .respiraSesion(let k):
            BreathworkSessionView(kind: k, settings: Breathwork.Settings(), completed: .constant(false))
        case .respiraResumen:
            if let r = model.breathworkRecords.last {
                BreathworkResultView(record: r)
            } else {
                DSScreen("Respira", back: "Actividad") {
                    DSEmptyState(icon: "wind", title: "Sin sesiones", message: "Aún no has hecho ninguna respiración guiada.")
                }
            }
        case .chequeo60s: ScanView()
        case .coherencia: CoherenceView()
        case .ortostatico: OrthostaticTestView()
        case .recuperacionFC: RecoveryTestView()
        case .fcMaxima: MaxHRTestView()
        case .poincare: PoincareView()
        case .monitorVivo: MonitorView()
        case .planSemanal: WeeklyPlanView()
        case .planEditar: PlanEditor(goals: model.planGoals)
        }
    }
}

struct ActividadMetricDestination: View {
    let kind: MetricKind

    var body: some View {
        switch kind {
        case .pasos:
            DSTrendMetricDetail(metric: .steps, title: "Pasos", back: "Actividad", color: DS.act)
        case .calorias:
            DSTrendMetricDetail(metric: .calories, title: "Calorías", back: "Actividad", color: DS.act)
        case .zonas:
            DSTrendMetricDetail(metric: .zonesLight, title: "Zonas de FC", back: "Actividad", color: DS.act)
        case .vo2max:
            VO2MaxView()
        case .carga:
            TrendsView(initialMode: 0)
        default:
            EmptyView()
        }
    }
}
