import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

// MARK: - Pieces

/// A heart that beats at your live heart rate.
struct BeatingHeart: View {
    let bpm: Int?
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: bpm == nil)) { ctx in
            let period = 60 / Double(max(30, bpm ?? 60))
            let phase = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            // Two bumps per beat (lub-dub), decaying.
            let lub = exp(-phase * 14), dub = phase > 0.18 ? exp(-(phase - 0.18) * 16) * 0.55 : 0
            let scale = bpm == nil ? 1 : 1 + 0.16 * (lub + dub)
            Image(systemName: "heart.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(color)
                .scaleEffect(scale)
                .shadow(color: color.opacity(bpm == nil ? 0 : 0.6), radius: 8 * scale)
        }
    }
}

/// Heart rate over the zone bands (target band highlighted).
struct ZoneBandsChart: View {
    let model: HeartRateModel
    let points: [LivePoint]
    let target: Int?

    var body: some View {
        let lo = model.zoneFloor(1) - 15
        let t1 = max(points.last?.date ?? Date(), Date())
        let t0 = min(points.first?.date ?? t1.addingTimeInterval(-60), t1.addingTimeInterval(-60))
        Chart {
            ForEach(1...5, id: \.self) { z in
                RectangleMark(xStart: .value("t0", t0), xEnd: .value("t1", t1),
                              yStart: .value("de", model.zoneFloor(z)), yEnd: .value("a", z >= 5 ? model.maxHR : model.zoneFloor(z + 1)))
                    .foregroundStyle(Theme.zoneColor(z).opacity(target == z ? 0.32 : 0.10))
            }
            ForEach(points) { p in
                LineMark(x: .value("t", p.date), y: .value("FC", p.hr))
                    .foregroundStyle(.white)
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartYScale(domain: lo...model.maxHR)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: (1...5).map { model.zoneFloor($0) }) { v in
                AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))").scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.tertiary) }
            }
        }
    }
}

/// Big round score.
struct LiveRing: View {
    let value: Double
    let text: String
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 14)
            Circle().trim(from: 0, to: max(0.01, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(text).scaledFont(44, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3).monospacedDigit().foregroundStyle(.white)
        }
    }
}

private func row(_ k: String, _ v: String, _ note: String? = nil) -> some View {
    HStack {
        Text(k).foregroundStyle(Theme.secondary)
        Spacer()
        if let note { Text(note).font(.caption).foregroundStyle(Theme.tertiary) }
        Text(v).font(.headline.monospacedDigit()).foregroundStyle(.white)
    }
    .font(.subheadline)
}

private func signed(_ v: Double?, _ unit: String) -> String? {
    guard let v else { return nil }
    return (v >= 0 ? "+" : "−") + "\(Int(abs(v).rounded())) \(unit) vs tu normal"
}

/// Countdown of the running phase (from the model, so it is right after navigating away and back).
private struct RunClock: View {
    let run: LiveRun
    let title: String
    let hint: String

    var body: some View {
        TimelineView(.periodic(from: run.phaseStart, by: 0.5)) { ctx in
            VStack(spacing: 14) {
                if let total = run.phaseSeconds, let left = run.remaining(at: ctx.date) {
                    LiveRing(value: 1 - left / max(total, 1), text: LiveView.duration(left.rounded(.up)), color: Theme.link)
                        .frame(width: 190, height: 190)
                } else {
                    Text(LiveView.duration(ctx.date.timeIntervalSince(run.phaseStart)))
                        .font(.title3.monospacedDigit()).foregroundStyle(Theme.secondary)
                }
                Text(title).font(.title3.bold()).foregroundStyle(.white)
                Text(hint).font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            }
        }
    }
}

/// R-R beats received in the running phase, and a warning when pulse arrives without them.
private struct PhaseBeatsNote: View {
    let run: LiveRun

