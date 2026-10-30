import Foundation

/// The fixed half of every analysis' "Cómo se calcula": what it is, what it needs, over which period,
/// how to read it and where it stops being valid. The variable half (formula, n, confidence) is in `MetricResult`.
public struct MetricGuide: Equatable, Sendable {
    /// What kind of claim the number makes. Nothing here is causal.
    public enum Kind: String, Sendable {
        case measure, estimate, association, correlation, hypothesis

        public var label: String {
            switch self {
            case .measure: return "Medida"
            case .estimate: return "Estimación"
            case .association: return "Asociación"
            case .correlation: return "Correlación"
            case .hypothesis: return "Hipótesis"
            }
        }

        public var explanation: String {
            switch self {
            case .measure: return "Se calcula directamente de tus datos."
            case .estimate: return "Un modelo aproxima un valor que no se mide directamente; tiene margen de error."
            case .association: return "Compara días con y sin algo; otras diferencias entre esos días pueden explicarlo. No es causa."
            case .correlation: return "Dos medidas que se mueven juntas. No indica cuál mueve a cuál ni si hay causa."
            case .hypothesis: return "Patrón posible en tus datos que conviene confirmar con más tiempo."
            }
        }
    }

    public var kind: Kind
    public var definition: String
    public var data: String
    public var period: String
    public var interpretation: String
    public var limitations: String

    public static func of(_ id: String) -> MetricGuide? { all[id] }

