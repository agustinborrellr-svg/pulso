import SwiftUI
import Charts
import PulsoStore
import PulsoIntelligence

/// Per-workout cardiac analysis (1 Hz data): heart-rate recovery, drift, reserve and the nights it cost.
struct WorkoutCardiacCard: View {
    @EnvironmentObject var model: AppModel
    let workout: Workout
    @State private var result: WorkoutAnalysis.Result?
    @State private var hasHeart = true

    var body: some View {
        Card {
            SectionTitle(title: "Análisis cardíaco", subtitle: "Con tus datos segundo a segundo")
            if result != nil, !hasHeart {
                Text(workout.source.isExternal
                     ? "Sin datos de pulso: entreno importado sin la pulsera puesta. No entra en la recuperación del pulso."
                     : "Sin datos de pulso de la pulsera en este entreno.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            } else if let r = result {
                if let rec = r.recovery {
                    HStack {
                        stat("A 60 s", rec.drop60.map { "−\(Int($0.rounded()))" } ?? "–", "lpm")
                        stat("A 120 s", rec.drop120.map { "−\(Int($0.rounded()))" } ?? "–", "lpm")
                        stat("τ", rec.tau.map { "\(Int($0.rounded()))" } ?? "–", "s")
                        stat("A reposo", rec.minutesToBaseline.map { "\(Int($0.rounded()))" } ?? ">30", "min")
                    }
                    if rec.curve.count >= 4 {
                        Chart(rec.curve, id: \.t) { p in
                            LineMark(x: .value("s", p.t), y: .value("lpm", p.hr)).foregroundStyle(Theme.red).interpolationMethod(.monotone)
                        }
                        .chartXAxis { AxisMarks(values: [0, 60, 120, 180]) { v in AxisValueLabel { Text("\(v.as(Int.self) ?? 0) s") } } }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 110)
                    }
                    Text("Cuánto baja tu pulso al terminar. Más bajada y τ más pequeño = mejor recuperación cardíaca.")
                        .font(.caption2).foregroundStyle(Theme.tertiary)
                } else {
                    Text("Sin curva de recuperación: el esfuerzo final no fue intenso o faltan datos justo al terminar.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Divider().overlay(Color.white.opacity(0.1))
                if let d = r.drift.percent {
                    LabeledContent("Deriva cardíaca", value: String(format: "%+.1f %%", d))
                } else {
                    LabeledContent("Deriva cardíaca", value: "–")
                }
                Text(r.drift.note).font(.caption2).foregroundStyle(Theme.tertiary)
                if let res = r.reserve {
                    LabeledContent("Reserva cardíaca media", value: "\(Int((res.mean * 100).rounded())) %")
                    LabeledContent("Mejor minuto", value: "\(Int((res.peak * 100).rounded())) %")
                    if res.minutesAbove90 >= 0.5 { LabeledContent("Por encima del 90 %", value: Fmt.hm(res.minutesAbove90)) }
                    if res.approximate {
                        Text("Aproximado: tu FC máxima es estimada. Fíjala en Perfil si la conoces.").font(.caption2).foregroundStyle(Theme.tertiary)
                    }
                }
                if let e = model.loadEvent(for: workout) {
                    Divider().overlay(Color.white.opacity(0.1))
                    LabeledContent("Noches hasta normalizarte", value: e.recoveryNights.map { String(format: "%.1f", $0) } ?? (e.censored ? "≥ 5" : "sin medir"))
                    if let h = e.hrvChangePct { LabeledContent("VFC la noche siguiente", value: String(format: "%+.0f %%", h)) }
                    if e.chained { Text("Hubo otro día exigente antes de recuperarte: carga encadenada.").font(.caption2).foregroundStyle(Theme.yellow) }
                }
            } else {
                ProgressView()
            }
            if hasHeart { HowCalculated(id: "hrr60", formula: "FCR60 = FC al terminar (media de los últimos 30 s) − FC 60 s después; τ por ajuste log-lineal de los 2 primeros minutos") }
        }
        .font(.subheadline)
        .task {
            let w = workout
            hasHeart = model.workoutHasHeartData(w)
            result = model.workoutAnalysis(w)
        }
    }

    private func stat(_ k: String, _ v: String, _ u: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(v).font(.headline.monospacedDigit())
                Text(u).font(.caption2).foregroundStyle(Theme.secondary)
            }
            Text(k).font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
