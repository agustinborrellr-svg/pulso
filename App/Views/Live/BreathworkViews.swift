import SwiftUI
import UIKit
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoIntelligence

// MARK: - What each session is

/// Texts, colour and icon of each guided-breathing session.
struct BreathworkInfo {
    let kind: Breathwork.Kind
    let title: String
    let goal: String
    let short: String
    let icon: String
    let color: Color
    let about: String
    let benefitsTitle: String
    let benefits: String
    let prep: String
    let disclaimer: String

    static func of(_ kind: Breathwork.Kind) -> BreathworkInfo {
        let calmPrep = "Siéntate cómodo o túmbate. Puedes cerrar los ojos: la pulsera vibra en cada cambio de fase."
        let calmDisclaimer = "Si notas mareo, para y respira con normalidad. No lo hagas conduciendo ni en el agua."
        switch kind {
        case .alert:
            return BreathworkInfo(
                kind: kind, title: Breathwork.activityName(kind), goal: "Actívate",
                short: "Respiración rápida con retenciones: más energía y foco en 5 minutos.",
                icon: "gauge.with.dots.needle.67percent", color: ActBreath.color(kind),
                about: "Series de respiraciones rápidas y profundas, una retención con los pulmones vacíos y una inspiración final que aguantas arriba. Activa tu sistema nervioso simpático: sube el pulso, libera adrenalina y te deja despierto y con energía.",
                benefitsTitle: "Beneficios de la hiperventilación cíclica",
                benefits: "Una dosis corta y controlada de estrés entrena tu tolerancia a otras formas de estrés (hormesis). Va bien antes de entrenar, de estudiar o cuando te falta energía. Pulso cronometra cada retención y te enseña cómo baja tu pulso mientras aguantas.",
                prep: "Siéntate o recuéstate por si te mareas.",
                disclaimer: "No lo hagas en el agua ni conduciendo. Evítalo si estás embarazada, tienes la tensión alta, te recuperas de una operación o tienes antecedentes de problemas graves como insuficiencia cardíaca, epilepsia o ictus.")
        case .sigh:
            return BreathworkInfo(
                kind: kind, title: Breathwork.activityName(kind), goal: "Cálmate",
                short: "Doble inspiración y espiración larga: la forma más rápida de bajar pulsaciones.",
                icon: "wind", color: ActBreath.color(kind),
                about: "Dos inspiraciones por la nariz, una larga y otra corta para llenar del todo, y una espiración lenta y larga por la boca. Vacía el aire viejo de los pulmones y frena el corazón en cada espiración.",
                benefitsTitle: "Por qué funciona",
                benefits: "En un estudio de Stanford (Balban y cols., Cell Reports Medicine 2023), 5 minutos al día de suspiro cíclico mejoraron el ánimo y bajaron la respiración en reposo más que la meditación. Pulso te enseña cuánto bajan tu pulso y tu estrés.",
                prep: calmPrep, disclaimer: calmDisclaimer)
        case .coherence:
            return BreathworkInfo(
                kind: kind, title: Breathwork.activityName(kind), goal: "Cálmate",
                short: "Unas 6 respiraciones por minuto: tu pulso y tu respiración se sincronizan.",
                icon: "waveform.path.ecg", color: ActBreath.color(kind),
                about: "Respiras despacio a un ritmo fijo, unas 6 veces por minuto. A ese ritmo el pulso sube al inspirar y baja al espirar con la máxima amplitud (frecuencia de resonancia) y tu VFC se dispara.",
                benefitsTitle: "Por qué funciona",
                benefits: "La respiración a frecuencia de resonancia (Lehrer) se usa en biofeedback para la ansiedad, la tensión arterial y la recuperación. Pulso compara tu VFC y tu estrés antes y después.",
                prep: calmPrep, disclaimer: calmDisclaimer)
        case .box:
            return BreathworkInfo(
                kind: kind, title: Breathwork.activityName(kind), goal: "Cálmate",
                short: "4-4-4-4: la cabeza fría antes de algo importante.",
                icon: "square", color: ActBreath.color(kind),
                about: "Cuatro tiempos iguales: inhalar, aguantar, exhalar y aguantar. Un ritmo lento y predecible que calma sin adormecer.",
                benefitsTitle: "Cuándo usarla",
                benefits: "Para mantener la calma bajo presión: un examen, una competición, hablar en público. Pulso mide cuánto baja tu estrés.",
                prep: calmPrep, disclaimer: calmDisclaimer)
        case .sleep:
            return BreathworkInfo(
                kind: kind, title: Breathwork.activityName(kind), goal: "Duerme",
                short: "4-7-8 en la cama: suelta el día y baja pulsaciones.",
                icon: "moon.stars", color: ActBreath.color(kind),
                about: "Inhala 4 segundos, aguanta 7 y exhala 8. La espiración larga activa el sistema parasimpático y ayuda a soltar el día.",
                benefitsTitle: "Cómo sacarle partido",
                benefits: "Hazlo ya en la cama con la luz apagada: la pulsera marca cada fase con una vibración para que no tengas que mirar la pantalla. Con el tiempo, el impacto en tu recuperación te dirá si duermes mejor los días que la haces.",
                prep: "Túmbate en la cama con la luz apagada. Cierra los ojos y sigue la vibración de la pulsera.",
                disclaimer: calmDisclaimer)
        }
    }