    static let all: [String: MetricGuide] = [
        "coherence": .init(kind: .measure,
            definition: "Lo habitual que es la combinación de VFC, FC en reposo, respiración y temperatura de anoche comparada con tus noches anteriores. Es un percentil: 64 significa que el 64 % de tus noches de referencia eran al menos igual de raras.",
            data: "Noches con las cuatro señales; mínimo 14 de referencia, completa con 28.",
            period: "Anoche frente a tus 28 noches anteriores con datos.",
            interpretation: "Alto (≥ 50): noche típica para ti. Medio (10–50): algo inusual. Bajo (< 10): combinación rara. Raro no es lo mismo que malo: mira hacia dónde se mueve cada señal.",
            limitations: "Solo te compara contigo. Con menos de 28 noches la referencia es parcial. Las noches importadas y las medidas por Pulso calculan VFC y temperatura de forma distinta; mezclarlas resta precisión."),
        "physDebt": .init(kind: .measure,
            definition: "Alteración acumulada cuando varias noches seguidas tus constantes van en la dirección desfavorable.",
            data: "Las mismas noches que la coherencia.",
            period: "Se arrastra noche a noche y se reduce un 40 % cada noche.",
            interpretation: "0 = sin alteración. Por encima de 1,5, varios días fuera de lo tuyo.",
            limitations: "No distingue la causa (entreno, enfermedad, alcohol, estrés)."),
        "forecast": .init(kind: .estimate,
            definition: "Recuperación que el modelo personal espera para mañana si duermes tus horas habituales.",
            data: "21 pares de días consecutivos con recuperación, esfuerzo y sueño.",
            period: "Todo tu historial disponible (hasta 150 días).",
            interpretation: "El número es el centro; el rango cubre el 80 % de los errores pasados del modelo.",
            limitations: "Aprende asociaciones de tus datos; si cambias de rutina tarda en adaptarse."),
        "surprise": .init(kind: .estimate,
            definition: "Cuánto se alejó la recuperación de hoy de lo que el modelo esperaba ayer.",
            data: "Un modelo ya validado.",
            period: "Hoy.",
            interpretation: "< 1 σ, lo esperado; > 2 σ, algo no registrado influyó.",
            limitations: "Depende de la calidad del modelo (mira la predictibilidad)."),
        "cardiacCost": .init(kind: .measure,
            definition: "Latidos de más sobre tu FC en reposo mientras estás despierto, fuera de entrenos y siestas.",
            data: "Días completos medidos por Pulso con pulso minuto a minuto (los importados no lo traen).",
            period: "El último día completo frente a la mediana de tus 28 días completos anteriores. El día en curso se muestra sin comparar.",
            interpretation: "Más alto que tu día típico: estrés, calor, cafeína, poco sueño o enfermedad.",
            limitations: "Depende de las horas que lleves la pulsera. No mide calorías."),
        "recoveryVelocity": .init(kind: .measure,
            definition: "Noches que tardan tus constantes en volver a tu patrón tras un día exigente.",
            data: "3 días exigentes (esfuerzo ≥ tu p75 o entreno ≥ 8) con las noches siguientes medidas.",
            period: "Mediana de los 10 últimos.",
            interpretation: "Menos noches = recuperas antes.",
            limitations: "Los días encadenados se apartan; si no vuelves en 5 noches cuenta como «5 o más»."),
        "recoveryEfficiency": .init(kind: .measure,
            definition: "Cuánto te desajusta un día exigente: suma de la desviación desfavorable de las noches fuera de rango.",
            data: "3 días exigentes medidos.",
            period: "Mediana de los 10 últimos.",
            interpretation: "Menor = mejor.",
            limitations: "No separa el efecto del entreno del de otras cosas de esas noches."),
        "recoveryConsistency": .init(kind: .measure,
            definition: "Lo parecido que es tu tiempo de recuperación en sesiones comparables.",
            data: "4 sesiones del mismo deporte e intensidad.",
            period: "Todas las sesiones limpias.",
            interpretation: "Alto = predecible; bajo = influyen otros factores.",
            limitations: "Solo usa el grupo de sesiones más frecuente."),
        "hrr60": .init(kind: .measure,
            definition: "Cuánto baja tu pulso en el primer minuto tras un esfuerzo intenso.",
            data: "Entrenos con pulso de la pulsera justo al terminar (los importados sin pulso no cuentan).",
            period: "Mediana de los 8 últimos; tendencia frente a los anteriores.",
            interpretation: "Más bajada = mejor recuperación cardíaca.",
            limitations: "Depende de cómo termines (parada brusca o vuelta a la calma)."),
        "adaptation": .init(kind: .association,
            definition: "Si, a igual esfuerzo, cada vez te desajustas menos (o más) tras los días exigentes.",
            data: "8 días exigentes limpios.",
            period: "Todo el historial de días exigentes.",
            interpretation: "Pendiente negativa con intervalo bajo 0 = adaptándote.",
            limitations: "Asociación en el tiempo: cambios de sueño o estrés pueden explicarla."),
        "recoveryCeiling": .init(kind: .hypothesis,
            definition: "Carga de 3 días a partir de la cual tu recuperación se alarga más que la carga.",
            data: "20 días exigentes medidos; los que no se recuperan en 5 noches cuentan como «5 o más».",
            period: "Todo el historial de días exigentes.",
            interpretation: "Un codo marca tu carga tolerable. «No se ve límite» también es un resultado: en el rango de carga que has hecho no hay punto de quiebre.",
            limitations: "Solo vale dentro de las cargas que ya has hecho; no predice cargas nunca probadas."),
        "adaptationLag": .init(kind: .correlation,
            definition: "Semanas que tarda tu VFC en reflejar un cambio sostenido de carga.",
            data: "12 semanas con esfuerzo y VFC.",
            period: "Semanas completas de tu historial.",
            interpretation: "Retraso más probable con su intervalo.",
            limitations: "Correlación con desfase; confianza baja hasta 26 semanas."),
        "sri": .init(kind: .measure,
            definition: "Probabilidad de estar en el mismo estado (dormido/despierto) a la misma hora en días seguidos.",
            data: "5 noches en las dos últimas semanas.",
            period: "Últimos 14 días.",
            interpretation: "100 = horario idéntico; < 70 = irregular.",
            limitations: "Las noches importadas solo traen hora de acostarse y levantarse."),
        "socialJetlag": .init(kind: .measure,
            definition: "Diferencia del punto medio del sueño entre fin de semana y entre semana.",
            data: "3 noches entre semana y 2 de fin de semana.",
            period: "Últimas semanas.",
            interpretation: "> 1 h = desfase notable.",
            limitations: "Turnos o viajes lo distorsionan."),
        "circadian": .init(kind: .estimate,
            definition: "Índice que combina regularidad, jet lag social y variación de la hora de acostarse.",
            data: "Dos semanas de noches.",
            period: "Últimos 14 días.",
            interpretation: "0 = ritmo estable; alto = disrupción.",
            limitations: "Los pesos son una elección razonable, no un estándar clínico."),
        "nadir": .init(kind: .measure,
            definition: "En qué momento de la noche llega tu pulso más bajo.",
            data: "5 noches con pulso medido por Pulso.",
            period: "Mediana de 14 noches.",
            interpretation: "Pronto (primera mitad) suele indicar buena recuperación; tarde, digestión, alcohol o estrés.",
            limitations: "Asociación descrita en estudios, no un diagnóstico."),
        "fragmentationCost": .init(kind: .association,
            definition: "Puntos de recuperación asociados a cada despertar, a igual horas dormidas.",
            data: "21 noches medidas por Pulso (las importadas no traen despertares).",
            period: "Todo el historial.",
            interpretation: "Negativo = cada despertar se asocia a peor recuperación.",
            limitations: "Asociación; los despertares pueden ser consecuencia de otra cosa."),
        "timingSensitivity": .init(kind: .association,
            definition: "Puntos de recuperación asociados a cada hora que te acuestas fuera de tu hora habitual.",
            data: "21 noches con recuperación y hora de acostarse.",
            period: "Todo el historial.",
            interpretation: "Más negativo = más te afecta cambiar de horario.",
            limitations: "Asociación; con noches importadas se añade un término por fuente."),
        "habits": .init(kind: .association,
            definition: "Diferencia media de recuperación al día siguiente entre días con y sin cada hábito.",
            data: "4 días con y 4 sin, contando solo días en que se preguntó por ese hábito.",
            period: "Todo tu diario.",
            interpretation: "«Claro» solo si el intervalo 90 % excluye 0 y pasa la corrección por comparaciones múltiples (Benjamini–Hochberg, q < 0,10).",
            limitations: "Asociación: esos días pueden diferir en otras cosas (carga, sueño, otros hábitos)."),
        "predictability": .init(kind: .measure,
            definition: "Cuánto mejor acierta el modelo personal que tu media de los 7 últimos días.",
            data: "26 pares de días para validar.",
            period: "Validación día a día con solo días anteriores.",
            interpretation: "> 15 %: útil. ≤ 0 %: el simulador aún no es fiable para ti.",
            limitations: "Si cambias de rutina, el acierto pasado no garantiza el futuro."),
        "relation": .init(kind: .correlation,
            definition: "Correlación de Pearson entre dos métricas, emparejadas por fecha.",
            data: "Días con las dos métricas; mínimo 10 para hablar de relación.",
            period: "El periodo elegido.",
            interpretation: "Solo se habla de relación si el intervalo 90 % de r (Fisher z) no incluye 0.",
            limitations: "Correlación no es causa; días seguidos no son independientes, así que el intervalo es algo optimista."),
    ]
}
