import SwiftUI
import PulsoStore
import PulsoFeatures

/// «Despertador» (studio B-sueno 14, 16, 17): the next alarm (or the one ringing), every alarm, the band's wake-up
/// test and the guide. Only the UI: the alarm logic lives in `AppModel+Alarms`.
struct AlarmsView: View {
    @EnvironmentObject var model: AppModel
    /// Screenshot runs only: a state drawn without touching the model.
    var demo: SuenoDemo?
    var back: String? = "Sueño"
    @State private var editing: AlarmConfig?

    var body: some View {
        DSScreen("Despertador", back: back) {
            Button { editing = AlarmConfig() } label: { DSCircleButton(icon: "plus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Nueva alarma")
        } content: {
            if model.alarmRinging || demo == .ringing {
                DSSectionHeader("Próxima")
                ringingCard
            } else if let next = model.nextAlarm {
                DSSectionHeader("Próxima")
                nextCard(next)
            }
            DSSectionHeader("Alarmas")
            if model.alarms.isEmpty {
                Text("Sin alarmas. Pulsa + para crear una.").dsFont(15).foregroundStyle(DS.t2).dsCard(padding: 16)
            } else {
                DSGroup(footer: "Vibra la pulsera; si no te despiertas, suena el iPhone\(model.alarmBackup.usesSystemAlarm ? " aunque esté en silencio" : ""). Doble toque en la pulsera para posponer o apagar.") {
                    ForEach(model.alarms) { a in
                        Button { editing = a } label: { AlarmRow(alarm: a) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if a.isRepeating && a.enabled {
                                    Button { model.skipNext(id: a.id) } label: {
                                        Label(a.skipDay == nil ? "Saltar la próxima" : "No saltar", systemImage: "forward.end")
                                    }
                                }
                                Button(role: .destructive) { model.deleteAlarm(id: a.id) } label: { Label("Borrar", systemImage: "trash") }
                            }
                            .dsRowInset(14)
                    }
                }
            }
            DSSectionHeader("Despertador de la pulsera")
            WakeCallTestCard(demo: demo == .bandTest ? .confirmed(Date().addingTimeInterval(60)) : nil)
            NavigationLink { SmartAlarmHelp() } label: {
                HStack {
                    Text("Cómo funciona la alarma inteligente").dsFont(16).foregroundStyle(DS.t1)
                    Spacer()
                    DSChevron()
                }
                .padding(.horizontal, 16).frame(minHeight: 52)
                .dsCard(padding: 0)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .sheet(item: $editing) { a in
            NavigationStack { AlarmEditor(alarm: a) }
                .environmentObject(model)
        }
    }

    // MARK: Next

    private func dayWord(_ key: String) -> String {
        let today = DayKey.string(Date())
        if key == today { return "hoy" }
        if key == DayKey.shift(today, days: 1) { return "mañana" }
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE"
        return f.string(from: d)
    }

    private func nextCard(_ next: PlannedAlarm) -> some View {
        let start = next.isSmart ? next.earliest : next.latest
        let left = max(0, start.timeIntervalSinceNow / 60)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "alarm").font(.system(size: 13)).foregroundStyle(DS.sueno)
                        Text("\(next.alarm.label) · \(dayWord(next.dayKey))").dsFont(15).foregroundStyle(DS.t2).lineLimit(1)
                    }
                    Text(next.isSmart ? "desde las \(Fmt.clock(next.earliest))" : "a las \(Fmt.clock(next.latest))")
                        .dsFont(24, .semibold).foregroundStyle(DS.t1)
                }
                Spacer(minLength: 8)
                Text("en \(DSFmt.duration(left))").dsFont(15, .semibold).foregroundStyle(DS.t2)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(DS.fill, in: Capsule())
            }
            if let status = model.alarmStatus, model.wakeSession?.state != .waiting {
                Text(status).dsFont(14).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
            }
            if next.isSmart { AlarmWindowBar(earliest: next.earliest, latest: next.latest) }
        }
        .dsCard(padding: 16)
    }

    // MARK: Ringing

    private var ringingCard: some View {
        let session = model.wakeSession
        let planned = session?.planned ?? model.nextAlarm
        let alarm = planned?.alarm
        let early = session?.wokeEarlyBy
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                HoyDot(color: DS.sueno, size: 9).padding(.top, 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sonando").dsFont(20, .semibold).foregroundStyle(DS.t1)
                    if let early, early >= 60 {
                        Text("Te despierta en sueño ligero, \(early / 60) min antes de la hora final")
                            .dsFont(15).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
                    } else if demo == nil, let status = model.alarmStatus {
                        Text(status).dsFont(15).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let p = planned, p.isSmart {
                AlarmWindowBar(earliest: p.earliest, latest: p.latest,
                               marker: (early ?? 0) >= 60 ? p.latest.addingTimeInterval(-Double(early ?? 0)) : nil)
            }
            HStack(spacing: 10) {
                Button { if demo == nil { model.alarmSnooze() } } label: {
                    Text("Posponer \(alarm?.snoozeMinutes ?? 9) min").frame(maxWidth: .infinity)
                }
                .buttonStyle(DSButtonStyle(tint: DS.sueno, fullWidth: true))
                Button { if demo == nil { model.alarmStop() } } label: {
                    Text("Apagar").foregroundStyle(DSLevel.baja.ink).frame(maxWidth: .infinity)
                }
                .buttonStyle(DSButtonStyle(gray: true, fullWidth: true))
            }
            Text("Doble toque en la pulsera para \(alarm?.doubleTap == .stop ? "apagar" : "posponer")")
                .dsFont(14, .semibold).foregroundStyle(DS.t2).frame(maxWidth: .infinity)
        }
        .dsCard(padding: 16)
    }
}