    /// What to do in each phase, with the colour of its bullet.
    func instructions(_ step: Breathwork.Step, afterRetention: Bool) -> [(String, Color)] {
        let inC = DS.act, outC = DS.recarga
        switch (kind, step.phase) {
        case (.alert, .inhale):
            return afterRetention ? [("Inhala hondo y aguanta arriba.", inC)]
                : [("Inhala enérgicamente por la nariz.", inC), ("Exhala pasivamente por la boca.", outC)]
        case (.alert, .exhale):
            return step.count == nil ? [("Suelta el aire despacio.", outC)]
                : [("Inhala enérgicamente por la nariz.", inC), ("Exhala pasivamente por la boca.", outC)]
        case (.alert, .holdOut): return [("Exhala por la boca. Vacía los pulmones por completo.", outC)]
        case (_, .retention): return [("Aguanta con los pulmones vacíos hasta que necesites respirar.", outC)]
        case (.alert, .holdIn): return [("Aguanta en la parte alta de la inspiración.", inC)]
        case (.sigh, .inhale): return [("Inhala por la nariz.", inC)]
        case (_, .topUp): return [("Otra pequeña inhalación para llenar del todo.", inC)]
        case (.sigh, .exhale): return [("Exhala largo y lento por la boca.", outC)]
        case (.box, .inhale): return [("Inhala contando 4.", inC)]
        case (.box, .holdIn): return [("Aguanta arriba.", inC)]
        case (.box, .exhale): return [("Exhala contando 4.", outC)]
        case (.box, .holdOut): return [("Aguanta vacío.", outC)]
        case (.sleep, .inhale): return [("Inhala por la nariz (4).", inC)]
        case (.sleep, .holdIn): return [("Aguanta (7).", inC)]
        case (.sleep, .exhale): return [("Exhala por la boca (8).", outC)]
        case (_, .inhale): return [("Inhala suave por la nariz.", inC)]
        case (_, .exhale): return [("Exhala despacio.", outC)]
        case (_, .holdIn): return [("Aguanta arriba.", inC)]
        case (_, .holdOut): return [("Aguanta vacío.", outC)]
        }
    }

    func insight(_ s: Breathwork.Summary) -> String {
        if kind == .alert {
            var t = "Al acelerar tu respiración activaste tu respuesta de «lucha o huida»: adrenalina, más pulso y más estrés. Tu cuerpo queda más alerta, con más energía y listo para rendir."
            if let best = s.retentions.max() { t += " Tu mejor retención: \(LiveView.duration(best))." }
            return t
        }
        if let c = s.stressChange, c <= -0.1 {
            var t = "Tu estrés bajó \(Fmt.dec(abs(c))) puntos"
            if let a = s.hrSeries.prefix(6).last, let b = s.hrSeries.suffix(6).first { t += " y tu pulso pasó de \(Int(a)) a \(Int(b)) lpm" }
            return t + ": tu sistema nervioso se ha calmado."
        }
        return "Esta vez tu estrés apenas bajó. Prueba a alargar la espiración o a hacer la sesión un par de minutos más larga."
    }
}

// MARK: - One breath, drawn

/// The session's breathing pattern as a smooth wave (up while you breathe in, flat while you hold, down while you
/// breathe out), three cycles, with the seconds of each phase underneath.
struct BreathPatternView: View {
    let kind: Breathwork.Kind
    let settings: Breathwork.Settings
    let color: Color

    /// One cycle: the steps from the first one until its phase comes back.
    private var cycle: [Breathwork.Step] {
        let steps = Breathwork.steps(kind, settings).filter { $0.seconds != nil && $0.phase != .retention }
        guard let first = steps.first else { return [] }
        var out: [Breathwork.Step] = [first]
        for s in steps.dropFirst() {
            if s.phase == first.phase { break }
            out.append(s)
        }
        return out
    }