    var body: some View {
        if run.phaseLacksRR {
            Label("Llega pulso pero sin intervalos R-R en esta fase: no servirá para el cálculo. Ajusta la pulsera.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(Theme.yellow)
        } else {
            Text("Latidos con R-R en esta fase: \(run.beatsInPhase())").font(.caption).foregroundStyle(Theme.tertiary)
        }
    }
}

/// Numbered steps of a guided test; done steps are ticked, the current one highlighted.
private struct PhaseSteps: View {
    let steps: [String]
    let current: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 8) {
                    Image(systemName: i < current ? "checkmark.circle.fill" : i == current ? "circle.inset.filled" : "circle")
                        .foregroundStyle(i < current ? Theme.green : i == current ? Theme.link : Theme.tertiary)
                    Text(s).font(.subheadline.weight(i == current ? .semibold : .regular))
                        .foregroundStyle(i == current ? .white : i < current ? Theme.secondary : Theme.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension View {
    func liveScreen(_ title: String, client: String, model: AppModel) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(PulsoBackground())
            .pulsoTitle(title)
            .onAppear { model.setLive(true, client: client) }
            .onDisappear { model.setLive(false, client: client) }
    }
}

private func history(_ records: [LiveTestRecord], format: @escaping (LiveTestRecord) -> String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        if !records.isEmpty {
            SectionHeading(text: "Historial")
            ForEach(records.suffix(12).reversed()) { r in
                HStack {
                    Text(r.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.caption).foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(format(r)).font(.subheadline.monospacedDigit()).foregroundStyle(.white)
                }
                .padding(.vertical, 4)
                .overlay(alignment: .bottom) { Divider().overlay(Theme.hairline) }
            }
        }
    }
}

/// Start button for a test, disabled (with the reason) without fresh beats or while another test runs.
private struct StartTestButton: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let action: () -> Void

    var body: some View {
        let other = model.liveLab.run
        Button(title, action: action)
            .buttonStyle(PrimaryCapsuleStyle())
            .disabled(model.liveToolBlocker != nil || other != nil)
        if let other {
            Label("Hay otro test en curso: \(other.kind.title). Termínalo o cancélalo primero.", systemImage: "hourglass")
                .font(.caption).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LiveBlockerNote()
        }
    }
}

