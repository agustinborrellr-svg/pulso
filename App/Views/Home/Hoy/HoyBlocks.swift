import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoFeatures

/// A block of the customisable part of Hoy. The top (scores, monitor, Ahora) is fixed and not listed here.
enum HoyBlock: String, Codable, CaseIterable, Identifiable {
    case actividades, anoche, estres, tendencias, edadPulso, estaNoche
    case tuSemana, cargaSemana, pasos, racha, meVoyADormir, constantes

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case recuperacion = "Recuperación"
        case sueno = "Sueño"
        case actividad = "Actividad"
        case cuerpo = "Cuerpo"
    }

    var title: String {
        switch self {
        case .actividades: return "Actividades"
        case .anoche: return "Anoche"
        case .estres: return "Estrés del día"
        case .tendencias: return "Tendencias de tu cuerpo"
        case .edadPulso: return "Edad Pulso"
        case .estaNoche: return "Esta noche"
        case .tuSemana: return "Tu semana"
        case .cargaSemana: return "Carga de la semana"
        case .pasos: return "Pasos y movimiento"
        case .racha: return "Racha"
        case .meVoyADormir: return "Me voy a dormir"
        case .constantes: return "Constantes vitales"
        }
    }

    var subtitle: String {
        switch self {
        case .actividades: return "Registro del día y franja de 24 h"
        case .anoche: return "Fases, horario y regularidad"
        case .estres: return "Curva por zonas, hora a hora"
        case .tendencias: return "5 constantes · 30 días"
        case .edadPulso: return "Edad fisiológica · 6 meses"
        case .estaNoche: return "Hora de acostarte y despertador"
        case .tuSemana: return "Recarga, Sueño y Esfuerzo · 7 días"
        case .cargaSemana: return "Carga de 7 días frente a tus 4 semanas"
        case .pasos: return "Pasos y minutos activos · 7 días"
        case .racha: return "Noches seguidas de más de 7 h"
        case .meVoyADormir: return "Ampliado: tus últimas 7 noches"
        case .constantes: return "Tus 5 constantes de anoche"
        }
    }

    var group: Group {
        switch self {
        case .tuSemana, .estres: return .recuperacion
        case .racha, .meVoyADormir, .anoche, .estaNoche: return .sueno
        case .cargaSemana, .pasos, .actividades: return .actividad
        case .constantes, .tendencias, .edadPulso: return .cuerpo
        }
    }

    static let defaults: [HoyBlock] = [.actividades, .anoche, .estres, .tendencias, .edadPulso, .estaNoche]
}

/// The user's blocks in order, saved as a JSON list of ids in `pulso.hoy.blocks`. Empty (never saved) = defaults;
/// "[]" = the user removed everything.
enum HoyLayout {
    static let key = "pulso.hoy.blocks"

    static func decode(_ raw: String) -> [HoyBlock] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return HoyBlock.defaults }
        var seen = Set<HoyBlock>()
        return ids.compactMap(HoyBlock.init(rawValue:)).filter { seen.insert($0).inserted }
    }

    static func encode(_ list: [HoyBlock]) -> String {
        guard let data = try? JSONEncoder().encode(list.map(\.rawValue)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension AppModel {
    /// Whether a block has real data to show. Blocks without data are hidden on Hoy and not offered in «Añadir».
    func hoyHasData(_ b: HoyBlock, day: DaySummary?) -> Bool {
        switch b {
        case .actividades: return day != nil
        case .anoche: return day.flatMap { sleep(for: $0) }.map { !$0.stages.isEmpty } ?? false
        case .estres: return day.map { !hoyStressPoints(for: $0).isEmpty } ?? false
        case .tendencias, .constantes: return !vitalReadings().isEmpty
        case .edadPulso: return pulsoAge?.pulsoAge != nil
        case .estaNoche: return tonightPlan != nil || nextAlarm != nil
        case .tuSemana: return days.suffix(7).contains { $0.recovery != nil || $0.sleepPerformance != nil || $0.strain != nil }
        case .cargaSemana: return trainingLoad.last?.acwr != nil
        case .pasos: return days.suffix(7).contains { ($0.steps ?? 0) > 0 }
        case .racha, .meVoyADormir: return days.suffix(14).contains { $0.sleepMinutes != nil }
        }
    }
}
