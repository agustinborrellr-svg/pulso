import SwiftUI
import PulsoStore
import PulsoAnalytics

/// "¿Te acabas de echar una siesta?" with one button per answer (studio B-sueno 10).
struct SleepQuestionCard: View {
    @EnvironmentObject var model: AppModel
    let session: SleepSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.fill").font(.system(size: 18)).foregroundStyle(DS.sueno).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.isNap ? "¿Te acabas de echar una siesta?" : "¿Has dormido durante el día?")
                        .dsFont(18, .semibold).foregroundStyle(DS.t1).fixedSize(horizontal: false, vertical: true)
                    Text("\(ended) · contada como \(session.isNap ? "siesta" : "sueño")")
                        .dsFont(14).foregroundStyle(DS.t2)
                }
            }
            HStack(spacing: 10) {
                Button { model.answerSleepQuestion(session, isNap: true) } label: { Text("Fue una siesta").frame(maxWidth: .infinity) }
                    .buttonStyle(DSButtonStyle(tint: DS.sueno, size: .small, fullWidth: true))
                Button { model.answerSleepQuestion(session, isNap: false) } label: { Text("Era mi sueño").frame(maxWidth: .infinity) }
                    .buttonStyle(DSButtonStyle(size: .small, gray: true, fullWidth: true))
            }
            Button("No dormí: estaba descansando") { model.answerSleepQuestion(session, kind: .notSleep) }
                .dsFont(15, .semibold)
                .foregroundStyle(DS.t2)
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
        }
        .dsCard(padding: 16)
    }

    /// "terminó hace 1 h 33" (or its times when it was long ago).
    private var ended: String {
        let ago = Date().timeIntervalSince1970 - TimeInterval(session.end)
        if ago >= 60, ago < 12 * 3600 { return "terminó hace \(DSFmt.duration(ago / 60))" }
        return "\(Fmt.time(session.start))–\(Fmt.time(session.end))"
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
                    Text("Confianza de las fases").dsFont(16).foregroundStyle(DS.t1)
                    Spacer()
                    Text(confidence.level.label).dsFont(16, .semibold).foregroundStyle(color)
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(DS.t3)
                }
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    DSStatStrip(stats: [DSStat(label: "Lectura", value: pct(confidence.coverage)),
                                        DSStat(label: "Latido a latido", value: pct(confidence.beatCoverage)),
                                        DSStat(label: "Claridad", value: pct(confidence.decisiveness))])
                    if confidence.reasons.isEmpty {
                        Text("Señal limpia y fases claras esta noche.").dsFont(15).foregroundStyle(DS.t1)
                    } else {
                        Text(confidence.level == .high ? "Lo que la ha bajado un poco:" : "Por qué no es alta:")
                            .dsFont(15, .semibold).foregroundStyle(DS.t1)
                        ForEach(confidence.reasons, id: \.self) { r in
                            Label(r, systemImage: "exclamationmark.circle").dsFont(14).foregroundStyle(DS.t2)
                        }
                    }
                    Text("Ninguna pulsera puede tener confianza total en las fases: se miden de verdad con la actividad del cerebro (EEG) en un laboratorio del sueño. La pulsera las deduce del pulso, la VFC y el movimiento, y en los estudios acierta la fase de cada minuto alrededor de 6-7 de cada 10 veces. «Alta» significa que esta noche las señales fueron limpias y claras, no que sea una medida de laboratorio. El total dormido es mucho más fiable que el reparto entre fases.")
                        .dsFont(13)
                        .foregroundStyle(DS.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var color: Color {
        switch confidence.level {
        case .high: return DSLevel.buena.ink
        case .medium: return DSLevel.justa.ink
        case .low: return DSLevel.baja.ink
        }
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }
}

/// Shown in the morning while last night is missing, so yesterday's cycle is never read as today's.
struct NightPendingCard: View {
    @EnvironmentObject var model: AppModel
    let status: NightStatus
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: status == .awaitingData ? "arrow.triangle.2.circlepath" : "moon.fill")
                    .font(.system(size: 18)).foregroundStyle(DS.sueno).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status == .awaitingData ? "Tu noche aún no está descargada" : "No encuentro tu noche")
                        .dsFont(18, .semibold).foregroundStyle(DS.t1)
                    Text("Lo que ves abajo es el ciclo del \(Fmt.shortDay(model.currentDayKey).lowercased()). La recuperación de hoy saldrá de la noche que acaba esta mañana.")
                        .dsFont(14).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
                }
            }
            if status == .awaitingData {
                Button("Sincronizar ahora") { model.syncNow() }
                    .buttonStyle(DSButtonStyle(tint: DS.sueno, size: .small))
                    .disabled(!model.strapState.isConnected)
                if !model.strapState.isConnected {
                    Text("La pulsera no está conectada: acércala al iPhone y abre la app.")
                        .dsFont(13).foregroundStyle(DS.t2)
                }
            } else {
                Text("Hay datos de esta mañana pero ningún sueño principal. Si dormiste, añade las horas y se calcula todo con ellas.")
                    .dsFont(13).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
                Button { adding = true } label: { Label("Añadir sueño", systemImage: "plus") }
                    .buttonStyle(DSButtonStyle(tint: DS.sueno, size: .small))
            }
        }
        .dsCard(padding: 16)
        .sheet(isPresented: $adding) {
            SleepEditSheet(session: nil, forDay: DayKey.string(Date())).environmentObject(model)
        }
    }
}