private func failure(_ outcome: LiveOutcome?) -> some View {
    Group {
        if case .failed(let why)? = outcome {
            Label(why, systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(Theme.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func cancelButton(_ model: AppModel) -> some View {
    Button("Cancelar test") { model.cancelLiveTest() }
        .buttonStyle(SecondaryCapsuleStyle())
}

/// Live heart rate while a test runs: the heart only beats with fresh data.
private struct LiveHRReadout: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let fresh = model.liveToolBlocker == nil
            VStack(spacing: 6) {
                BeatingHeart(bpm: fresh ? model.liveHR : nil, color: fresh ? Theme.red : Theme.secondary).frame(width: 64, height: 64)
                Text("\(fresh ? model.liveHR.map(String.init) ?? "--" : "--") lpm")
                    .scaledFont(52, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3).monospacedDigit()
                    .foregroundStyle(fresh ? .white : Theme.secondary)
                if !fresh, let at = model.lastLiveAt {
                    Text("Sin señal desde las \(Fmt.clock(at))").font(.caption).foregroundStyle(Theme.yellow)
                }
            }
        }
    }
}

// MARK: - Running test banner

/// "Test en curso" strip at the top of En vivo; tapping it goes back to the test.
struct LiveRunBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let r = model.liveLab.run {
            NavigationLink {
                Self.destination(r.kind)
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: 10) {
                        Image(systemName: "record.circle").foregroundStyle(Theme.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Test en curso: \(r.kind.title)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text(r.remaining(at: ctx.date).map { "\(r.phase.title) · quedan \(LiveView.duration($0.rounded(.up)))" }
                                 ?? "\(r.phase.title) · \(LiveView.duration(ctx.date.timeIntervalSince(r.phaseStart)))")
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                    }
                    .padding(12)
                    .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder static func destination(_ kind: LiveRun.Kind) -> some View {
        switch kind {
        case .scan: ScanView()
        case .orthostatic: OrthostaticTestView()
        case .recovery: RecoveryTestView()
        case .maxHR: MaxHRTestView()
        case .breathing: BreathingView()
        }
    }
}

// MARK: - Scan

struct ScanView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let run = model.liveLab.running(.scan)
        let outcome = model.liveLab.outcomes[.scan]
        ScrollView {
            VStack(spacing: 18) {
                if let run {
                    RunClock(run: run, title: run.extended ? "Faltan latidos: alargando hasta 90 s" : "Escaneando…",
                             hint: "Quédate sentado, quieto y respirando normal. No hables.")
                        .padding(.top, 12)
                    PhaseBeatsNote(run: run)
                    cancelButton(model)
                } else {
                    if case .scan(let r)? = outcome {
                        resultCard(r)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "dot.radiowaves.left.and.right").scaledFont(54, relativeTo: .largeTitle, maxScale: 1.3).foregroundStyle(Theme.link)
                            Text("Siéntate, apoya el brazo y respira normal durante un minuto. Pulso compara tu pulso, tu VFC y tu respiración con tu normal en calma.")
                                .font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                    }
                    failure(outcome)
                    StartTestButton(title: outcome == nil ? "Empezar escaneo" : "Repetir") { model.startLiveTest(.scan) }
                }
                history(model.liveTests.filter { $0.kind == .scan }) { r in
                    "\(Int(r.value)) · \(Fmt.int(r.hr)) lpm · VFC \(Fmt.int(r.rmssd))"
                }
            }
            .liveScreen("Escanear", client: "scan", model: model)
        }
        .background(PulsoBackground())
    }

    private func resultCard(_ r: LiveMetrics.Scan) -> some View {
        let color: Color = (r.stress ?? 0) < 1 ? Theme.green : (r.stress ?? 0) < 2 ? Theme.yellow : Theme.red
        return PCard {
            HStack(spacing: 18) {
                LiveRing(value: Double(r.state ?? 0) / 100, text: r.state.map(String.init) ?? "–", color: color)
                    .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.label).font(.title3.bold()).foregroundStyle(color)
                    Text("Estado ahora frente a tu calma habitual (100 = como en tus mejores momentos de calma).")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            row("Pulso", "\(Int(r.hr.rounded())) lpm", signed(r.hrDelta, "lpm"))
            row("VFC (RMSSD)", Fmt.int(r.rmssd) + " ms", r.hrvRatio.map { "\(Int(($0 * 100).rounded())) % de tu normal" })
            row("Respiración", Fmt.dec(r.respRate) + " rpm")
            row("Estrés", r.stress.map { String(format: "%.1f / 3", $0) } ?? "–")
            Text("\(r.beats) latidos analizados.").font(.caption2).foregroundStyle(Theme.tertiary)
        }
    }
}

// MARK: - Poincaré

