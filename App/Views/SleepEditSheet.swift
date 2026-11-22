import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

struct SleepEditSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: SleepSession?
    /// The day whose night is being added (the night that ends that morning); defaults to the selected day.
    var forDay: String?
    var napDefault = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var isNap = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
            Group {
                Section {
                    DatePicker("Me dormí", selection: $start)
                    DatePicker("Me desperté", selection: $end)
                    if session == nil { Toggle("Es una siesta", isOn: $isNap) }
                } footer: {
                    Text("Las fases, la VFC y la recuperación se recalculan con las horas que indiques.")
                }
                if session != nil {
                    Section {
                        Button("Eliminar este sueño", role: .destructive) { confirmDelete = true }
                    }
                }
                        }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
            .pulsoTitle(session == nil ? "Añadir sueño" : "Ajustar sueño")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let s = session {
                            model.saveSleepEdit(s, start: start, end: end)
                        } else {
                            model.addManualSleep(start: start, end: end, nap: isNap)
                        }
                        dismiss()
                    }
                    .disabled(end <= start || end.timeIntervalSince(start) > 16 * 3600)
                }
            }
            .confirmationDialog("¿Eliminar este sueño?", isPresented: $confirmDelete) {
                Button("Eliminar", role: .destructive) {
                    if let s = session { model.deleteSleep(s) }
                    dismiss()
                }
            }
            .onAppear {
                if let s = session {
                    start = Date(timeIntervalSince1970: TimeInterval(s.start))
                    end = Date(timeIntervalSince1970: TimeInterval(s.end))
                } else if let d = DayKey.date(forDay ?? model.selectedDay) {
                    isNap = napDefault
                    start = d.addingTimeInterval(napDefault ? 15 * 3600 : -60 * 60)
                    end = d.addingTimeInterval(napDefault ? 15.5 * 3600 : 7 * 3600)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
