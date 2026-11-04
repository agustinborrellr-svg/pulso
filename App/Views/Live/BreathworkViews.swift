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
                icon: "gauge.with.dots.needle.67percent", color: Theme.stressHigh,
                about: "Series de respiraciones rápidas y profundas, una retención con los pulmones vacíos y una inspiración final que aguantas arriba. Activa tu sistema nervioso simpático: sube el pulso, libera adrenalina y te deja despierto y con energía.",
                benefitsTitle: "Beneficios de la hiperventilación cíclica",
                benefits: "Una dosis corta y controlada de estrés entrena tu tolerancia a otras formas de estrés (hormesis). Va bien antes de entrenar, de estudiar o cuando te falta energía. Pulso cronometra cada retención y te enseña cómo baja tu pulso mientras aguantas.",
                prep: "Siéntate o recuéstate por si te mareas.",
                disclaimer: "No lo hagas en el agua ni conduciendo. Evítalo si estás embarazada, tienes la tensión alta, te recuperas de una operación o tienes antecedentes de problemas graves como insuficiencia cardíaca, epilepsia o ictus.")
        case .sigh:
            return BreathworkInfo(
                kind: kind, title: Breathwork.activityName(kind), goal: "Cálmate",
                short: "Doble inspiración y espiración larga: la forma más rápida de bajar pulsaciones.",
                icon: "wind", color: Theme.link,
                about: "Dos inspiraciones por la nariz, una larga y otra corta para llenar del todo, y una espiración lenta y larga por la boca. Vacía el aire viejo de los pulmones y frena el corazón en cada espiración.",
                benefitsTitle: "Por qué funciona",
                benefits: "En un estudio de Stanford (Balban y cols., Cell Reports Medicine 2023), 5 minutos al día de suspiro cíclico mejoraron el ánimo y bajaron la respiración en reposo más que la meditación. Pulso te enseña cuánto bajan tu pulso y tu estrés.",
                prep: calmPrep, disclaimer: calmDisclaimer)
        case .coherence:
            return BreathworkInfo(
                kind: kind, title: Breathwork.activityName(kind), goal: "Cálmate",
                short: "Unas 6 respiraciones por minuto: tu pulso y tu respiración se sincronizan.",
                icon: "waveform.path.ecg", color: Theme.hrv,
                about: "Respiras despacio a un ritmo fijo, unas 6 veces por minuto. A ese ritmo el pulso sube al inspirar y baja al espirar con la máxima amplitud (frecuencia de resonancia) y tu VFC se dispara.",
                benefitsTitle: "Por qué funciona",
                benefits: "La respiración a frecuencia de resonancia (Lehrer) se usa en biofeedback para la ansiedad, la tensión arterial y la recuperación. Pulso compara tu VFC y tu estrés antes y después.",
                prep: calmPrep, disclaimer: calmDisclaimer)
        case .box:
            return BreathworkInfo(
                kind: kind, title: Breathwork.activityName(kind), goal: "Cálmate",
                short: "4-4-4-4: la cabeza fría antes de algo importante.",
                icon: "square", color: Theme.sleep,
                about: "Cuatro tiempos iguales: inhalar, aguantar, exhalar y aguantar. Un ritmo lento y predecible que calma sin adormecer.",
                benefitsTitle: "Cuándo usarla",
                benefits: "Para mantener la calma bajo presión: un examen, una competición, hablar en público. Pulso mide cuánto baja tu estrés.",
                prep: calmPrep, disclaimer: calmDisclaimer)
        case .sleep:
            return BreathworkInfo(
                kind: kind, title: Breathwork.activityName(kind), goal: "Duerme",
                short: "4-7-8 en la cama: suelta el día y baja pulsaciones.",
                icon: "moon.stars", color: Theme.sleep,
                about: "Inhala 4 segundos, aguanta 7 y exhala 8. La espiración larga activa el sistema parasimpático y ayuda a soltar el día.",
                benefitsTitle: "Cómo sacarle partido",
                benefits: "Hazlo ya en la cama con la luz apagada: la pulsera marca cada fase con una vibración para que no tengas que mirar la pantalla. Con el tiempo, el impacto en tu recuperación te dirá si duermes mejor los días que la haces.",
                prep: "Túmbate en la cama con la luz apagada. Cierra los ojos y sigue la vibración de la pulsera.",
                disclaimer: calmDisclaimer)
        }
    }

    /// What to do in each phase, with the colour of its bullet.
    func instructions(_ step: Breathwork.Step, afterRetention: Bool) -> [(String, Color)] {
        let inC = Theme.stressHigh, outC = Theme.link
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

// MARK: - Live hub card

/// A session on the Live page: colour, icon, what it does and how the last one went.
struct BreathworkCard: View {
    @EnvironmentObject var model: AppModel
    let kind: Breathwork.Kind

    var body: some View {
        let info = BreathworkInfo.of(kind)
        let last = model.breathworkRecords.last { $0.summary.kind == kind }?.summary
        NavigationLink { BreathworkDetailView(kind: kind) } label: {
            HStack(spacing: 14) {
                Image(systemName: info.icon).font(.title2).foregroundStyle(info.color)
                    .frame(width: 52, height: 52)
                    .background(info.color.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Caps(info.title, size: 12)
                    Text(info.short).font(.caption).foregroundStyle(Theme.secondary).multilineTextAlignment(.leading)
                    if let last {
                        Text(lastLine(last)).font(.caption2.weight(.semibold)).foregroundStyle(info.color)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.tertiary)
            }
            .padding(14)
            .background(
                LinearGradient(colors: [info.color.opacity(0.14), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func lastLine(_ s: Breathwork.Summary) -> String {
        if s.kind == .alert, let best = s.retentions.max() { return "Última: retención máx. \(LiveView.duration(best))" }
        if let c = s.stressChange { return "Última: estrés \(c <= 0 ? "▼" : "▲") \(Fmt.dec(abs(c)))" }
        return "Última: \(Fmt.hmm(Double(s.duration) / 60)) min"
    }
}

// MARK: - Detail with settings

struct BreathworkDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kind: Breathwork.Kind
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Caps(info.goal, size: 11, color: info.color)
                Text(info.title.uppercased()).scaledFont(26, weight: .heavy, relativeTo: .title1).tracking(1).foregroundStyle(.white)
                Text(info.about).font(.body).foregroundStyle(.white.opacity(0.85))
                VStack(spacing: 8) {
                    if kind == .alert {
                        row("Repeticiones de respiración", "lungs", "\(settings.breaths)", .breaths)
                        row("Rondas", "arrow.triangle.2.circlepath", "\(settings.rounds)", .rounds)
                    } else {
                        row("Duración", "timer", "\(settings.minutes) min", .minutes)
                        if kind == .coherence { row("Ritmo", "metronome", "\(Fmt.dec(settings.pace)) resp/min", .pace) }
                    }
                }
                if let last {
                    NavigationLink { BreathworkResultView(record: last) } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(info.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Caps("Tu última sesión", size: 10, color: Theme.secondary, weight: .semibold)
                                Text(info.insight(last.summary)).font(.caption).foregroundStyle(.white).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.tertiary)
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Text(info.benefitsTitle).font(.headline).foregroundStyle(.white).padding(.top, 6)
                Text(info.benefits).font(.body).foregroundStyle(Theme.secondary)
                NavigationLink { BreathworkPrepView(kind: kind, settings: settings) } label: {
                    Caps("Iniciar ejercicio", size: 13, color: Theme.link)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .overlay(Capsule().stroke(Theme.link, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(PulsoBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Caps("Detalles de la sesión", size: 12) } }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            settings = model.breathworkSettings(kind)
        }
        .sheet(item: $editing) { f in
            BreathworkWheel(field: f, settings: $settings) {
                model.saveBreathworkSettings(settings, for: kind)
                editing = nil
            }
            .presentationDetents([.height(320)])
            .preferredColorScheme(.dark)
        }
    }

    private func row(_ title: String, _ icon: String, _ value: String, _ field: Field) -> some View {
        Button { editing = field } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Theme.secondary).frame(width: 22)
                Caps(title, size: 11)
                Spacer()
                Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white)
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// One setting on a wheel, like the reference: title, wheel, Guardar.
struct BreathworkWheel: View {
    let field: BreathworkDetailView.Field
    @Binding var settings: Breathwork.Settings
    let save: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Caps(title, size: 12).padding(.top, 18)
            switch field {
            case .breaths:
                Picker(title, selection: $settings.breaths) { ForEach(10...50, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.wheel)
            case .rounds:
                Picker(title, selection: $settings.rounds) { ForEach(1...6, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.wheel)
            case .minutes:
                Picker(title, selection: $settings.minutes) { ForEach(1...30, id: \.self) { Text("\($0) min").tag($0) } }.pickerStyle(.wheel)
            case .pace:
                Picker(title, selection: $settings.pace) {
                    ForEach([4.5, 5.0, 5.5, 6.0, 6.5, 7.0], id: \.self) { Text("\(Fmt.dec($0)) resp/min").tag($0) }
                }
                .pickerStyle(.wheel)
            }
            Button(action: save) {
                Caps("Guardar", size: 13, color: Theme.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(Capsule().stroke(Theme.green, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(PulsoBackground())
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

// MARK: - Before starting

struct BreathworkPrepView: View {
    @Environment(\.dismiss) private var dismiss
    let kind: Breathwork.Kind
    let settings: Breathwork.Settings
    @State private var running = false
    @State private var completed = false

    var body: some View {
        let info = BreathworkInfo.of(kind)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: kind == .sleep ? "bed.double" : "figure.mind.and.body")
                    .font(.system(size: 150, weight: .ultraLight))
                    .foregroundStyle(LinearGradient(colors: [Theme.green, info.color], startPoint: .top, endPoint: .bottom))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                Text(info.prep).font(.title3.weight(.medium)).foregroundStyle(.white)
                Caps("Descargo de responsabilidad", size: 11, weight: .semibold).padding(.top, 8)
                Text(info.disclaimer).font(.subheadline).foregroundStyle(Theme.secondary)
                Button { running = true } label: {
                    Caps("Iniciar sesión", size: 13, color: Theme.link)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .overlay(Capsule().stroke(Theme.link, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
            .padding(20)
        }
        .background(PulsoBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Caps(info.title, size: 12) } }
        .fullScreenCover(isPresented: $running, onDismiss: { if completed { dismiss() } }) {
            BreathworkSessionView(kind: kind, settings: settings, completed: $completed)
        }
    }
}

// MARK: - The session

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
            PulsoBackground().ignoresSafeArea()
            if let r = saved {
                NavigationStack {
                    BreathworkResultView(record: r) {
                        completed = true
                        dismiss()
                    }
                }
            } else if saving {
                VStack(spacing: 16) {
                    ProgressView().tint(.white).scaleEffect(1.4)
                    Caps("Guardando sesión…", size: 12)
                }
            } else {
                VStack(spacing: 0) {
                    header(info)
                    Spacer()
                    TimelineView(.animation) { ctx in circle(at: ctx.date) }
                        .frame(height: 340)
                    Spacer()
                    footer(info)
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: start)
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
        HStack {
            Button {
                if Date().timeIntervalSince(sessionStart) > 30 { confirmQuit = true } else { dismiss() }
            } label: { Image(systemName: "xmark").font(.title2.weight(.semibold)).foregroundStyle(.white) }
            Spacer()
            VStack(spacing: 3) {
                Caps(info.title, size: 12)
                if kind == .alert, let s = step {
                    Caps("Serie \(s.round)/\(settings.rounds)", size: 10, color: Theme.secondary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Caps(LiveView.duration(max(0, remaining(at: ctx.date))), size: 10, color: Theme.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "xmark").font(.title2).opacity(0)
        }
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
        let tint = warm ? Theme.stressHigh : Theme.link
        let label: String = {
            guard let s else { return "" }
            if s.phase == .retention { return LiveView.duration(elapsed) }
            if let c = s.count { return "\(c)" }
            return "\(Int(ceil(max(0, (s.seconds ?? 0) - elapsed))))"
        }()
        return ZStack {
            Circle().stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            Circle()
                .fill(RadialGradient(colors: [Color.black.opacity(0.6), tint.opacity(0.35)], center: .center, startRadius: 10, endRadius: 170))
                .overlay(Circle().stroke(AngularGradient(colors: [tint, tint.opacity(0.6), tint], center: .center), lineWidth: 3))
                .shadow(color: tint.opacity(0.5), radius: 20)
                .scaleEffect(scale)
            Circle().stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 4])).scaleEffect(0.42)
            Text(label).scaledFont(s?.phase == .retention ? 34 : 54, weight: .bold, relativeTo: .largeTitle).monospacedDigit().foregroundStyle(.white)
        }
        .animation(.linear(duration: 0.1), value: scale)
    }

    private func footer(_ info: BreathworkInfo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let s = step {
                let afterRetention = index > 0 && steps[index - 1].phase == .retention
                ForEach(Array(info.instructions(s, afterRetention: afterRetention).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().stroke(line.1, lineWidth: 2).frame(width: 12, height: 12).padding(.top, 6)
                        Text(line.0).font(.title3.weight(.medium)).foregroundStyle(.white)
                    }
                }
                if s.phase == .retention {
                    Button { next(Date()) } label: {
                        Caps(s.round >= settings.rounds ? "Finalizar sesión" : "Iniciar el siguiente ciclo", size: 12, color: Theme.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(Capsule().stroke(Theme.green, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.red)
                Text(model.liveHR.map { "\($0) lpm" } ?? "Sin pulso en directo").font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 170, alignment: .top)
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
        model.setLive(true)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { saved = BreathworkRecord(summary: summary) }
    }
}

// MARK: - What the session did

/// The session in the day's activities: time, stress change, what it did, the stress or pulse curve, the share of
/// each phase, the numbers against your last 30 days and how it moves your recovery.
struct BreathworkResultView: View {
    @EnvironmentObject var model: AppModel
    let record: BreathworkRecord
    var onDone: (() -> Void)?
    @State private var showHR = false

    var body: some View {
        let s = record.summary
        let info = BreathworkInfo.of(s.kind)
        let history = model.breathworkHistory(s.kind, before: s.start)
        DetailScreen(title: info.title, subtitle: "\(Fmt.dayTitle(DayKey.string(ts: s.start))) de las \(Fmt.time(s.start)) a las \(Fmt.time(s.end))") {
            HStack(alignment: .top, spacing: 28) {
                big(LiveView.duration(Double(s.duration)), "Minutos")
                if let c = s.stressChange {
                    big("\(c <= 0 ? "▼" : "▲") \(Fmt.dec(abs(c)))", "Cambio de estrés")
                }
            }
            Text(info.insight(s))
                .font(.body).foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LinearGradient(colors: [Theme.hrv, Theme.link], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
            HStack(spacing: 0) {
                segment("Estrés", selected: !showHR) { showHR = false }
                segment("Frecuencia cardíaca", selected: showHR) { showHR = true }
            }
            .padding(4)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            chart(s).frame(height: 190)
            phaseBar("Inhala", s.inhaleSeconds, s, Theme.stressHigh)
            phaseBar("Exhala", s.exhaleSeconds, s, Theme.link)
            phaseBar("Retención de la respiración", s.holdSeconds, s, .white)
            HStack {
                Caps("Métricas de la sesión", size: 11)
                Spacer()
                Caps("vs. tus 30 días", size: 9.5, color: Theme.secondary, weight: .semibold)
            }
            .padding(.top, 6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                if s.kind == .alert, let best = s.retentions.max() {
                    metric("Retención máxima", LiveView.duration(best), "", history.compactMap { $0.retentions.max() }, format: { LiveView.duration($0) })
                }
                metric("FC mínima", Fmt.int(s.hrMin), "lpm", history.compactMap(\.hrMin))
                metric("FC media", Fmt.int(s.hrAvg), "lpm", history.compactMap(\.hrAvg))
                metric("FC máxima", Fmt.int(s.hrMax), "lpm", history.compactMap(\.hrMax))
                if let a = s.rmssdBefore, let b = s.rmssdAfter {
                    metric("VFC antes → después", "\(Int(a)) → \(Int(b))", "ms", [])
                }
            }
            impact
            if let onDone {
                Button(action: onDone) { Text("Hecho").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryCapsuleStyle())
                    .padding(.top, 6)
            }
        }
    }

    private func big(_ v: String, _ k: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).scaledFont(40, weight: .bold, relativeTo: .largeTitle).monospacedDigit().foregroundStyle(.white)
            Caps(k, size: 10.5, color: Theme.secondary, weight: .semibold)
        }
    }

    private func segment(_ t: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Caps(t, size: 11, color: selected ? .white : Theme.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? Theme.cardHighlight : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chart(_ s: Breathwork.Summary) -> some View {
        let values = showHR ? s.hrSeries : s.stressSeries
        let step = showHR ? 5.0 : 15.0
        let offset = showHR ? 0.0 : 45.0
        return Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("s", offset + Double(i) * step), y: .value("v", v))
                    .foregroundStyle(LinearGradient(colors: [Theme.link.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("s", offset + Double(i) * step), y: .value("v", v))
                    .foregroundStyle(showHR ? Theme.link : Theme.hrv)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: showHR ? .automatic(includesZero: false) : .automatic(includesZero: true))
        .chartXAxis {
            AxisMarks(values: [0.0, Double(s.duration)]) { v in
                AxisValueLabel { Text(Fmt.time(s.start + Int(v.as(Double.self) ?? 0))).font(.caption2).foregroundStyle(Theme.secondary) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel().foregroundStyle(Theme.secondary)
            }
        }
        .overlay {
            if values.isEmpty {
                Text("Sin pulso en directo durante la sesión").font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func phaseBar(_ title: String, _ seconds: Double, _ s: Breathwork.Summary, _ color: Color) -> some View {
        let total = max(1, s.inhaleSeconds + s.exhaleSeconds + s.holdSeconds)
        let share = seconds / total
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Caps(title, size: 11)
                Text("\(Int((share * 100).rounded())) %").font(.subheadline.weight(.bold)).foregroundStyle(color)
                Spacer()
                Text(LiveView.duration(seconds)).font(.headline.monospacedDigit()).foregroundStyle(.white)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: max(8, g.size.width * share))
                }
            }
            .frame(height: 14)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metric(_ title: String, _ value: String, _ unit: String, _ past: [Double], format: (Double) -> String = { Fmt.int($0) }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Caps(title, size: 9.5, color: Theme.secondary, weight: .semibold).lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).scaledFont(24, weight: .bold, relativeTo: .title2).monospacedDigit().foregroundStyle(.white)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Theme.secondary) }
            }
            Text(past.count >= 2 ? "rango \(format(past.min()!))–\(format(past.max()!))" : "primeras sesiones")
                .font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Days with a session so far towards the 5 that unlock its impact on your recovery.
    private var impact: some View {
        let days = Set(model.breathworkRecords.map { DayKey.string(ts: $0.summary.start) }).count
        return PCard {
            HStack {
                Caps("Impacto en la recuperación", size: 11)
                Spacer()
                Text("\(min(days, Behaviors.minEach))/\(Behaviors.minEach)").font(.subheadline.monospacedDigit().bold()).foregroundStyle(.white)
            }
            Text(days >= Behaviors.minEach
                 ? "Ya tienes días suficientes con sesión: mira cuánto mueve tu recuperación al día siguiente."
                 : "Sigue haciendo sesiones: con \(Behaviors.minEach) días con y \(Behaviors.minEach) sin, Pulso te dice cuánto mueven tu recuperación.")
                .font(.caption).foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                ForEach(0..<Behaviors.minEach, id: \.self) { i in
                    Circle().fill(i < days ? Theme.green : Color.white.opacity(0.1)).frame(width: 22, height: 22)
                        .overlay { if i < days { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.black) } }
                }
            }
            NavigationLink { BehaviorsView() } label: {
                Caps("Ver más impactos", size: 10.5, color: Theme.link)
            }
        }
    }
}