    var body: some View {
        let c = cycle
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { g in
                let total = c.compactMap(\.seconds).reduce(0, +) * 3
                let pts = points(c, width: g.size.width, height: g.size.height, total: total)
                ZStack {
                    Path { p in
                        guard let f = pts.first else { return }
                        p.move(to: CGPoint(x: f.x, y: g.size.height))
                        for q in pts { p.addLine(to: q) }
                        p.addLine(to: CGPoint(x: pts.last?.x ?? 0, y: g.size.height))
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { p in
                        guard let f = pts.first else { return }
                        p.move(to: f)
                        for q in pts.dropFirst() { p.addLine(to: q) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    Rectangle().fill(DS.sep).frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 110)
            HStack(spacing: 16) {
                ForEach(Array(labels(c).enumerated()), id: \.offset) { _, l in
                    Text(l).dsFont(14, .semibold).foregroundStyle(DS.t1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(labels(c).joined(separator: ", "))
    }

    private func points(_ c: [Breathwork.Step], width: CGFloat, height: CGFloat, total: Double) -> [CGPoint] {
        guard total > 0 else { return [] }
        var out: [CGPoint] = []
        var t = 0.0
        var level = 0.0
        for _ in 0..<3 {
            for s in c {
                let d = s.seconds ?? 0
                let target: Double
                switch s.phase {
                case .inhale: target = 1
                case .topUp: target = 1
                case .exhale: target = 0
                default: target = level
                }
                let n = 24
                for i in 0...n {
                    let f = Double(i) / Double(n)
                    let e = (1 - cos(f * .pi)) / 2
                    let v = level + (target - level) * e
                    out.append(CGPoint(x: width * CGFloat((t + d * f) / total), y: 4 + (height - 8) * CGFloat(1 - v)))
                }
                t += d
                level = target
            }
        }
        return out
    }

    private func labels(_ c: [Breathwork.Step]) -> [String] {
        func sec(_ v: Double) -> String { v == v.rounded() ? "\(Int(v)) s" : "\(Fmt.dec(v)) s" }
        return c.compactMap { s in
            guard let d = s.seconds else { return nil }
            switch s.phase {
            case .inhale: return "Inhala \(sec(d))"
            case .topUp: return "Otra más \(sec(d))"
            case .exhale: return "Exhala \(sec(d))"
            case .holdIn, .holdOut: return "Aguanta \(sec(d))"
            case .retention: return nil
            }
        }
    }
}

// MARK: - Detail with settings (20, 21)

struct BreathworkDetailView: View {
    @EnvironmentObject var model: AppModel
    let kind: Breathwork.Kind
    /// Opens with this wheel showing (21 in the screenshot run).
    var initialField: Field?
    @State private var settings = Breathwork.Settings()
    @State private var editing: Field?
    @State private var loaded = false

    enum Field: String, Identifiable {
        case breaths, rounds, minutes, pace
        var id: String { rawValue }
    }

    var body: some View {
        let info = BreathworkInfo.of(kind)
        let last = model.breathworkRecords.last { $0.summary.kind == kind }
        DSScreen("", back: "Actividad") {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.goal).dsFont(15, .semibold).foregroundStyle(info.color)
                Text(info.title).dsFont(28, .bold, relativeTo: .title1).foregroundStyle(DS.t1)
                    .fixedSize(horizontal: false, vertical: true)
                BreathPatternView(kind: kind, settings: settings, color: info.color).padding(.top, 14)
                Text(info.about).dsFont(16).foregroundStyle(DS.t2).padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .dsCard(padding: 16)

            DSSectionHeader("Ajustes")
            DSGroup {
                if kind == .alert {
                    settingRow("Repeticiones de respiración", "\(settings.breaths)", .breaths)
                    settingRow("Rondas", "\(settings.rounds)", .rounds)
                } else {
                    settingRow("Duración", "\(settings.minutes) min", .minutes)
                    if kind == .coherence { settingRow("Ritmo", "\(Fmt.dec(settings.pace)) resp/min", .pace) }
                }
            }
            if let last {
                RouteLink(.actividad(.respiraResumen(start: last.summary.start))) { lastRow(last.summary, info) }
            }
            if kind == .sleep {
                DSGroup(footer: "En prueba: al acabar, el pulso en directo sigue hasta 45 min para estimar la hora a la que te duermes. No vibra ni avisa; gasta algo de batería de la pulsera.") {
                    DSToggleRow(label: "Apuntar cuándo me duermo",
                                isOn: Binding(get: { model.onsetAfterBreathing }, set: { model.onsetAfterBreathing = $0 }))
                }
            }
            DSSectionHeader("Por qué funciona")
            Text(info.benefits).dsFont(16).foregroundStyle(DS.t2)
                .fixedSize(horizontal: false, vertical: true)
                .dsCard(padding: 16)
            RouteLink(.actividad(.respiraPreparacion(kind))) {
                Label("Iniciar ejercicio", systemImage: "play.fill")
                    .dsFont(17, .semibold).foregroundStyle(info.color)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(info.color.opacity(DS.tintOpacity), in: Capsule())
            }
            .padding(.top, 12)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            settings = model.breathworkSettings(kind)
            if let f = initialField { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { editing = f } }
        }
        .sheet(item: $editing) { f in
            BreathworkWheel(field: f, settings: $settings) {
                model.saveBreathworkSettings(settings, for: kind)
                editing = nil
            }
            .dsSheet(detents: [.height(400)])
        }
    }

    private func settingRow(_ title: String, _ value: String, _ field: Field) -> some View {
        Button { editing = field } label: {
            DSRow(label: title, value: value, chevron: true)
        }
        .buttonStyle(.plain)
    }

    private func lastRow(_ s: Breathwork.Summary, _ info: BreathworkInfo) -> some View {
        let change: (String, Color)? = {
            if s.kind == .alert, let best = s.retentions.max() { return ("retención \(LiveView.duration(best))", DS.t2) }
            guard let c = s.stressChange else { return nil }
            return ("estrés \(c <= 0 ? "−" : "+")\(Fmt.dec(abs(c)))", c <= 0 ? DSLevel.buena.ink : DSLevel.justa.ink)
        }()
        return HStack(spacing: 12) {
            Image(systemName: info.icon).font(.system(size: 17)).foregroundStyle(info.color).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("Tu última sesión").dsFont(17, .semibold).foregroundStyle(DS.t1)
                Text("\(Fmt.dayTitle(DayKey.string(ts: s.start))) · \(Fmt.time(s.start))").dsFont(15).foregroundStyle(DS.t2)
            }
            Spacer(minLength: 6)
            if let change { Text(change.0).dsFont(16, .medium).foregroundStyle(change.1) }
            DSChevron()
        }
        .dsCard(padding: 14)
    }
}

/// One setting on a wheel: title, wheel, Guardar.
struct BreathworkWheel: View {
    let field: BreathworkDetailView.Field
    @Binding var settings: Breathwork.Settings
    let save: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(title).dsFont(17, .semibold, relativeTo: .headline).foregroundStyle(DS.t1).padding(.top, 26)
            Group {
                switch field {
                case .breaths:
                    Picker(title, selection: $settings.breaths) { ForEach(10...50, id: \.self) { Text("\($0)").tag($0) } }
                case .rounds:
                    Picker(title, selection: $settings.rounds) { ForEach(1...6, id: \.self) { Text("\($0)").tag($0) } }
                case .minutes:
                    Picker(title, selection: $settings.minutes) { ForEach(1...30, id: \.self) { Text("\($0) min").tag($0) } }
                case .pace:
                    Picker(title, selection: $settings.pace) {
                        ForEach([4.5, 5.0, 5.5, 6.0, 6.5, 7.0], id: \.self) { Text("\(Fmt.dec($0)) resp/min").tag($0) }
                    }
                }
            }
            .pickerStyle(.wheel)
            .padding(.horizontal, DS.gutter)
            Button("Guardar", action: save)
                .buttonStyle(DSButtonStyle(tint: DSLevel.buena.ink, size: .xl, fullWidth: true))
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DS.card.ignoresSafeArea())
    }

    private var title: String {
        switch field {
        case .breaths: return "Repeticiones de respiración"
        case .rounds: return "Rondas"
        case .minutes: return "Duración"
        case .pace: return "Ritmo"
        }
    }
}

// MARK: - Before starting (22)

/// The breathing circle at rest with the session's length, what to do, the band's state and the disclaimer.
struct BreathCircle: View {
    let color: Color
    var scale: Double = 0.62
    var label: String
    var labelSize: CGFloat = 54

    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            ZStack {
                Circle().stroke(DS.t3.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(width: d, height: d)
                Circle().fill(color.opacity(0.2))
                    .overlay(Circle().stroke(color, lineWidth: 3))
                    .frame(width: d * scale, height: d * scale)
                Circle().stroke(DS.t3.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(width: d * 0.42, height: d * 0.42)
                Text(label).dsFont(labelSize, .bold, relativeTo: .largeTitle, maxScale: 1.15).foregroundStyle(DS.t1)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: d * 0.55)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .accessibilityHidden(true)
    }
}

struct BreathworkPrepView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kind: Breathwork.Kind
    let settings: Breathwork.Settings
    @State private var running = false
    @State private var completed = false

    var body: some View {
        let info = BreathworkInfo.of(kind)
        let length = kind == .alert ? "\(settings.rounds) × \(settings.breaths)" : LiveView.duration(Double(max(1, settings.minutes) * 60))
        DSScreen(info.title) {
            BreathCircle(color: info.color, scale: 0.62, label: length, labelSize: 52)
                .frame(height: 290)
                .padding(.vertical, 6)
            Text(info.prep).dsFont(22, .semibold, relativeTo: .title2).foregroundStyle(DS.t1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            bandRow
            DSSectionHeader("Antes de empezar")
            Text(info.disclaimer).dsFont(16).foregroundStyle(DS.t2)
                .fixedSize(horizontal: false, vertical: true)
                .dsCard(padding: 16)
            Button { running = true } label: {
                Label("Iniciar sesión", systemImage: "play.fill")
                    .dsFont(17, .semibold).foregroundStyle(info.color)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(info.color.opacity(DS.tintOpacity), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .fullScreenCover(isPresented: $running, onDismiss: { if completed { dismiss() } }) {
            BreathworkSessionView(kind: kind, settings: settings, completed: $completed)
                .environmentObject(model)
        }
    }

    private var bandRow: some View {
        let live = model.liveToolBlocker == nil
        let connected = model.strapState.isConnected || live
        return HStack(spacing: 12) {
            Image(systemName: "applewatch").font(.system(size: 16, weight: .semibold)).foregroundStyle(connected ? DS.t2 : DSLevel.justa.ink)
            Text(connected ? "Pulsera conectada" : "Pulsera desconectada").dsFont(16, .semibold).foregroundStyle(DS.t1)
            Spacer()
            if live, let hr = model.liveHR {
                DSDot(color: DS.cor, size: 8)
                Text("\(hr) lpm").dsFont(16).foregroundStyle(DS.t2)
            } else if !connected {
                Text("sin pulso en directo").dsFont(14).foregroundStyle(DS.t3)
            }
        }
        .dsCard(padding: 14)
    }
}

// MARK: - The session (23, 24, 25)

/// The guided session: a breathing circle (orange in, blue out), the count, what to do, and the strap's vibration
/// on each change. Holds on empty lungs last until you tap.
struct BreathworkSessionView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kind: Breathwork.Kind
    let settings: Breathwork.Settings
    @Binding var completed: Bool

    @State private var steps: [Breathwork.Step] = []
    @State private var index = 0
    @State private var stepStart = Date()
    @State private var sessionStart = Date()
    @State private var done: [(phase: Breathwork.Phase, seconds: Double)] = []
    @State private var hrLog: [(t: Double, hr: Double)] = []
    @State private var beatLog: [LiveMetrics.Beat] = []
    @State private var saving = false
    @State private var saved: BreathworkRecord?
    @State private var confirmQuit = false
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        let info = BreathworkInfo.of(kind)
        ZStack {
            DS.bg.ignoresSafeArea()
            if let r = saved {
                NavigationStack {
                    BreathworkResultView(record: r) {
                        completed = true
                        dismiss()
                    }
                }
            } else if saving {
                VStack(spacing: 16) {
                    ProgressView().tint(DS.t1).scaleEffect(1.4)
                    Text("Guardando sesión…").dsFont(15).foregroundStyle(DS.t2)
                }
            } else {
                VStack(spacing: 0) {
                    header(info)
                    Spacer(minLength: 10)
                    TimelineView(.animation) { ctx in circle(at: ctx.date) }
                        .frame(height: 340)
                        .padding(.horizontal, 40)
                    Spacer(minLength: 10)
                    footer(info)
                }
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: start)
        .onDisappear { model.setLive(false, client: "breathwork") }
        .onReceive(ticker) { now in advanceIfDue(now) }
        .onReceive(model.$liveHR) { hr in
            guard let hr, saved == nil else { return }
            hrLog.append((Date().timeIntervalSince1970, Double(hr)))
            let last = beatLog.last?.t ?? 0
            beatLog += model.liveBeats.filter { $0.t > last }
        }
        .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmQuit) {
            Button("Guardar lo que llevas") { finish() }
            Button("Descartar", role: .destructive) { dismiss() }
        }
    }

    private var step: Breathwork.Step? { index < steps.count ? steps[index] : nil }

    private func header(_ info: BreathworkInfo) -> some View {
        ZStack {
            VStack(spacing: 1) {
                Text(info.title).dsFont(17, .semibold, relativeTo: .headline).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                if kind == .alert, let s = step {
                    Text("Serie \(s.round)/\(settings.rounds)").dsFont(13).foregroundStyle(DS.t2)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text("\(LiveView.duration(max(0, remaining(at: ctx.date)))) restante").dsFont(13).foregroundStyle(DS.t2)
                    }
                }
            }
            .padding(.horizontal, 56)
            HStack {
                Button {
                    if Date().timeIntervalSince(sessionStart) > 30 { confirmQuit = true } else { dismiss() }
                } label: { DSCircleButton(icon: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Terminar")
                Spacer()
            }
        }
        .frame(height: 52)
        .padding(.top, 4)
        .padding(.horizontal, DS.gutter)
    }

    private func circle(at date: Date) -> some View {
        let s = step
        let elapsed = date.timeIntervalSince(stepStart)
        let p = min(1, max(0, s?.seconds.map { elapsed / $0 } ?? 0))
        let rapid = kind == .alert && s?.count != nil
        let scale: Double = {
            guard let s else { return 0.5 }
            let lo = rapid ? 0.6 : 0.45, hi = rapid ? 0.85 : 1.0
            switch s.phase {
            case .inhale: return lo + (hi - lo) * p
            case .topUp: return 0.9 + 0.1 * p
            case .exhale: return hi - (hi - lo) * p
            case .holdIn: return hi
            case .holdOut, .retention: return lo
            }
        }()
        let warm = s.map { [.inhale, .topUp, .holdIn].contains($0.phase) } ?? false
        let tint = warm ? DS.act : DS.recarga
        let label: String = {
            guard let s else { return "" }
            if s.phase == .retention { return LiveView.duration(elapsed) }
            if let c = s.count { return "\(c)" }
            return "\(Int(ceil(max(0, (s.seconds ?? 0) - elapsed))))"
        }()
        return BreathCircle(color: tint, scale: scale * 0.8, label: label, labelSize: s?.phase == .retention ? 46 : 58)
            .animation(.linear(duration: 0.1), value: scale)
    }

    private func footer(_ info: BreathworkInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = step {
                let afterRetention = index > 0 && steps[index - 1].phase == .retention
                ForEach(Array(info.instructions(s, afterRetention: afterRetention).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 14) {
                        Circle().stroke(line.1, lineWidth: 2.5).frame(width: 14, height: 14).padding(.top, 7)
                        Text(line.0).dsFont(22, .medium, relativeTo: .title2).foregroundStyle(DS.t1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if s.phase == .retention {
                    let previous = done.filter { $0.phase == .retention }.map(\.seconds)
                    if !previous.isEmpty {
                        Text(previous.enumerated().map { "Serie \($0.offset + 1): \(LiveView.duration($0.element))" }.joined(separator: " · "))
                            .dsFont(14).foregroundStyle(DS.t3).padding(.leading, 28)
                    }
                    Button(s.round >= settings.rounds ? "Finalizar sesión" : "Iniciar el siguiente ciclo") { next(Date()) }
                        .buttonStyle(DSButtonStyle(tint: DSLevel.buena.ink, size: .xl, fullWidth: true))
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(DS.cor)
                Text(model.liveHR.map { "\($0) lpm" } ?? "Sin pulso en directo").dsFont(16).foregroundStyle(DS.t2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 190, alignment: .top)
        .padding(.horizontal, 24)
    }

    private func remaining(at date: Date) -> Double {
        guard index < steps.count else { return 0 }
        let rest = steps[(index + 1)...].compactMap(\.seconds).reduce(0, +)
        return rest + max(0, (steps[index].seconds ?? 0) - date.timeIntervalSince(stepStart))
    }

    private func start() {
        guard steps.isEmpty else { return }
        steps = Breathwork.steps(kind, settings)
        sessionStart = Date()
        stepStart = sessionStart
        beatLog = model.beats(since: sessionStart.addingTimeInterval(-60))
        model.setLive(true, client: "breathwork") // its own client: it keeps pacing with the screen locked
        cue(steps.first, previous: nil)
    }

    private func advanceIfDue(_ now: Date) {
        guard !saving, saved == nil, let s = step, let sec = s.seconds, now.timeIntervalSince(stepStart) >= sec else { return }
        next(now)
    }

    private func next(_ now: Date) {
        guard let s = step else { return }
        done.append((s.phase, now.timeIntervalSince(stepStart)))
        index += 1
        stepStart = now
        if index >= steps.count { finish() } else { cue(steps[index], previous: s) }
    }

    /// A tap on the wrist when the kind of phase changes (not on every rapid breath).
    private func cue(_ s: Breathwork.Step?, previous: Breathwork.Step?) {
        guard let s else { return }
        let rapid = kind == .alert && s.count != nil && previous?.count != nil
        guard !rapid else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        switch s.phase {
        case .inhale, .topUp: model.strap.buzz(loops: 1)
        case .exhale, .retention: model.strap.buzz(loops: 2)
        case .holdIn, .holdOut: break
        }
    }

    private func finish() {
        guard !saving else { return }
        if let s = step, index < steps.count { done.append((s.phase, Date().timeIntervalSince(stepStart))) }
        saving = true
        let summary = Breathwork.summarize(kind: kind, start: Int(sessionStart.timeIntervalSince1970), end: Int(Date().timeIntervalSince1970),
                                           done: done, hr: hrLog, beats: beatLog, baseline: model.liveBaseline)
        model.saveBreathwork(summary)
        model.breathingFinished(kind)
        // Ended with the phone locked, onDisappear won't come until morning: let the stream go now.
        model.setLive(false, client: "breathwork")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { saved = BreathworkRecord(summary: summary) }
    }
}

// MARK: - What the session did (26)

/// The session in the day's activities: time, stress change, what it did, the stress or pulse curve, the share of
/// each phase, the numbers against your last 30 days and how it moves your recovery.
struct BreathworkResultView: View {
    @EnvironmentObject var model: AppModel
    let record: BreathworkRecord
    var onDone: (() -> Void)?
    @State private var showHR = 0

    var body: some View {
        let s = record.summary
        let info = BreathworkInfo.of(s.kind)
        let history = model.breathworkHistory(s.kind, before: s.start)
        DSScreen(info.title, subtitle: "\(Fmt.dayTitle(DayKey.string(ts: s.start))) · \(Fmt.time(s.start))–\(Fmt.time(s.end))") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 0) {
                    big(LiveView.duration(Double(s.duration)), "Duración", color: DS.t1, arrow: nil)
                    if let c = s.stressChange {
                        big(Fmt.dec(abs(c)), "Cambio de estrés", color: c <= 0 ? DSLevel.buena.ink : DSLevel.justa.ink, arrow: c <= 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                    }
                }
                DSDivider()
                Text(info.insight(s)).dsFont(17).foregroundStyle(DS.t1).fixedSize(horizontal: false, vertical: true)
            }
            .dsCard(padding: 16)

            VStack(alignment: .leading, spacing: 12) {
                DSSegmented(options: [(0, "Estrés"), (1, "Frecuencia cardíaca")], selection: $showHR, height: 34)
                chart(s).frame(height: 170)
            }
            .dsCard(padding: 14)

            DSSectionHeader("Fases")
            phases(s)

            DSSectionHeader("Métricas", note: "vs. tus 30 días")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.stack), GridItem(.flexible())], spacing: DS.stack) {
                if s.kind == .alert, let best = s.retentions.max() {
                    metric("Retención máxima", LiveView.duration(best), "", history.compactMap { $0.retentions.max() }, format: { LiveView.duration($0) })
                }
                if s.hrMin != nil { metric("FC mínima", Fmt.int(s.hrMin), "lpm", history.compactMap(\.hrMin)) }
                if s.hrAvg != nil { metric("FC media", Fmt.int(s.hrAvg), "lpm", history.compactMap(\.hrAvg)) }
                if s.hrMax != nil { metric("FC máxima", Fmt.int(s.hrMax), "lpm", history.compactMap(\.hrMax)) }
                if let a = s.rmssdBefore, let b = s.rmssdAfter {
                    tile("VFC", "\(Int(a)) → \(Int(b))", "ms", "antes → después")
                }
            }
            impact
            if let onDone {
                Button("Hecho", action: onDone)
                    .buttonStyle(DSButtonStyle(tint: info.color, size: .xl, fullWidth: true))
                    .padding(.top, 8)
            }
        }
    }

    private func big(_ v: String, _ k: String, color: Color, arrow: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let arrow { Image(systemName: arrow).font(.system(size: 18)).foregroundStyle(color) }
                Text(v).dsFont(48, .semibold, relativeTo: .largeTitle, maxScale: 1.15).foregroundStyle(color)
            }
            Text(k).dsFont(15).foregroundStyle(DS.t2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chart(_ s: Breathwork.Summary) -> some View {
        let hr = showHR == 1
        let values = hr ? s.hrSeries : s.stressSeries
        let step = hr ? 5.0 : 15.0
        let offset = hr ? 0.0 : 45.0
        let color = hr ? DS.cor : DS.bien
        return VStack(spacing: 6) {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("s", offset + Double(i) * step), y: .value("v", v))
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("s", offset + Double(i) * step), y: .value("v", v))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = values.last {
                    PointMark(x: .value("s", offset + Double(values.count - 1) * step), y: .value("v", last))
                        .foregroundStyle(color).symbolSize(40)
                }
            }
            .chartYScale(domain: hr ? .automatic(includesZero: false) : .automatic(includesZero: true))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(DS.sep)
                    AxisValueLabel().foregroundStyle(DS.t3)
                }
            }
            .overlay {
                if values.isEmpty {
                    Text("Sin pulso en directo durante la sesión").dsFont(14).foregroundStyle(DS.t3)
                }
            }
            HStack {
                Text(Fmt.time(s.start)).foregroundStyle(DS.t3)
                Spacer()
                Text(Fmt.time(s.end)).fontWeight(.semibold).foregroundStyle(DS.t1)
            }
            .dsFont(13, relativeTo: .footnote)
            .padding(.trailing, 28)
        }
    }

    private func phases(_ s: Breathwork.Summary) -> some View {
        let parts: [(String, Double, Color)] = [("Inhala", s.inhaleSeconds, DS.act), ("Exhala", s.exhaleSeconds, DS.recarga),
                                                ("Retención", s.holdSeconds, DS.t2)].filter { $0.1 > 0 }
        let total = max(1, parts.reduce(0) { $0 + $1.1 })
        return VStack(spacing: 0) {
            GeometryReader { g in
                let gap: CGFloat = 3
                let usable = g.size.width - gap * CGFloat(max(0, parts.count - 1))
                HStack(spacing: gap) {
                    ForEach(parts.indices, id: \.self) { i in
                        Capsule().fill(parts[i].2).frame(width: max(4, usable * CGFloat(parts[i].1 / total)))
                    }
                }
            }
            .frame(height: 12)
            .padding(.bottom, 8)
            ForEach(parts.indices, id: \.self) { i in
                if i > 0 { DSDivider() }
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(parts[i].2).frame(width: 9, height: 9)
                    Text(parts[i].0).dsFont(17).foregroundStyle(DS.t1)
                    Spacer()
                    Text("\(Int((parts[i].1 / total * 100).rounded())) %").dsFont(17, .semibold).foregroundStyle(DS.t1)
                    Text(LiveView.duration(parts[i].1)).dsFont(17).foregroundStyle(DS.t2).frame(width: 64, alignment: .trailing)
                }
                .frame(minHeight: 46)
            }
        }
        .dsCard(padding: 14)
    }

    private func metric(_ title: String, _ value: String, _ unit: String, _ past: [Double], format: (Double) -> String = { Fmt.int($0) }) -> some View {
        tile(title, value, unit, past.count >= 2 ? "rango \(format(past.min()!))–\(format(past.max()!))" : "primeras sesiones")
    }

    private func tile(_ title: String, _ value: String, _ unit: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).dsFont(14).foregroundStyle(DS.t2).lineLimit(1)
            HoyValue(value: value, unit: unit, size: 26)
            Text(note).dsFont(14).foregroundStyle(DS.t3).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(padding: 14)
    }

