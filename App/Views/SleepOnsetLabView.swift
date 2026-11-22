import SwiftUI
import PulsoAnalytics

/// Laboratorio → Dormirse (prueba en silencio): the running trial, a test nap, and each trial's live onset against
/// the downloaded one.
struct SleepOnsetLabView: View {
    @EnvironmentObject var model: AppModel
    @State private var napMinutes = 20

    var body: some View {
        let trials = Array(model.onsetTrials.reversed())
        let pairs = trials.map { OnsetPair(trial: $0, downloaded: model.downloadedOnset($0)) }
        let errors = pairs.compactMap { SleepOnsetWatch.errorMinutes(live: $0.trial.liveOnset, downloaded: $0.downloaded) }
        Form {
            Section {
                if let t = model.onsetTrial {
                    LabeledContent(t.kind == .nap ? "Siesta de prueba" : "Tras 4-7-8", value: "desde las \(Fmt.time(t.start))")
                    LabeledContent("Dormido según el directo", value: t.liveOnset.map { Fmt.time($0) } ?? "aún no")
                    if let w = t.wouldWakeAt { LabeledContent("Te habría despertado", value: Fmt.time(w)) }
                    Button("Terminar", role: .destructive) { model.finishOnsetTrial() }
                } else {
                    Stepper("Dormir \(napMinutes) min", value: $napMinutes, in: 10...90, step: 5)
                    Button("Empezar siesta de prueba") { model.startOnsetTrial(.nap, napMinutes: napMinutes) }
                        .disabled(!model.strapState.isConnected)
                }
                Toggle("Detectar tras Respiración para dormir", isOn: Binding(get: { model.onsetAfterBreathing },
                                                                             set: { model.onsetAfterBreathing = $0 }))
            } header: {
                Text("Ahora")
            } footer: {
                Text("La siesta de prueba no te despierta: pon tu alarma de siempre. Pulso solo apunta cuándo te dormiste y cuándo te habría despertado. El directo se apaga solo (10 min después de dormirte tras la 4-7-8, a la hora de despertar en la siesta, y como mucho a los 45 / 90 min).")
            }

            if !errors.isEmpty {
                Section("Error frente a la noche descargada") {
                    LabeledContent("Pruebas comparadas", value: "\(errors.count)")
                    LabeledContent("Error medio", value: String(format: "%.0f min", Stats.mean(errors.map(abs)) ?? 0))
                    LabeledContent("Sesgo", value: String(format: "%+.0f min", Stats.mean(errors) ?? 0))
                }
            }

            Section {
                if pairs.isEmpty {
                    Text("Aún no hay pruebas.").foregroundStyle(.secondary)
                }
                ForEach(pairs) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(p.trial.kind == .nap ? "Siesta" : "4-7-8") · \(Self.date(p.trial.start)) \(Fmt.time(p.trial.start))–\(Fmt.time(p.trial.end))")
                            .font(.subheadline.weight(.semibold))
                        HStack {
                            Text("Directo \(p.trial.liveOnset.map { Fmt.time($0) } ?? "–")")
                            Text("Noche \(p.downloaded.map { Fmt.time($0) } ?? "sin descargar")")
                            if let e = SleepOnsetWatch.errorMinutes(live: p.trial.liveOnset, downloaded: p.downloaded) {
                                Text(String(format: "%+.0f min", e)).foregroundStyle(abs(e) <= 10 ? .green : .orange)
                            }
                        }
                        .font(.caption.monospacedDigit())
                        if let w = p.trial.wouldWakeAt {
                            Text("Habría despertado a las \(Fmt.time(w))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Pruebas")
            } footer: {
                Text("«Noche» es el primer minuto dormido del sueño descargado y analizado por segundo. Una captura de esta pantalla cada pocos días basta para ajustar la regla.")
            }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
        .pulsoTitle("Dormirse (prueba)")
    }

    private struct OnsetPair: Identifiable {
        var trial: SleepOnsetWatch.Trial
        var downloaded: Int?
        var id: Int { trial.id }
    }

    private static func date(_ ts: Int) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
