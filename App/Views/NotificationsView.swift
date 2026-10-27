import SwiftUI
import PulsoFeatures

/// Which alerts to receive, which also vibrate the strap, and quiet hours.
struct NotificationsView: View {
    @EnvironmentObject var model: AppModel
    @State private var prefs = AlertPreferences()
    @State private var quietStart = Date()
    @State private var quietEnd = Date()
    @State private var loaded = false

    private let groups: [(String, [AlertKind])] = [
        ("Cada día", [.morningReport, .bedtime, .caffeine, .weekly]),
        ("Salud", [.illness, .trend, .stress]),
        ("Actividad", [.strainReached, .overreaching, .inactivity]),
        ("Pulsera", [.batteryLow, .offWrist, .syncStale]),
    ]

    var body: some View {
        Form {
            Group {
            ForEach(groups, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1, id: \.self) { kind in
                        row(kind)
                    }
                }
            }
            Section {
                Stepper("Aviso de dormir \(prefs.bedtimeLeadMinutes) min antes", value: $prefs.bedtimeLeadMinutes, in: 0...120, step: 15)
                Stepper("Sin pulsera tras \(prefs.offWristMinutes) min", value: $prefs.offWristMinutes, in: 15...240, step: 15)
                Stepper("Quieto tras \(prefs.inactivityMinutes) min", value: $prefs.inactivityMinutes, in: 30...180, step: 15)
                Stepper("Batería baja por debajo del \(prefs.batteryThreshold) %", value: $prefs.batteryThreshold, in: 5...50, step: 5)
            } header: {
                Text("Ajustes")
            }
            Section {
                DatePicker("Desde", selection: $quietStart, displayedComponents: .hourAndMinute)
                DatePicker("Hasta", selection: $quietEnd, displayedComponents: .hourAndMinute)
            } header: {
                Text("Horas de silencio")
            } footer: {
                Text("Los avisos que pueden esperar (batería, tendencias…) se guardan hasta el final de las horas de silencio. El informe al despertar, la hora de acostarse y las alarmas no se ven afectados.")
            }
                    }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
        .pulsoTitle("Avisos")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            prefs = model.alertPrefs
            quietStart = Self.date(minutes: prefs.quietStart)
            quietEnd = Self.date(minutes: prefs.quietEnd)
        }
        .onDisappear { save() }
    }

    private func row(_ kind: AlertKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { prefs.isOn(kind) }, set: { prefs.enabled[kind] = $0 })) {
                Label(kind.label, systemImage: kind.icon)
            }
            if prefs.isOn(kind) {
                Toggle(isOn: Binding(get: { prefs.buzzes(kind) }, set: { prefs.strapBuzz[kind] = $0 })) {
                    Text("Vibrar también la pulsera").font(.caption).foregroundStyle(Theme.secondary)
                }
                .padding(.leading, 34)
            }
        }
    }

    private func save() {
        let s = Calendar.current.dateComponents([.hour, .minute], from: quietStart)
        let e = Calendar.current.dateComponents([.hour, .minute], from: quietEnd)
        prefs.quietStart = (s.hour ?? 23) * 60 + (s.minute ?? 0)
        prefs.quietEnd = (e.hour ?? 7) * 60 + (e.minute ?? 0)
        model.saveAlertPrefs(prefs)
    }

    static func date(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
}
