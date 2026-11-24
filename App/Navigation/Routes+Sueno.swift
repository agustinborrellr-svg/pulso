import SwiftUI
import PulsoStore
import PulsoFeatures
import PulsoAnalytics

// B · Sueño (studio APP/B-sueno, mapa.md). Owned by the Sueño area: add cases here, map them in `SuenoDestination`,
// list them in `shots` (`-PulsoScreen r.sueno.<name>`). Sleep metric details go in `SuenoMetricDestination`.

enum SuenoRoute: AreaRoute {
    /// 02 Detalle de la noche (day key; nil = the selected day).
    case noche(day: String?)
    /// 10 Siestas.
    case siestas
    /// 12 Ajustar horas de sueño (sheet).
    case ajustarSueno
    /// 13 Me voy a dormir (sheet).
    case meVoyADormir
    /// 14 Despertador.
    case alarmas
    /// 15 Editar alarma (sheet; id nil = new alarm).
    case alarmaEditar(id: String?)
    /// 18 Cómo funciona la alarma inteligente.
    case alarmaInteligente
    /// 19 Tus noches.
    case historial
    /// Screenshot states: 11 nap menu open, 16 band test running, 17 alarm ringing, 20 morning without a night.
    case demo(SuenoDemo)

    var presentation: RoutePresentation {
        switch self {
        case .ajustarSueno, .meVoyADormir, .alarmaEditar: return .sheet
        default: return .push
        }
    }

    static let shots: [(String, SuenoRoute)] = [
        ("noche", .noche(day: nil)), ("siestas", .siestas), ("siestaMenu", .demo(.napMenu)), ("ajustarSueno", .ajustarSueno),
        ("meVoyADormir", .meVoyADormir), ("alarmas", .alarmas), ("alarmaEditar", .alarmaEditar(id: "shot-1")),
        ("alarmaNueva", .alarmaEditar(id: nil)), ("pruebaPulsera", .demo(.bandTest)), ("alarmaSonando", .demo(.ringing)),
        ("alarmaInteligente", .alarmaInteligente), ("historial", .historial), ("sinNoche", .demo(.noNight)),
    ]
}

/// UI states the screenshot run shows without touching the model (nothing is sent to the band).
enum SuenoDemo: Hashable {
    case napMenu, bandTest, ringing, noNight
}

struct SuenoDestination: View {
    @EnvironmentObject var model: AppModel
    let route: SuenoRoute

    var body: some View {
        switch route {
        case .noche(let day):
            SleepDetailView(day: day, back: "Sueño")
        case .siestas:
            SuenoNapsView()
        case .ajustarSueno:
            SleepEditSheet(session: model.selected.flatMap { model.sleep(for: $0) }, forDay: model.selectedDay)
        case .meVoyADormir:
            BedtimeView()
        case .alarmas:
            AlarmsView()
        case .alarmaEditar(let id):
            NavigationStack {
                AlarmEditor(alarm: id.flatMap { i in model.alarms.first { $0.id == i } } ?? AlarmConfig())
            }
        case .alarmaInteligente:
            SmartAlarmHelp()
        case .historial:
            SuenoHistoryView()
        case .demo(let d):
            switch d {
            case .napMenu: SuenoNapsView(demoMenu: true)
            case .bandTest: AlarmsView(demo: .bandTest)
            case .ringing: AlarmsView(demo: .ringing)
            case .noNight: SleepTab(previewEmpty: true)
            }
        }
    }
}

struct SuenoMetricDestination: View {
    let kind: MetricKind

    var body: some View {
        switch kind {
        case .calificacion: SuenoScoreDetail()
        case .necesidadSueno: SuenoNeedDetail()
        case .regularidad: SuenoRegularityDetail()
        case .eficiencia: SuenoEfficiencyDetail()
        case .reparador: SuenoRestorativeDetail()
        case .latencia: SuenoLatencyDetail()
        case .fase(let st): SuenoPhaseDetail(stage: st)
        default: EmptyView()
        }
    }
}