/// The smart window on a short time line: half an hour either side, the window in violet, an optional mark.
struct AlarmWindowBar: View {
    let earliest: Date
    let latest: Date
    var marker: Date?

    var body: some View {
        let a = earliest.addingTimeInterval(-1800), b = latest.addingTimeInterval(1800)
        let total = max(b.timeIntervalSince(a), 1)
        GeometryReader { g in
            let w = g.size.width - 40
            let x = { (d: Date) in 20 + w * CGFloat(d.timeIntervalSince(a) / total) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(DS.fill).frame(width: w, height: 6).position(x: g.size.width / 2, y: 24)
                Capsule().fill(DS.sueno).frame(width: max(6, x(latest) - x(earliest)), height: 14)
                    .position(x: (x(earliest) + x(latest)) / 2, y: 24)
                if let marker {
                    Text("sueño ligero").dsFont(11, .semibold).foregroundStyle(DS.t1).fixedSize().position(x: x(marker), y: 6)
                    Rectangle().fill(DS.t1).frame(width: 2, height: 20).position(x: x(marker), y: 24)
                }
                Text(Fmt.clock(a)).position(x: 20, y: 44)
                if marker == nil { Text(Fmt.clock(a.addingTimeInterval(total / 2))).position(x: g.size.width / 2, y: 44) }
                Text(Fmt.clock(b)).position(x: g.size.width - 20, y: 44)
            }
            .dsFont(12, .medium)
            .foregroundStyle(DS.t3)
        }
        .frame(height: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ventana de \(Fmt.clock(earliest)) a \(Fmt.clock(latest))")
    }
}

struct AlarmRow: View {
    @EnvironmentObject var model: AppModel
    let alarm: AlarmConfig

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(bigTime).dsFont(46, .regular, relativeTo: .largeTitle, maxScale: 1.2)
                    .foregroundStyle(alarm.enabled ? DS.t1 : DS.t3)
                Text(subtitle).dsFont(14).foregroundStyle(DS.t2).lineLimit(2)
            }
            Spacer()
            Toggle("Activa", isOn: Binding(get: { alarm.enabled }, set: { model.toggleAlarm(id: alarm.id, on: $0) }))
                .labelsHidden()
                .tint(DS.sueno)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// With per-day times, the time of the next occurrence.
    private var bigTime: String {
        guard alarm.hasDayTimes, let p = AlarmPlanner.next(alarm, after: Date()) else { return alarm.timeText }
        let c = Calendar.current.dateComponents([.hour, .minute], from: p.latest)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var subtitle: String {
        var parts = [alarm.label, alarm.hasDayTimes ? alarm.dayTimesText : (alarm.weekdays.isEmpty ? "una vez" : alarm.daysText)]
        switch alarm.mode {
        case .fixed: break
        case .smart: parts.append("inteligente \(alarm.windowMinutes) min")
        case .sleepGoal: parts.append("según tu sueño")
        }
        if let s = alarm.skipDay { parts.append("salta \(Fmt.dayTitle(s).lowercased())") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Editor (15)

struct AlarmEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var alarm: AlarmConfig
    @State private var time = Date()
    @State private var perDay = false

    private static let weekdayOrder: [(Int, String)] = [(2, "L"), (3, "M"), (4, "X"), (5, "J"), (6, "V"), (7, "S"), (1, "D")]
    private static let weekdayNames = [2: "Lunes", 3: "Martes", 4: "Miércoles", 5: "Jueves", 6: "Viernes", 7: "Sábado", 1: "Domingo"]

    private var exists: Bool { model.alarms.contains(where: { $0.id == alarm.id }) }

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
        VStack(spacing: 0) {
            ZStack {
                Text(exists ? "Editar alarma" : "Nueva alarma").dsFont(17, .semibold).foregroundStyle(DS.t1)
                HStack {
                    Button("Cancelar") { dismiss() }.foregroundStyle(DS.t1)
                    Spacer()
                    Button("Guardar", action: save).fontWeight(.semibold).foregroundStyle(DS.sueno)
                }
                .dsFont(17)
                .buttonStyle(.plain)
            }
            .frame(height: 50)
            .padding(.top, 12)
            .padding(.horizontal, DS.gutter)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.stack) {
                    if !perDay {
                        VStack(spacing: 0) {
                            Text(alarm.mode == .fixed ? "Hora" : "No más tarde de").dsFont(15, .semibold).foregroundStyle(DS.t2)
                            DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    DSGroup {
                        HStack {
                            Text("Nombre").dsFont(16).foregroundStyle(DS.t1)
                            TextField("Nombre", text: $alarm.label)
                                .multilineTextAlignment(.trailing)
                                .dsFont(16).foregroundStyle(DS.t2)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 50)
                        .dsRowInset(14)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 0) {
                                ForEach(Self.weekdayOrder, id: \.0) { d in
                                    let on = alarm.weekdays.contains(d.0)
                                    Button {
                                        if on { alarm.weekdays.removeAll { $0 == d.0 } } else { alarm.weekdays.append(d.0) }
                                    } label: {
                                        Text(d.1).dsFont(16, .semibold)
                                            .frame(width: 38, height: 38)
                                            .background(on ? DS.sueno : DS.fill, in: Circle())
                                            .foregroundStyle(on ? DS.t1 : DS.t2)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity)
                                    .accessibilityLabel(Self.weekdayNames[d.0] ?? d.1)
                                    .accessibilityAddTraits(on ? .isSelected : [])
                                }
                            }
                            Text(alarm.weekdays.isEmpty ? "Sin días marcados: sonará una sola vez." : alarm.daysText)
                                .dsFont(13).foregroundStyle(DS.t2)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .dsRowInset(14)
                        if !alarm.weekdays.isEmpty {
                            toggleRow("Hora distinta cada día", $perDay)
                        }
                        if perDay && !alarm.weekdays.isEmpty {
                            ForEach(Self.weekdayOrder.filter { alarm.weekdays.contains($0.0) }, id: \.0) { d in
                                HStack {
                                    Text(Self.weekdayNames[d.0] ?? d.1).dsFont(16).foregroundStyle(DS.t1)
                                    Spacer()
                                    DatePicker(Self.weekdayNames[d.0] ?? d.1, selection: dayTime(d.0), displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                }
                                .padding(.horizontal, 14).frame(minHeight: 50)
                                .dsRowInset(14)
                            }
                        }
                    }

                    DSGroupLabel("Cómo despertarte")
                    DSGroup(footer: modeFooter) {
                        ForEach(WakeMode.allCases, id: \.self) { m in
                            Button { alarm.mode = m } label: {
                                HStack {
                                    Text(m.label).dsFont(16).foregroundStyle(DS.t1)
                                    Spacer()
                                    if alarm.mode == m {
                                        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.sueno)
                                    }
                                }
                                .padding(.horizontal, 14).frame(minHeight: 50)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(alarm.mode == m ? .isSelected : [])
                            .dsRowInset(14)
                        }
                        if alarm.mode != .fixed {
                            stepRow("Ventana", "\(alarm.windowMinutes) min", $alarm.windowMinutes, 10...60, step: 5)
                        }
                    }
                    if alarm.mode != .fixed {
                        SmartWindowDrawing(start: windowStart, end: "hora final")
                            .frame(height: 96)
                            .dsCard(padding: 14)
                    }

                    DSGroupLabel("Pulsera")
                    DSGroup {
                        pickerRow("Vibración", $alarm.vibration, VibrationStyle.allCases) { $0.label }
                        Button {
                            model.enqueueHaptics(Array(HapticPlan.ring(alarm.vibration, duration: 12)))
                        } label: {
                            Label("Probar en la pulsera", systemImage: "applewatch.radiowaves.left.and.right")
                                .dsFont(16).foregroundStyle(model.strapState.isConnected ? DS.sueno : DS.t3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).frame(minHeight: 50)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.strapState.isConnected)
                        .dsRowInset(14)
                        pickerRow("Doble toque", $alarm.doubleTap, AlarmDoubleTap.allCases) { $0.label }
                        stepRow("Posponer", "\(alarm.snoozeMinutes) min", $alarm.snoozeMinutes, 3...30)
                        stepRow("Máx. repeticiones", "\(alarm.maxSnoozes)", $alarm.maxSnoozes, 0...10)
                    }

                    DSGroupLabel("iPhone")
                    DSGroup(footer: "Si la pulsera no consigue despertarte, el iPhone suena unos minutos después. El informe te dice tu recuperación y lo que has dormido.") {
                        toggleRow("Respaldo en el iPhone", $alarm.phoneBackup)
                        if alarm.phoneBackup {
                            stepRow("Suena", "\(alarm.phoneBackupDelay) min después", $alarm.phoneBackupDelay, 0...15)
                        }
                        toggleRow("Informe al despertar", $alarm.morningReport)
                    }

                    if exists {
                        Button {
                            model.deleteAlarm(id: alarm.id)
                            dismiss()
                        } label: {
                            Text("Borrar alarma").dsFont(17).foregroundStyle(DSLevel.baja.ink)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.sheet.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            time = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()) ?? Date()
            perDay = alarm.hasDayTimes
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.sheetRadius)
        .presentationBackground(DS.sheet)
        .preferredColorScheme(.dark)
    }

    /// Start of the smart window for the time on the wheel.
    private var windowStart: String {
        Fmt.clock(time.addingTimeInterval(-Double(alarm.windowMinutes) * 60))
    }

    private func save() {
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

    private func toggleRow(_ label: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) { Text(label).dsFont(16).foregroundStyle(DS.t1) }
            .tint(DS.sueno)
            .padding(.horizontal, 14).frame(minHeight: 50)
            .dsRowInset(14)
    }

    private func stepRow(_ label: String, _ value: String, _ v: Binding<Int>, _ range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack(spacing: 10) {
            Text(label).dsFont(16).foregroundStyle(DS.t1)
            Spacer()
            Text(value).dsFont(16).foregroundStyle(DS.t2).lineLimit(1)
            SuenoStepper(value: v, range: range, step: step)
        }
        .padding(.horizontal, 14).frame(minHeight: 52)
        .dsRowInset(14)
    }

    private func pickerRow<T: Hashable>(_ label: String, _ sel: Binding<T>, _ all: [T], _ name: @escaping (T) -> String) -> some View {
        HStack {
            Text(label).dsFont(16).foregroundStyle(DS.t1)
            Spacer()
            Menu {
                Picker(label, selection: sel) {
                    ForEach(all, id: \.self) { Text(name($0)).tag($0) }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(name(sel.wrappedValue)).dsFont(16)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DS.t2)
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
        .dsRowInset(14)
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

/// A drawing of how the smart window works (not data): sleep depth as a wave, the window shaded, the wake point in it.
struct SmartWindowDrawing: View {
    var start: String
    var end: String

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height - 20
            let wa = w * 0.58, wb = w * 0.86
            let wave = Path { p in
                let pts: [(CGFloat, CGFloat)] = [(0, 0.75), (0.15, 0.55), (0.3, 0.2), (0.45, 0.72), (0.58, 0.85),
                                                 (0.7, 0.45), (0.76, 0.2), (0.86, 0.5), (1, 0.4)]
                p.move(to: CGPoint(x: 0, y: h * pts[0].1))
                for i in 1..<pts.count {
                    let a = pts[i - 1], b = pts[i]
                    let mx = (a.0 + b.0) / 2 * w
                    p.addCurve(to: CGPoint(x: b.0 * w, y: h * b.1), control1: CGPoint(x: mx, y: h * a.1), control2: CGPoint(x: mx, y: h * b.1))
                }
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(DS.sueno.opacity(0.16))
                    .overlay(alignment: .leading) { Rectangle().fill(DS.sueno.opacity(0.5)).frame(width: 1) }
                    .overlay(alignment: .trailing) { Rectangle().fill(DS.sueno.opacity(0.5)).frame(width: 1) }
                    .frame(width: wb - wa, height: h).offset(x: wa)
                wave.stroke(DS.sueno, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(DS.card).overlay(Circle().stroke(DS.t1, lineWidth: 2)).frame(width: 12, height: 12)
                    .position(x: w * 0.76, y: h * 0.2)
                Text("vibra en sueño ligero").dsFont(11, .semibold).foregroundStyle(DS.t1).fixedSize()
                    .position(x: w * 0.76, y: max(6, h * 0.2 - 14))
                Text("ligero").dsFont(11).foregroundStyle(DS.t3).position(x: 18, y: 6)
                Text(start).dsFont(12, .medium).foregroundStyle(DS.t3).fixedSize().position(x: wa, y: h + 12)
                Text(end).dsFont(12, .medium).foregroundStyle(DS.t3).fixedSize().position(x: wb, y: h + 12)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Guide (18)

struct SmartAlarmHelp: View {
    var body: some View {
        DSScreen("Alarma inteligente", back: "Despertador") {
            SmartWindowDrawing(start: "inicio de la ventana", end: "hora final")
                .frame(height: 150)
                .dsCard(padding: 16)
            DSSectionHeader("Cómo decide")
            VStack(alignment: .leading, spacing: 0) {
                step(1, "Vigila", "Durante la ventana descarga cada par de minutos tu movimiento, tu pulso y el estado de sueño de la pulsera.")
                DSDivider().padding(.vertical, 12)
                step(2, "Elige", "Vibra cuando ve sueño ligero: te mueves, el pulso sube sobre el mínimo de la noche o se vuelve irregular, como en el REM.")
                DSDivider().padding(.vertical, 12)
                step(3, "Asegura", "Si no encuentra el momento, vibra a la hora final. Si algo falla, suena el iPhone.")
            }
            .dsCard(padding: 16)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.fill").font(.system(size: 16)).foregroundStyle(DS.t2).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Con el iPhone bloqueado").dsFont(17, .semibold).foregroundStyle(DS.t1)
                    Text("Un minuto antes de la ventana, la pulsera salta una alarma propia sin vibración que despierta a Pulso. Desde ahí lee tu pulso en directo solo durante la ventana y mientras suena.")
                        .dsFont(15).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .dsCard(padding: 16)
            DSSectionHeader("Consejos")
            VStack(alignment: .leading, spacing: 10) {
                tip("Deja el iPhone cerca de la cama con Bluetooth y Pulso abierta en segundo plano (no la cierres deslizando).")
                tip("Una ventana de 30 minutos funciona bien para la mayoría.")
                tip("La vibración progresiva empieza suave y va subiendo: es la más agradable para despertar.")
            }
            .dsCard(padding: 16)
        }
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").dsFont(14, .bold).foregroundStyle(DS.t1)
                .frame(width: 26, height: 26).background(DS.fill, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).dsFont(17, .semibold).foregroundStyle(DS.t1)
                Text(text).dsFont(15).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            HoyDot(color: DS.sueno).padding(.top, 7)
            Text(text).dsFont(15).foregroundStyle(DS.t1).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Band wake-up test (14, 16)

/// The strap's silent alarm wakes Pulso before each alarm; this checks, once, that the 5.0 really does it.
struct WakeCallTestCard: View {
    @EnvironmentObject var model: AppModel
    /// Screenshot runs only: the state to draw instead of the model's.
    var demo: WakeCallTest?

    var body: some View {
        let state = demo ?? model.wakeCallTest
        VStack(alignment: .leading, spacing: 14) {
            switch state {
            case nil:
                if model.wakeCallVerified {
                    header("checkmark.circle.fill", DSLevel.buena.ink, "Funciona", "La pulsera ha despertado a Pulso con el iPhone bloqueado.")
                    action("Volver a probar") { model.startWakeCallTest() }
                } else {
                    header("questionmark.circle", DSLevel.justa.ink, "Sin comprobar",
                           "Hasta que la prueba salga bien, cuenta con el aviso del iPhone. Pulsa, bloquea el iPhone y espera un minuto.")
                    action("Probar ahora (1 min)") { model.startWakeCallTest() }
                }
            case .armed(let at), .confirmed(let at):
                header("lock.fill", DS.t2, "Bloquea el iPhone y espera",
                       "Si funciona, te llega una notificación. La pulsera no debería vibrar.")
                VStack(alignment: .leading, spacing: 10) {
                    stepRow(true, "Alarma enviada a la pulsera")
                    stepRow(state == .confirmed(at), "Aceptada · salta a las \(Fmt.time(Int(at.timeIntervalSince1970)))")
                    stepRow(false, "Despierta a Pulso")
                }
                .padding(.leading, 34)
            case .worked:
                header("checkmark.circle.fill", DSLevel.buena.ink, "Funciona", "La pulsera ha despertado a Pulso con el iPhone bloqueado.")
                action("Volver a probar") { model.wakeCallTest = nil }
            case .failed(let why):
                header("xmark.circle.fill", DSLevel.baja.ink, "No ha funcionado", why)
                action("Volver a probar") { model.wakeCallTest = nil }
            }
        }
        .dsCard(padding: 16)
    }

    private func header(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color).frame(width: 22).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).dsFont(18, .semibold).foregroundStyle(color == DS.t2 ? DS.t1 : color)
                Text(text).dsFont(15).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func action(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(DSButtonStyle(size: .small, gray: true, fullWidth: true))
    }

    private func stepRow(_ done: Bool, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 16))
                .foregroundStyle(done ? DSLevel.buena.ink : DS.t3)
            Text(text).dsFont(15).foregroundStyle(done ? DS.t1 : DS.t2)
        }
    }
}