struct PoincareView: View {
    @EnvironmentObject var model: AppModel
    @State private var plot: LiveMetrics.Poincare?
    @State private var pairs = 0
    @State private var noRR = false
    @State private var updated: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PCard {
                    CardHeader(title: "Diagrama de Poincaré", subtitle: "Cada punto: un intervalo R-R (eje X) frente al siguiente (eje Y), últimos 5 min")
                    if let p = plot {
                        let lo = (p.points.map { min($0.x, $0.y) }.min() ?? 500) - 30
                        let hi = (p.points.map { max($0.x, $0.y) }.max() ?? 1200) + 30
                        Chart {
                            LineMark(x: .value("x", lo), y: .value("y", lo)).foregroundStyle(Theme.tertiary)
                            LineMark(x: .value("x", hi), y: .value("y", hi)).foregroundStyle(Theme.tertiary)
                            ForEach(Array(p.points.enumerated()), id: \.offset) { i, q in
                                PointMark(x: .value("RRn", q.x), y: .value("RRn+1", q.y))
                                    .symbolSize(18)
                                    .foregroundStyle(Theme.hrv.opacity(0.25 + 0.75 * Double(i) / Double(max(1, p.points.count))))
                            }
                        }
                        .chartXScale(domain: lo...hi)
                        .chartYScale(domain: lo...hi)
                        .chartXAxisLabel("R-R n (ms)")
                        .chartYAxisLabel("R-R n+1 (ms)")
                        .aspectRatio(1, contentMode: .fit)
                        row("SD1 (latido a latido)", "\(Int(p.sd1.rounded())) ms")
                        row("SD2 (largo plazo)", "\(Int(p.sd2.rounded())) ms")
                        row("SD1 / SD2", String(format: "%.2f", p.sd1 / max(p.sd2, 1)).replacingOccurrences(of: ".", with: ","))
                        row("Pares de latidos", "\(p.points.count)")
                        if let updated {
                            Text("Actualizado a las \(updated.formatted(.dateTime.hour().minute().second())).").font(.caption2).foregroundStyle(Theme.tertiary)
                        }
                        Text("Una nube ancha y redonda (SD1/SD2 alto) = mucha variabilidad latido a latido, típico de calma. Un puro estrecho y alargado (SD1/SD2 bajo) = domina el sistema nervioso acelerado: estrés, esfuerzo o cansancio.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    } else if noRR {
                        Label("Tu pulsera está enviando pulso sin intervalos R-R: no se puede dibujar.", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(Theme.yellow)
                    } else if let why = model.liveToolBlocker {
                        Label(why, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Theme.secondary)
                    } else {
                        Text("Juntando latidos: \(pairs) de 10 pares limpios. Quédate quieto.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .liveScreen("Poincaré", client: "poincare", model: model)
        }
        .background(PulsoBackground())
        .task {
            while !Task.isCancelled {
                recompute()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func recompute() {
        let now = Date()
        let beats = model.beats(since: now.addingTimeInterval(-300))
        plot = LiveMetrics.poincare(beats)
        pairs = LiveMetrics.runs(beats).reduce(0) { $0 + max(0, $1.count - 1) }
        let recentPulse = model.livePoints.filter { $0.date >= now.addingTimeInterval(-30) }.count
        noRR = plot == nil && recentPulse >= 15 && model.beats(since: now.addingTimeInterval(-30)).isEmpty
        if plot != nil { updated = now }
    }
}

// MARK: - Guided breathing and coherence

/// Paced breathing with live coherence feedback, a timer and a before/after result.
struct BreathingView: View {
    @EnvironmentObject var model: AppModel
    @State private var pace = 6.0
    @State private var minutes = 5
    @State private var explain = false

    var body: some View {
        let run = model.liveLab.running(.breathing)
        let outcome = model.liveLab.outcomes[.breathing]
        ScrollView {
            VStack(spacing: 18) {
                if let run {
                    pacer(run)
                    paceStepper(Binding(get: { run.pace }, set: { model.setBreathingPace($0) }))
                    if run.scores.count > 1 { coherenceChart(run.scores.map(\.hr)) }
                    if let c = run.coherence {
                        Text("Tu pulso oscila a \(Fmt.dec(c.peakPerMinute)) ciclos por minuto; tú respiras a \(Fmt.dec(run.pace)). Cuanto más se parezcan y más regular sea la ola, más coherencia.")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    } else {
                        Text(run.beats.isEmpty && run.samplesInPhase() >= 15
                             ? "Llega pulso pero sin intervalos R-R: la coherencia no se puede medir. El ritmo guiado sigue sirviendo."
                             : "La coherencia aparece tras ~1 minuto de latidos con R-R.")
                            .font(.caption).foregroundStyle(run.beats.isEmpty ? Theme.yellow : Theme.secondary)
                    }
                    Button("Terminar ya") { model.finishLiveTestNow() }
                        .buttonStyle(PrimaryCapsuleStyle())
                    cancelButton(model)
                } else {
                    if case .breathing(let r)? = outcome { resultCard(r) }
                    explainer
                    paceStepper($pace)
                    Picker("Duración", selection: $minutes) {
                        ForEach([1, 3, 5, 10], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    StartTestButton(title: outcome == nil ? "Empezar" : "Otra sesión") {
                        model.startLiveTest(.breathing, pace: pace, minutes: minutes)
                    }
                    sessionsHistory
                }
            }
            .liveScreen("Respiración", client: "breathing", model: model)
        }
        .background(PulsoBackground())
    }

    /// Circle grows while inhaling (40 % of the cycle) and shrinks while exhaling; a pace change restarts on an inhale.
    private func pacer(_ run: LiveRun) -> some View {
        TimelineView(.animation) { ctx in
            let period = 60 / run.pace
            let t = max(0, ctx.date.timeIntervalSince(run.paceAnchor)).truncatingRemainder(dividingBy: period)
            let inT = period * 0.4
            let inhale = t < inT
            let x = inhale ? t / inT : 1 - (t - inT) / (period - inT)
            let s = 0.45 + 0.55 * (0.5 - 0.5 * cos(.pi * x))
            let left = run.remaining(at: ctx.date) ?? 0
            let c = coherenceColor(run.coherence)
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(c.opacity(0.12)).frame(width: 240, height: 240)
                    Circle().fill(c.opacity(0.55)).frame(width: 240 * s, height: 240 * s)
                    VStack(spacing: 0) {
                        Text(run.coherence.map { "\($0.score)" } ?? "–").scaledFont(46, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3).foregroundStyle(.white)
                        Caps(run.coherence.map { "Coherencia \($0.level)" } ?? "Midiendo", size: 10, color: .white.opacity(0.8))
                    }
                }
                Text(inhale ? "Inspira" : "Espira").font(.title2.bold()).foregroundStyle(.white)
                Text("Quedan \(LiveView.duration(left.rounded(.up)))").font(.headline.monospacedDigit()).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func paceStepper(_ value: Binding<Double>) -> some View {
        Stepper("Ritmo: \(Fmt.dec(value.wrappedValue)) resp/min", value: value, in: 4.5...8, step: 0.5)
            .foregroundStyle(.white)
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func coherenceChart(_ scores: [Double]) -> some View {
        Chart(Array(scores.enumerated()), id: \.offset) { i, v in
            LineMark(x: .value("t", i), y: .value("coherencia", v)).foregroundStyle(Theme.hrv).interpolationMethod(.catmullRom)
            AreaMark(x: .value("t", i), y: .value("coherencia", v))
                .foregroundStyle(LinearGradient(colors: [Theme.hrv.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .frame(height: 90)
    }

    private var explainer: some View {
        PCard {
            CardHeader(title: "Respiración guiada y coherencia")
            Text("Respira por la nariz siguiendo el círculo: crece al inspirar y se encoge al espirar (espirar un poco más largo calma).")
                .font(.subheadline).foregroundStyle(Color(white: 0.82))
            DisclosureGroup(isExpanded: $explain) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coherencia (resonancia): al inspirar el pulso sube y al espirar baja. Respirando lento y regular, esa subida y bajada se convierte en una ola grande y limpia, porque el reflejo que regula la tensión arterial entra en resonancia con tu respiración. La puntuación (0–100) mide cuánta de tu variabilidad está en esa única ola.")
                    Text("Por qué ~6 por minuto: es la frecuencia de resonancia típica de un adulto (entre 4,5 y 7 según la persona).")
                    Text("Si lo subes a 7 u 8: es más cómodo si 6 te deja sin aire, pero la ola suele ser algo menor. Prueba varios ritmos en días distintos: el que te dé más coherencia es el tuyo.")
                    Text("Es una medida de este rato. No garantiza mejora y no sustituye a la VFC nocturna.")
                        .foregroundStyle(Theme.secondary)
                }
                .font(.caption).foregroundStyle(Color(white: 0.82))
                .padding(.top, 6)
            } label: {
                Text("Qué es y por qué 6 por minuto").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
            .tint(.white)
        }
    }

    private func resultCard(_ r: BreathingRecord) -> some View {
        PCard {
            CardHeader(title: "Resultado", subtitle: "\(LiveView.duration(r.seconds)) a \(Fmt.dec(r.pace)) resp/min · \(Fmt.clock(r.date))")
            row(r.beforeIsFirstMinute ? "VFC primer minuto" : "VFC antes", r.rmssdBefore.map { "\(Int($0.rounded())) ms" } ?? "–")
            row("VFC último minuto", r.rmssdAfter.map { "\(Int($0.rounded())) ms" } ?? "–")
            row("Coherencia media", Fmt.int(r.coherenceMean))
            if let a = r.coherenceStart, let b = r.coherenceEnd {
                row("Coherencia al principio → al final", "\(Int(a.rounded())) → \(Int(b.rounded()))")
            }
            if r.scores.count > 1 { coherenceChart(r.scores) }
            Text(note(r)).font(.caption).foregroundStyle(Theme.secondary)
            Text("Calculado con \(r.beats) latidos con R-R. Un cambio en una sesión no garantiza mejora: lo que cuenta es la tendencia con el tiempo.")
                .font(.caption2).foregroundStyle(Theme.tertiary)
        }
    }

    private func note(_ r: BreathingRecord) -> String {
        guard let a = r.rmssdBefore, let b = r.rmssdAfter else {
            if r.beats == 0 { return "No llegaron intervalos R-R: no hay VFC ni coherencia de esta sesión." }
            return "No hubo latidos limpios suficientes para comparar antes y después (hace falta más de 1,5 min)."
        }
        let d = (b - a) / max(a, 1) * 100
        if abs(d) < 10 { return "Tu VFC quedó parecida a la del principio." }
        return d > 0 ? "Tu VFC subió un \(Int(d.rounded())) % durante la sesión." : "Tu VFC bajó un \(Int((-d).rounded())) %: puede pasar si el ritmo te costó."
    }

    private var sessionsHistory: some View {
        let all = model.breathingSessions
        return VStack(alignment: .leading, spacing: 8) {
            if !all.isEmpty {
                SectionHeading(text: "Historial")
                ForEach(all.suffix(12).reversed()) { r in
                    HStack {
                        Text(r.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.caption).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text("\(LiveView.duration(r.seconds)) · \(Fmt.dec(r.pace)) rpm · coh. \(Fmt.int(r.coherenceMean))")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.white)
                    }
                    .padding(.vertical, 4)
                    .overlay(alignment: .bottom) { Divider().overlay(Theme.hairline) }
                }
            }
        }
    }

    private func coherenceColor(_ c: LiveMetrics.Coherence?) -> Color {
        guard let c else { return Theme.hrv }
        return c.score >= 70 ? Theme.green : c.score >= 40 ? Theme.hrv : Theme.stress
    }
}

typealias CoherenceView = BreathingView

// MARK: - Orthostatic test

struct OrthostaticTestView: View {
    @EnvironmentObject var model: AppModel
    private static let steps = ["Preparación", "Tumbado 2 min", "Levántate", "De pie 3 min", "Análisis", "Resultado"]

    var body: some View {
        let run = model.liveLab.running(.orthostatic)
        let outcome = model.liveLab.outcomes[.orthostatic]
        ScrollView {
            VStack(spacing: 18) {
                if let run {
                    PhaseSteps(steps: Self.steps, current: stepIndex(run.phase))
                    RunClock(run: run, title: title(run.phase), hint: hint(run.phase))
                    PhaseBeatsNote(run: run)
                    cancelButton(model)
                } else {
                    if let outcome {
                        if case .orthostatic(let r) = outcome {
                            PhaseSteps(steps: Self.steps, current: 6)
                            resultCard(r)
                        } else {
                            PhaseSteps(steps: Self.steps, current: 4)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Mejor por la mañana, nada más despertar y antes del café.", systemImage: "sunrise")
                            Label("15 s para tumbarte, 2 min tumbado y quieto, la pulsera vibra, te levantas y 3 min de pie.", systemImage: "figure.stand")
                            Label("Mide cómo se adapta tu sistema nervioso al cambio de postura: un indicador clásico de fatiga y sobreentrenamiento.", systemImage: "info.circle")
                        }
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    failure(outcome)
                    StartTestButton(title: outcome == nil ? "Empezar" : "Repetir") { model.startLiveTest(.orthostatic) }
                }
                history(model.liveTests.filter { $0.kind == .orthostatic }) { r in "+\(Int(r.value)) lpm · \(r.detail)" }
            }
            .liveScreen("Test ortostático", client: "orthostatic", model: model)
        }
        .background(PulsoBackground())
    }

    private func stepIndex(_ p: LiveRun.Phase) -> Int {
        switch p {
        case .prepare: return 0
        case .lying: return 1
        case .standUp: return 2
        default: return 3
        }
    }

    private func title(_ p: LiveRun.Phase) -> String {
        switch p {
        case .prepare: return "Túmbate"
        case .lying: return "Tumbado, quieto"
        case .standUp: return "¡Levántate ahora!"
        default: return "De pie, quieto"
        }
    }

    private func hint(_ p: LiveRun.Phase) -> String {
        switch p {
        case .prepare: return "Boca arriba y cómodo. Al acabar la cuenta empieza la medida tumbado."
        case .lying: return "Respira normal, sin hablar. Cuando vibre la pulsera, levántate."
        case .standUp: return "Ponte de pie de una vez y quédate quieto."
        default: return "Brazos relajados, sin hablar ni moverte."
        }
    }

    private func resultCard(_ r: LiveMetrics.Orthostatic) -> some View {
        PCard {
            CardHeader(title: "Resultado")
            row("Pulso tumbado", "\(Int(r.lyingHR)) lpm")
            row("Pico al levantarte", "\(Int(r.peakHR)) lpm")
            row("Pulso de pie (min 2–3)", "\(Int(r.standingHR)) lpm")
            row("Subida", "+\(Int(r.rise.rounded())) lpm")
            row("VFC tumbado → de pie", "\(Fmt.int(r.lyingRMSSD)) → \(Fmt.int(r.standingRMSSD)) ms")
            if let q = r.ratio3015 { row("Índice 30:15", String(format: "%.2f", q)) }
            Text(r.verdict).font(.subheadline).foregroundStyle(.white)
            if let prev = model.liveTests.filter({ $0.kind == .orthostatic }).dropLast().last {
                Text("La vez anterior subiste \(Int(prev.value)) lpm. Una subida mayor de lo habitual por la mañana suele indicar fatiga acumulada.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }
}

// MARK: - Heart-rate recovery test

struct RecoveryTestView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let run = model.liveLab.running(.recovery)
        let outcome = model.liveLab.outcomes[.recovery]
        ScrollView {
            VStack(spacing: 18) {
                if let run {
                    if run.phase == .recovering {
                        RunClock(run: run, title: "Recuperando", hint: "Quédate quieto (de pie o sentado), respira normal.")
                        Text("Lecturas de pulso desde que paraste: \(run.samplesInPhase())").font(.caption).foregroundStyle(Theme.tertiary)
                    } else {
                        LiveHRReadout()
                        Text("Haz tu esfuerzo (al menos 3 min intensos). Pulsa «He parado» justo cuando pares.")
                            .font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        Button("He parado") { model.markLiveStop() }
                            .buttonStyle(PrimaryCapsuleStyle())
                    }
                    cancelButton(model)
                } else {
                    if case .recovery(let r)? = outcome {
                        PCard {
                            CardHeader(title: "Bajada en 1 minuto")
                            HStack(alignment: .firstTextBaseline) {
                                Text("−\(Int(r.drop60.rounded()))").scaledFont(52, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3).foregroundStyle(.white)
                                Text("lpm").foregroundStyle(Theme.secondary)
                                Spacer()
                                Text(r.level).font(.title3.bold()).foregroundStyle(r.drop60 >= 20 ? Theme.green : r.drop60 >= 12 ? Theme.yellow : Theme.red)
                            }
                            row("Pico al parar", "\(Int(r.peakHR)) lpm")
                            row("Al minuto", "\(Int(r.hr60)) lpm")
                            if let d = r.drop120 { row("Bajada en 2 minutos", "−\(Int(d.rounded())) lpm") }
                            Text("Cuanto más rápido baja el pulso al parar, mejor tu forma aeróbica y tu sistema nervioso. Menos de 12 lpm en el primer minuto es bajo; más de 20, bueno. Compáralo siempre con el mismo esfuerzo.")
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                    } else {
                        Text("Haz un esfuerzo intenso (una subida, un sprint, un intervalo) y, al parar, quédate quieto 2 minutos. Pulso mide cuánto baja tu pulso.")
                            .font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    }
                    failure(outcome)
                    StartTestButton(title: outcome == nil ? "Empezar" : "Repetir") { model.startLiveTest(.recovery) }
                }
                history(model.liveTests.filter { $0.kind == .recovery }) { r in "−\(Int(r.value)) lpm · \(r.detail)" }
            }
            .liveScreen("Recuperación FC", client: "hrr", model: model)
        }
        .background(PulsoBackground())
    }
}

// MARK: - Max HR test

struct MaxHRTestView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let run = model.liveLab.running(.maxHR)
        let outcome = model.liveLab.outcomes[.maxHR]
        ScrollView {
            VStack(spacing: 18) {
                if let run {
                    TimelineView(.periodic(from: run.started, by: 1)) { ctx in
                        Text(LiveView.duration(ctx.date.timeIntervalSince(run.started))).font(.title3.monospacedDigit()).foregroundStyle(Theme.secondary)
                    }
                    LiveHRReadout()
                    row("Máximo del test (media de 5 s)", run.peak.map { "\(Int($0.rounded())) lpm" } ?? "–")
                    row("Tu FC máx actual", "\(Int(model.heartRateModel.maxHR)) lpm")
                    Text("\(run.samples.count) lecturas de pulso en el test.").font(.caption).foregroundStyle(Theme.tertiary)
                    Button("Terminar") { model.finishLiveTestNow() }
                        .buttonStyle(PrimaryCapsuleStyle())
                    cancelButton(model)
                } else {
                    if case .maxHR(let f)? = outcome {
                        PCard {
                            CardHeader(title: "Resultado")
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(Int(f.rounded()))").scaledFont(52, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3).foregroundStyle(.white)
                                Text("lpm").foregroundStyle(Theme.secondary)
                            }
                            if f > model.heartRateModel.maxHR - 1 || model.profile.maxHROverride != nil {
                                Button("Usar \(Int(f.rounded())) lpm como mi FC máxima") { model.setMaxHR(Int(f.rounded())) }
                                    .buttonStyle(PrimaryCapsuleStyle())
                                Text("Tus zonas, el esfuerzo y las calorías se calcularán con este valor.").font(.caption).foregroundStyle(Theme.secondary)
                            } else {
                                Text("No has superado tu FC máx actual (\(Int(model.heartRateModel.maxHR)) lpm): seguramente no era tu máximo de verdad.")
                                    .font(.caption).foregroundStyle(Theme.secondary)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Solo si estás sano y acostumbrado a entrenar fuerte. Si tienes dudas, consúltalo antes.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Theme.yellow)
                            Label("10–15 min de calentamiento suave.", systemImage: "1.circle")
                            Label("3 min fuerte, 2 min suave.", systemImage: "2.circle")
                            Label("2–3 min a tope, acelerando hasta no poder más (mejor cuesta arriba).", systemImage: "3.circle")
                            Label("Pulsa Terminar. Pulso se queda con tu mejor media de 5 segundos.", systemImage: "4.circle")
                        }
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    failure(outcome)
                    StartTestButton(title: outcome == nil ? "Empezar test" : "Repetir") { model.startLiveTest(.maxHR) }
                }
                history(model.liveTests.filter { $0.kind == .maxHR }) { r in "\(Int(r.value)) lpm" }
            }
            .liveScreen("FC máxima", client: "maxhr", model: model)
        }
        .background(PulsoBackground())
    }
}

/// Why a live test's start button is disabled, right under it.
struct LiveBlockerNote: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let why = model.liveToolBlocker {
            Label(why, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
