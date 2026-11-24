import SwiftUI
import PulsoStore
import PulsoFeatures
import PulsoAnalytics

// C · Actividad (studio APP/C-actividad, mapa.md). Owned by the Actividad area: add cases here, map them in
// `ActividadDestination`, list them in `shots` (`-PulsoScreen r.actividad.<name>`). Its metric details go in
// `ActividadMetricDestination`.

enum ActividadRoute: AreaRoute {
    /// Esfuerzo del día (the old strain screen).
    case esfuerzoDia
    /// 10 Entreno en vivo (11 with an interval plan), full screen.
    case entrenoVivo
    /// 10 with its menu open: 12 zona objetivo · 13 terminar (screenshot run).
    case entrenoVivoMenu(LivePanel)
    /// 11 with the 4×4 plan (screenshot run: starts the plan).
    case entrenoIntervalos
    /// 20 Detalle de un ejercicio de respiración.
    case respiraDetalle(Breathwork.Kind)
    /// 21 The same with the «Ritmo» / «Duración» wheel open.
    case respiraAjuste(Breathwork.Kind)
    /// 22 Preparación.
    case respiraPreparacion(Breathwork.Kind)
    /// 23–25 Sesión guiada (full screen).
    case respiraSesion(Breathwork.Kind)
    /// 26 Resumen de una sesión (its start; nil = the latest).
    case respiraResumen(start: Int?)
    /// 30 Chequeo de 60 s.
    case chequeo60s
    /// Coherencia (old guided breathing with live coherence; reached from a running test).
    case coherencia
    /// 31 Ortostático.
    case ortostatico
    /// 31 with the test running (screenshot run).
    case ortostaticoEnCurso
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
    /// 42 Plan vacío (screenshot run: the empty state even with goals).
    case planVacio
    /// 41 Editar plan (sheet).
    case planEditar
    /// 02 The tab root without the band (screenshot run).
    case sinPulsera

    var presentation: RoutePresentation {
        switch self {
        case .planEditar: return .sheet
        case .respiraSesion, .entrenoVivo, .entrenoVivoMenu, .entrenoIntervalos: return .cover
        default: return .push
        }
    }

    static let shots: [(String, ActividadRoute)] = [
        ("sinPulsera", .sinPulsera), ("esfuerzoDia", .esfuerzoDia),
        ("entrenoVivo", .entrenoVivo), ("entrenoIntervalos", .entrenoIntervalos),
        ("entrenoZona", .entrenoVivoMenu(.zona)), ("entrenoTerminar", .entrenoVivoMenu(.terminar)),
        ("respiraDetalle", .respiraDetalle(.coherence)), ("respiraAjuste", .respiraAjuste(.coherence)),
        ("respiraDetalleAlerta", .respiraDetalle(.alert)),
        ("respiraPreparacion", .respiraPreparacion(.coherence)),
        ("respiraSesion", .respiraSesion(.coherence)), ("respiraSesion478", .respiraSesion(.sleep)),
        ("respiraSesionAlerta", .respiraSesion(.alert)), ("respiraResumen", .respiraResumen(start: nil)),
        ("chequeo60s", .chequeo60s), ("coherencia", .coherencia), ("ortostatico", .ortostatico),
        ("ortostaticoEnCurso", .ortostaticoEnCurso), ("recuperacionFC", .recuperacionFC), ("fcMaxima", .fcMaxima),
        ("poincare", .poincare), ("monitorVivo", .monitorVivo),
        ("planSemanal", .planSemanal), ("planEditar", .planEditar), ("planVacio", .planVacio),
    ]
}

struct ActividadDestination: View {
    @EnvironmentObject var model: AppModel
    let route: ActividadRoute

    var body: some View {
        content.onAppear { ActShots.prepare(route, model: model) }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .esfuerzoDia:
            StrainDetailView()
        case .entrenoVivo, .entrenoIntervalos:
            LiveWorkoutView()
        case .entrenoVivoMenu(let p):
            LiveWorkoutView(initialPanel: p)
        case .respiraDetalle(let k):
            BreathworkDetailView(kind: k)
        case .respiraAjuste(let k):
            BreathworkDetailView(kind: k, initialField: k == .alert ? .breaths : (k == .coherence ? .pace : .minutes))
        case .respiraPreparacion(let k):
            BreathworkPrepView(kind: k, settings: model.breathworkSettings(k))
        case .respiraSesion(let k):
            BreathworkSessionView(kind: k, settings: model.breathworkSettings(k), completed: .constant(false))
        case .respiraResumen(let start):
            if let r = start.flatMap({ s in model.breathworkRecords.first { $0.summary.start == s } }) ?? model.breathworkRecords.last {
                BreathworkResultView(record: r)
            } else {
                DSScreen("Respira", back: "Actividad") {
                    DSEmptyState(icon: "wind", title: "Sin sesiones", message: "Aún no has hecho ninguna respiración guiada.")
                }
            }
        case .chequeo60s: ScanView()
        case .coherencia: CoherenceView()
        case .ortostatico, .ortostaticoEnCurso: OrthostaticTestView()
        case .recuperacionFC: RecoveryTestView()
        case .fcMaxima: MaxHRTestView()
        case .poincare: PoincareView()
        case .monitorVivo: MonitorView()
        case .planSemanal: WeeklyPlanView()
        case .planVacio: WeeklyPlanView(forceEmpty: true)
        case .planEditar: PlanEditor(goals: model.planGoals)
        case .sinPulsera:
            ActivityRootView(forceDisconnected: true)
        }
    }
}

struct ActividadMetricDestination: View {
    let kind: MetricKind

    var body: some View {
        switch kind {
        case .pasos:
            StepsDetailView()
        case .calorias:
            CaloriesDetailView()
        case .zonas:
            ZonesDetailView()
        case .vo2max:
            VO2MaxView()
        case .carga:
            LoadDetailView()
        default:
            EmptyView()
        }
    }
}
