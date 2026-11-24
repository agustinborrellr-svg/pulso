import SwiftUI
import PulsoStore
import PulsoFeatures
import PulsoAnalytics
import PulsoIntelligence

// D · Salud + Análisis (studio APP/D-salud, mapa.md). Owned by the Salud area: add cases here, map them in
// `SaludDestination`, list them in `shots` (`-PulsoScreen r.salud.<name>`). Its metric details (ritmo, hábitos,
// métricas de Análisis) go in `SaludMetricDestination`.

enum SaludRoute: AreaRoute {
    /// 02 Análisis, segmento Inteligencia.
    case analisis
    /// 12 Análisis, segmento Tendencias.
    case tendencias
    /// 03 Anoche frente a tu normal.
    case tuEstado
    /// 04 Simulador (mañana).
    case simulador
    /// 05 Qué te afecta (comportamientos).
    case comportamientos
    /// 06 Tras un día exigente.
    case respuestaCarga
    /// 07 Tu horario de sueño.
    case suenoRitmo
    /// Hábitos y predicción.
    case habitosPrediccion
    /// 08 Todas las métricas.
    case todasMetricas
    /// 10 Explorador.
    case explorador
    /// 11 Informe mensual.
    case informeMensual
    /// 14 Electrocardiograma.
    case ecg
    /// 15 Grabando un ECG (full screen; demo).
    case ecgGrabando
    /// 16 Detalle de un ECG (start; nil = the latest).
    case ecgDetalle(start: Int?)
    /// 17 Informe de salud.
    case informeSalud
    /// 18 Tensión arterial (20 = empty).
    case tension
    /// 19 Nueva lectura de tensión (sheet).
    case tensionNueva
    /// 21 Ciclo menstrual.
    case ciclo
    /// 25 Laboratorio.
    case laboratorio

    var presentation: RoutePresentation {
        switch self {
        case .tensionNueva: return .sheet
        case .ecgGrabando: return .cover
        default: return .push
        }
    }

    static let shots: [(String, SaludRoute)] = [
        ("analisis", .analisis), ("tendencias", .tendencias), ("tuEstado", .tuEstado), ("simulador", .simulador),
        ("comportamientos", .comportamientos), ("respuestaCarga", .respuestaCarga), ("suenoRitmo", .suenoRitmo),
        ("habitosPrediccion", .habitosPrediccion), ("todasMetricas", .todasMetricas), ("explorador", .explorador),
        ("informeMensual", .informeMensual), ("ecg", .ecg), ("ecgGrabando", .ecgGrabando), ("ecgDetalle", .ecgDetalle(start: nil)),
        ("informeSalud", .informeSalud), ("tension", .tension), ("tensionNueva", .tensionNueva), ("ciclo", .ciclo),
        ("laboratorio", .laboratorio),
    ]
}

struct SaludDestination: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let route: SaludRoute

    var body: some View {
        switch route {
        case .analisis: TrendsView(initialMode: 1)
        case .tendencias: TrendsView(initialMode: 0)
        case .tuEstado: IntelTodayView()
        case .simulador: WhatIfView()
        case .comportamientos: BehaviorsView()
        case .respuestaCarga: IntelSectionView(title: "Respuesta a la carga")
        case .suenoRitmo: IntelSectionView(title: "Sueño y ritmo")
        case .habitosPrediccion: IntelSectionView(title: "Hábitos y predicción")
        case .todasMetricas: IntelMoreView()
        case .explorador: RelationExplorerView()
        case .informeMensual: MonthlyReportView()
        case .ecg: ECGListView()
        case .ecgGrabando: ECGRecordView(simulated: true, onClose: { dismiss() })
        case .ecgDetalle(let start):
            if let r = start.flatMap({ s in model.ecgRecordings.first { $0.start == s } }) ?? model.ecgRecordings.first {
                ECGDetailView(recording: r)
            } else {
                ECGListView()
            }
        case .informeSalud: HealthMonitorView()
        case .tension: BloodPressureView()
        case .tensionNueva: NavigationStack { BloodPressureView() }
        case .ciclo: CycleCalendarView()
        case .laboratorio: LabView()
        }
    }
}

struct SaludMetricDestination: View {
    @EnvironmentObject var model: AppModel
    let kind: MetricKind

    var body: some View {
        switch kind {
        case .ritmoEnvejecimiento, .habito:
            PulsoAgeDetailView()
        case .intel(let id):
            if let m = model.intelligence?.metric(id) {
                MetricDetailView(metric: m)
            } else {
                DSScreen("Análisis", back: "Salud") {
                    DSEmptyState(icon: "brain.head.profile", title: "Calculando", message: "Esta métrica aparece cuando haya datos suficientes.")
                }
            }
        default:
            EmptyView()
        }
    }
}
