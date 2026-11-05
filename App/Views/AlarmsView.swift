import SwiftUI
import PulsoStore
import PulsoFeatures

/// All alarms, with the next one on top.
struct AlarmsView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: AlarmConfig?

    var body: some View {
        List {
            Group {
            if let status = model.alarmStatus {
                Section {
                    Label(status, systemImage: model.alarmRinging ? "alarm.waves.left.and.right" : "alarm")
                        .font(.subheadline)
                    if model.alarmRinging {
                        Button("Posponer") { model.alarmSnooze() }
                        Button("Apagar", role: .destructive) { model.alarmStop() }
                    }
                } header: {
                    Text("Próxima")
                }
            }
            Section {
                if model.alarms.isEmpty {
                    Text("Sin alarmas. Pulsa + para crear una.").foregroundStyle(Theme.secondary)
                }
                ForEach(model.alarms) { a in
                    Button {
                        editing = a
                    } label: {
                        AlarmRow(alarm: a)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { model.deleteAlarm(id: a.id) } label: { Label("Borrar", systemImage: "trash") }
                        if a.isRepeating && a.enabled {
                            Button { model.skipNext(id: a.id) } label: {
                                Label(a.skipDay == nil ? "Saltar" : "No saltar", systemImage: "forward.end")
                            }
                            .tint(Theme.yellow)
                        }
                    }
                }
            } header: {
                Text("Alarmas")
            } footer: {
                Text("La pulsera vibra primero. Si no te despiertas, suena el iPhone\(model.alarmBackup.usesSystemAlarm ? " como una alarma del sistema, aunque esté en silencio" : " con avisos repetidos"). Doble toque en la pulsera para posponer o apagar.")
            }
            WakeCallTestSection()
            Section {
                NavigationLink {
                    SmartAlarmHelp()
                } label: {
                    Label("Cómo funciona la alarma inteligente", systemImage: "questionmark.circle")
                }
            }
                    }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
        .pulsoTitle("Despertador")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = AlarmConfig()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { a in
            NavigationStack { AlarmEditor(alarm: a) }
                .environmentObject(model)
        }
    }
}

struct AlarmRow: View {
    @EnvironmentObject var model: AppModel
    let alarm: AlarmConfig

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(bigTime)
                    .scaledFont(38, weight: .semibold, design: .rounded, relativeTo: .largeTitle)
                    .monospacedDigit()
                    .foregroundStyle(alarm.enabled ? .white : Theme.tertiary)
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { alarm.enabled }, set: { model.toggleAlarm(id: alarm.id, on: $0) }))
                .labelsHidden()
        }
        .contentShape(Rectangle())
    }

    /// With per-day times, the time of the next occurrence.
    private var bigTime: String {
        guard alarm.hasDayTimes, let p = AlarmPlanner.next(alarm, after: Date()) else { return alarm.timeText }
        let c = Calendar.current.dateComponents([.hour, .minute], from: p.latest)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var subtitle: String {
        var parts = [alarm.label, alarm.hasDayTimes ? alarm.dayTimesText : alarm.daysText]
        switch alarm.mode {
        case .fixed: break
        case .smart: parts.append("inteligente \(alarm.windowMinutes) min")
        case .sleepGoal: parts.append("según tu sueño")
        }
        if let s = alarm.skipDay { parts.append("salta \(Fmt.dayTitle(s).lowercased())") }
        return parts.joined(separator: " · ")
    }
}

