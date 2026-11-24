import SwiftUI
import PulsoStore

// E · Tú (studio APP/E-tu, mapa.md). Owned by the Tú area: add cases here, map them in `TuDestination`, list them
// in `shots` (`-PulsoScreen r.tu.<name>`). The battery metric goes in `TuMetricDestination`.

enum TuRoute: AreaRoute {
    /// 02 Perfil.
    case perfil
    /// 03 Pulsera (estado).
    case pulsera
    /// 04 Pulsera, avanzado.
    case pulseraAvanzado
    /// 06–07 Emparejar (full screen).
    case emparejar
    /// 08 Registro de conexión.
    case registro
    /// 09 Guía de emparejamiento.
    case guiaEmparejamiento
    /// 10 Avisos.
    case avisos
    /// 11 Conexiones.
    case conexiones
    /// 12–13 Importar historial.
    case importar
    /// 14 Copias y almacenamiento.
    case copias
    /// 16 Diario de hábitos.
    case diario
    /// 17 Doble toque.
    case dobleToque
    /// 18–19 Guía de Pulso (full screen, from a page).
    case guia(page: Int)
    /// 20 Cómo se calcula cada métrica.
    case comoSeCalcula
    /// 21 Acerca de Pulso.
    case acerca

    var presentation: RoutePresentation {
        switch self {
        case .emparejar, .guia: return .cover
        default: return .push
        }
    }

    static let shots: [(String, TuRoute)] = [
        ("perfil", .perfil), ("pulsera", .pulsera), ("pulseraAvanzado", .pulseraAvanzado), ("emparejar", .emparejar),
        ("registro", .registro), ("guiaEmparejamiento", .guiaEmparejamiento), ("avisos", .avisos), ("conexiones", .conexiones),
        ("importar", .importar), ("copias", .copias), ("diario", .diario), ("dobleToque", .dobleToque),
        ("guia", .guia(page: 0)), ("guiaRecarga", .guia(page: 3)), ("comoSeCalcula", .comoSeCalcula), ("acerca", .acerca),
    ]
}

struct TuDestination: View {
    @EnvironmentObject var model: AppModel
    let route: TuRoute

    var body: some View {
        switch route {
        case .perfil: ProfileEditor(profile: model.profile)
        case .pulsera, .pulseraAvanzado: DeviceView()
        case .emparejar: PairingFlowView()
        case .registro: ConnectionLogView()
        case .guiaEmparejamiento: PairingGuideView()
        case .avisos: NotificationsView()
        case .conexiones: IntegrationsView(strava: model.strava)
        case .importar: WhoopImportView()
        case .copias: StorageView()
        case .diario: JournalEditor()
        case .dobleToque: DoubleTapView()
        case .guia(let page): GuideView(startPage: page)
        case .comoSeCalcula: MethodologyView()
        case .acerca: AboutScreen()
        }
    }
}

struct TuMetricDestination: View {
    let kind: MetricKind

    var body: some View {
        switch kind {
        case .bateria: DeviceView()
        default: EmptyView()
        }
    }
}

/// 21 Acerca de Pulso (minimal, real data only).
private struct AboutScreen: View {
    var body: some View {
        DSScreen("Acerca de Pulso", back: "Tú") {
            DSGroup {
                DSRow(label: "Versión", value: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "–", keyValue: true)
                DSRow(label: "Compilación", value: (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "–", keyValue: true)
            }
            Text("Pulso calcula todo en tu iPhone, sin nube. No es un dispositivo médico: todas las métricas son estimaciones de bienestar.")
                .dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2)
                .padding(.horizontal, 4)
        }
    }
}
