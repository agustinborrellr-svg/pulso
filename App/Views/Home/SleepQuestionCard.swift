import SwiftUI
import PulsoStore

/// "¿Te acabas de echar una siesta?" with one button per answer.
struct SleepQuestionCard: View {
    @EnvironmentObject var model: AppModel
    let session: SleepSession

    var body: some View {
        PCard {
            HStack(spacing: 10) {
                Image(systemName: "powersleep").font(.title2).foregroundStyle(Theme.sleep)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.isNap ? "¿Te acabas de echar una siesta?" : "¿Has dormido durante el día?")
                        .font(.headline).foregroundStyle(.white)
                    Text("\(Fmt.time(session.start))–\(Fmt.time(session.end)) · \(Fmt.hm(session.asleepMinutes)) dormido. Lo he contado como \(session.isNap ? "siesta" : "sueño").")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            Text("Una siesta reduce lo que necesitas dormir esta noche; si era tu sueño (por turnos o porque no dormiste de noche), cuenta entero en tus horas.")
                .font(.caption).foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                Button("Fue una siesta") { model.answerSleepQuestion(session, isNap: true) }
                    .buttonStyle(PrimaryCapsuleStyle())
                Button("Era mi sueño") { model.answerSleepQuestion(session, isNap: false) }
                    .buttonStyle(SecondaryCapsuleStyle())
            }
            .font(.caption)
        }
    }
}

/// Stage confidence with its reasons, and why no wrist device can be fully sure.
struct StageConfidenceRow: View {
    let confidence: StageConfidence
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack {
                    Image(systemName: "checkmark.seal").foregroundStyle(color)
                    Caps("Confianza de las fases", size: 12)
                    Spacer()
                    Text(confidence.level.label).font(.subheadline.bold()).foregroundStyle(color)
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption.bold()).foregroundStyle(Theme.secondary)
                }
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        stat("Lectura", confidence.coverage)
                        stat("Latido a latido", confidence.beatCoverage)
                        stat("Claridad", confidence.decisiveness)
                    }
                    if confidence.reasons.isEmpty {
                        Text("Señal limpia y fases claras esta noche.").font(.subheadline).foregroundStyle(.white)
                    } else {
                        Text(confidence.level == .high ? "Lo que la ha bajado un poco:" : "Por qué no es alta:")
                            .font(.subheadline.bold()).foregroundStyle(.white)
                        ForEach(confidence.reasons, id: \.self) { r in
                            Label(r, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(Color(white: 0.85))
                        }
                    }
                    Text("Ninguna pulsera puede tener confianza total en las fases: se miden de verdad con la actividad del cerebro (EEG) en un laboratorio del sueño. La pulsera las deduce del pulso, la VFC y el movimiento, y en los estudios acierta la fase de cada minuto alrededor de 6-7 de cada 10 veces. «Alta» significa que esta noche las señales fueron limpias y claras, no que sea una medida de laboratorio. El total dormido es mucho más fiable que el reparto entre fases.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var color: Color {
        switch confidence.level {
        case .high: return Theme.better
        case .medium: return Theme.yellow
        case .low: return Theme.worse
        }
    }

    private func stat(_ k: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int((v * 100).rounded())) %").font(.headline.monospacedDigit()).foregroundStyle(.white)
            Caps(k, size: 9, color: Theme.secondary, weight: .semibold)
        }
    }
}