struct AlarmEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var alarm: AlarmConfig
    @State private var time = Date()
    @State private var perDay = false

    private static let weekdayOrder: [(Int, String)] = [(2, "L"), (3, "M"), (4, "X"), (5, "J"), (6, "V"), (7, "S"), (1, "D")]
    private static let weekdayNames = [2: "Lunes", 3: "Martes", 4: "Miércoles", 5: "Jueves", 6: "Viernes", 7: "Sábado", 1: "Domingo"]

    /// Time of `weekday` in the per-day list (the general time until it is changed).
    private func dayTime(_ weekday: Int) -> Binding<Date> {
        Binding(get: {
            guard let m = alarm.dayTimes[weekday] else { return time }
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? time
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            alarm.dayTimes[weekday] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }

    var body: some View {
        Form {
            Group {
            Section {
                if !perDay {
                    DatePicker(alarm.mode == .fixed ? "Hora" : "No más tarde de", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                TextField("Nombre", text: $alarm.label)
                HStack(spacing: 6) {
                    ForEach(Self.weekdayOrder, id: \.0) { d in
                        let on = alarm.weekdays.contains(d.0)
                        Button {
                            if on { alarm.weekdays.removeAll { $0 == d.0 } } else { alarm.weekdays.append(d.0) }
                        } label: {
                            Text(d.1)
                                .font(.subheadline.bold())
                                .frame(width: 36, height: 36)
                                .background(on ? Theme.green : Theme.cardHighlight, in: Circle())
                                .foregroundStyle(on ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                Text(alarm.weekdays.isEmpty ? "Sin días marcados: sonará una sola vez." : alarm.daysText)
                    .font(.caption).foregroundStyle(Theme.secondary)
                if !alarm.weekdays.isEmpty {
                    Toggle("Hora distinta cada día", isOn: $perDay)
                }
                if perDay && !alarm.weekdays.isEmpty {
                    ForEach(Self.weekdayOrder.filter { alarm.weekdays.contains($0.0) }, id: \.0) { d in
                        DatePicker(Self.weekdayNames[d.0] ?? d.1, selection: dayTime(d.0), displayedComponents: .hourAndMinute)
                    }
                }
            }

            Section {
                Picker("Modo", selection: $alarm.mode) {
                    ForEach(WakeMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if alarm.mode != .fixed {
                    Stepper("Ventana: \(alarm.windowMinutes) min", value: $alarm.windowMinutes, in: 10...60, step: 5)
                }
            } header: {
                Text("Cómo despertarte")
            } footer: {
                Text(modeFooter)
            }

            Section {
                Picker("Vibración", selection: $alarm.vibration) {
                    ForEach(VibrationStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Button {
                    model.enqueueHaptics(Array(HapticPlan.ring(alarm.vibration, duration: 12)))
                } label: {
                    Label("Probar en la pulsera", systemImage: "iphone.radiowaves.left.and.right")
                }
                .disabled(!model.strapState.isConnected)
                Picker("Doble toque", selection: $alarm.doubleTap) {
                    ForEach(AlarmDoubleTap.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper("Posponer: \(alarm.snoozeMinutes) min", value: $alarm.snoozeMinutes, in: 3...30)
                Stepper("Máx. repeticiones: \(alarm.maxSnoozes)", value: $alarm.maxSnoozes, in: 0...10)
            } header: {
                Text("Pulsera")
            }

            Section {
                Toggle("Respaldo en el iPhone", isOn: $alarm.phoneBackup)
                if alarm.phoneBackup {
                    Stepper("Suena \(alarm.phoneBackupDelay) min después", value: $alarm.phoneBackupDelay, in: 0...15)
                }
                Toggle("Informe al despertar", isOn: $alarm.morningReport)
            } header: {
                Text("iPhone")
            } footer: {
                Text("Si la pulsera no consigue despertarte, el iPhone suena unos minutos después. El informe te dice tu recuperación y lo que has dormido.")
            }

            if model.alarms.contains(where: { $0.id == alarm.id }) {
                Section {
                    Button("Borrar alarma", role: .destructive) {
                        model.deleteAlarm(id: alarm.id)
                        dismiss()
                    }
                }
            }
                    }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
        .pulsoTitle(model.alarms.contains(where: { $0.id == alarm.id }) ? "Editar alarma" : "Nueva alarma")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            time = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()) ?? Date()
            perDay = alarm.hasDayTimes
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                    alarm.hour = c.hour ?? 7
                    alarm.minute = c.minute ?? 0
                    if perDay && !alarm.weekdays.isEmpty {
                        // Every marked day gets an explicit time; unmarked days are dropped.
                        let base = alarm.hour * 60 + alarm.minute
                        alarm.dayTimes = Dictionary(uniqueKeysWithValues: alarm.weekdays.map { ($0, alarm.dayTimes[$0] ?? base) })
                        if Set(alarm.dayTimes.values).count == 1, let only = alarm.dayTimes.values.first {
                            // All the same after all: keep it as a plain alarm at that time.
                            alarm.hour = only / 60
                            alarm.minute = only % 60
                            alarm.dayTimes = [:]
                        }
                    } else {
                        alarm.dayTimes = [:]
                    }
                    alarm.enabled = true
                    alarm.skipDay = nil
                    model.saveAlarm(alarm)
                    dismiss()
                }
            }
        }
    }

    private var modeFooter: String {
        switch alarm.mode {
        case .fixed:
            return "Vibra exactamente a la hora elegida. Funciona con el iPhone bloqueado si dejas Pulso en segundo plano (sin cerrarla): un minuto antes, la pulsera despierta a la app."
        case .smart:
            return "Durante los \(alarm.windowMinutes) min antes de la hora, Pulso mira tu sueño y vibra cuando estés en sueño ligero. Te despiertas más despejado."
        case .sleepGoal:
            return "Vibra cuando hayas dormido lo que necesitas (según tu esfuerzo y tu deuda de sueño), siempre dentro de la ventana y nunca después de la hora elegida."
        }
    }
}

struct SmartAlarmHelp: View {
    var body: some View {
        List {
            Group {
            Section {
                Text("Durante la ventana de despertar, Pulso descarga cada par de minutos lo último que ha medido la pulsera (movimiento, pulso, su propio estado de sueño) y busca señales de sueño ligero: te mueves, el pulso sube sobre el mínimo de la noche o el ritmo se vuelve irregular, como en el sueño REM.")
                Text("Si no encuentra un buen momento, vibra igualmente a la hora final. Si algo falla, suena el iPhone de respaldo.")
                Text("Con el iPhone bloqueado, iOS duerme a Pulso. Un minuto antes de la ventana, la pulsera hace saltar una alarma propia sin vibración que la despierta; desde ahí lee tu pulso en directo solo durante la ventana y mientras suena. El resto de la noche no le pide nada a la pulsera.")
            }
            Section("Consejos") {
                Text("Deja el iPhone cerca de la cama con Bluetooth activado y Pulso abierta en segundo plano (no la cierres deslizando).")
                Text("Una ventana de 30 minutos funciona bien para la mayoría.")
                Text("La vibración progresiva empieza suave y va subiendo: es la más agradable para despertar.")
            }
                    }
            .listRowBackground(Theme.card)
        }
        .pulsoList()
        .font(.subheadline)
        .pulsoTitle("Alarma inteligente")
    }
}

/// The strap's silent alarm wakes Pulso before each alarm; this checks, once, that the 5.0 really does it.
struct WakeCallTestSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            switch model.wakeCallTest {
            case nil:
                Button {
                    model.startWakeCallTest()
                } label: {
                    Label(model.wakeCallVerified ? "Volver a probar" : "Probar ahora (1 min)", systemImage: "bell.badge")
                }
            case .armed(let at), .confirmed(let at):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Bloquea el iPhone y espera", systemImage: "lock")
                        .font(.subheadline.weight(.semibold))
                    Text(model.wakeCallTest == .confirmed(at)
                         ? "La pulsera ha aceptado la alarma. Salta a las \(Fmt.time(Int(at.timeIntervalSince1970)))."
                         : "Enviando la alarma a la pulsera para las \(Fmt.time(Int(at.timeIntervalSince1970)))…")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            case .worked:
                Label("Funciona: la pulsera ha despertado a Pulso", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
                Button("Volver a probar") { model.wakeCallTest = nil }
            case .failed(let why):
                Label(why, systemImage: "xmark.circle.fill")
                    .foregroundStyle(Theme.red)
                Button("Volver a probar") { model.wakeCallTest = nil }
            }
        } header: {
            Text("Despertador de la pulsera")
        } footer: {
            Text("Antes de cada alarma, la pulsera hace saltar una alarma propia sin vibración que despierta a Pulso aunque el iPhone esté bloqueado. Así Pulso solo lee tu pulso en directo durante la ventana y mientras suena. Para probarlo: pulsa, bloquea el iPhone y espera un minuto. Si funciona, te llega una notificación. Fíjate también en si la pulsera vibra: no debería.")
        }
    }
}