    /// Days with a session so far towards the 5 that unlock its impact on your recovery.
    private var impact: some View {
        let days = Set(model.breathworkRecords.map { DayKey.string(ts: $0.summary.start) }).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Impacto en la recuperación").dsFont(17, .semibold).foregroundStyle(DS.t1)
                Spacer()
                Text("\(min(days, Behaviors.minEach))/\(Behaviors.minEach)").dsFont(17, .semibold).foregroundStyle(DS.t1)
            }
            HStack(spacing: 10) {
                ForEach(0..<Behaviors.minEach, id: \.self) { i in
                    Circle().fill(i < days ? DSLevel.buena.mark : DS.fill).frame(width: 26, height: 26)
                        .overlay { if i < days { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.bg) } }
                }
            }
            Text(days >= Behaviors.minEach
                 ? "Ya tienes días suficientes con sesión: mira cuánto mueve tu recuperación al día siguiente."
                 : "Con \(Behaviors.minEach) días con sesión y \(Behaviors.minEach) sin, Pulso te dice cuánto mueve tu recuperación.")
                .dsFont(15).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
            DSDivider()
            NavigationLink { BehaviorsView() } label: {
                HStack(spacing: 6) {
                    Text("Ver más impactos").dsFont(17, .semibold).foregroundStyle(DS.t1)
                    DSChevron()
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .dsCard(padding: 16)
    }
}
