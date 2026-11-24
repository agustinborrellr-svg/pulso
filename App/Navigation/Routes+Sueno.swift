import SwiftUI
import PulsoStore

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

    var presentation: RoutePresentation {
        switch self {
        case .ajustarSueno, .meVoyADormir, .alarmaEditar: return .sheet
        default: return .push
        }
    }

    static let shots: [(String, SuenoRoute)] = [
        ("noche", .noche(day: nil)), ("siestas", .siestas), ("ajustarSueno", .ajustarSueno), ("meVoyADormir", .meVoyADormir),
        ("alarmas", .alarmas), ("alarmaEditar", .alarmaEditar(id: nil)), ("alarmaInteligente", .alarmaInteligente),
        ("historial", .historial),
    ]
}

struct SuenoDestination: View {
    @EnvironmentObject var model: AppModel
    let route: SuenoRoute

    var body: some View {
        switch route {
        case .noche, .siestas:
            SleepDetailView()
        case .ajustarSueno:
            SleepEditSheet(session: model.selected.flatMap { model.sleep(for: $0) }, forDay: model.selectedDay)
        case .meVoyADormir:
            BedtimeView()
        case .alarmas:
            AlarmsView()
        case .alarmaEditar(let id):
            NavigationStack {
                AlarmEditor(alarm: (id.flatMap { i in model.alarms.first { $0.id == i } }) ?? model.alarms.first ?? AlarmConfig())
            }
        case .alarmaInteligente:
            SmartAlarmHelp()
        case .historial:
            TrendDetailView(metric: .sleepPerformance)
        }
    }
}

struct SuenoMetricDestination: View {
    let kind: MetricKind

    var body: some View {
        switch kind {
        case .calificacion:
            DSTrendMetricDetail(metric: .sleepPerformance, title: "Calificación", back: "Sueño", color: DS.sueno, score: true,
                                night: true, yDomain: 0...100)
        case .necesidadSueno:
            DSTrendMetricDetail(metric: .hoursVsNeed, title: "Horas vs. lo necesario", back: "Sueño", color: DS.sueno, night: true)
        case .regularidad:
            DSTrendMetricDetail(metric: .regularity, title: "Regularidad", back: "Sueño", color: DS.sueno, night: true)
        case .eficiencia:
            DSTrendMetricDetail(metric: .efficiency, title: "Eficiencia", back: "Sueño", color: DS.sueno, night: true)
        case .reparador:
            DSTrendMetricDetail(metric: .restorativeHours, title: "Sueño reparador", back: "Sueño", color: DS.sueno, night: true)
        case .latencia, .fase:
            SleepDetailView()
        default:
            EmptyView()
        }
    }
}
