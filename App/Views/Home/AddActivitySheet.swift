import SwiftUI
import PulsoStore
import PulsoIntegrations

/// "+ AGREGAR ACTIVIDAD": a workout the strap didn't detect (or you want named). Strain, heart rate and
/// zones are then computed from the strap's own data for that window.
struct AddActivitySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sport = "Carrera"
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var minutes = 45
    @State private var notes = ""

    private var end: Date { start.addingTimeInterval(Double(minutes) * 60) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Deporte", selection: $sport) {
                        ForEach(SportCatalog.all) { s in
                            Label(s.name, systemImage: s.symbol).tag(s.name)
                        }
                    }
                    DatePicker("Empezó", selection: $start, in: ...Date())
                    Stepper("Duración: \(Fmt.hmm(Double(minutes))) h", value: $minutes, in: 5...600, step: 5)
                    TextField("Notas (opcional)", text: $notes, axis: .vertical)
                } footer: {
                    Text("Termina a las \(Fmt.clock(end)). Si llevabas la pulsera, Pulso calcula el esfuerzo, el pulso y las zonas con lo que midió en ese rato.")
                }
                if end > Date() {
                    Section {
                        Label("Termina en el futuro: ajusta el inicio o la duración.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.yellow)
                    }
                }
            }
            .navigationTitle("Agregar actividad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let w = Workout(start: Int(start.timeIntervalSince1970), end: Int(end.timeIntervalSince1970), sport: sport,
                                        source: .manual, notes: notes)
                        model.saveWorkout(w)
                        dismiss()
                    }
                    .disabled(end > Date())
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
