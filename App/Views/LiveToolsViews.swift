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

// MARK: - Test screen chrome (redesign)

/// A test screen: DS bar and column, the live stream on while it is open.
private struct TestScreen<Content: View>: View {
    @EnvironmentObject var model: AppModel
    let title: String
    var subtitle: String?
    var back: String?
    let client: String
    @ViewBuilder var content: Content

    var body: some View {
        DSScreen(title, subtitle: subtitle, back: back) { content }
            .onAppear { model.setLive(true, client: client) }
            .onDisappear { model.setLive(false, client: client) }
    }
}

/// Start / repeat a test (neutral capsule), disabled with the reason when there are no fresh beats or another test runs.
private struct DSStartTest: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let action: () -> Void

    var body: some View {
        let other = model.liveLab.run
        Button(title, action: action)
            .buttonStyle(DSButtonStyle(size: .xl, gray: true, fullWidth: true))
            .disabled(model.liveToolBlocker != nil || other != nil)
            .opacity(model.liveToolBlocker != nil || other != nil ? 0.5 : 1)
            .padding(.top, 6)
        if let other {
            Text("Hay otro test en curso: \(other.kind.title). Termínalo o cancélalo primero.").dsFont(13).foregroundStyle(DS.t2)
        } else if let why = model.liveToolBlocker {
            Text(why).dsFont(13).foregroundStyle(DS.t2)
        }
    }
}

private func dsCancel(_ model: AppModel) -> some View {
    Button("Cancelar") { model.cancelLiveTest() }
        .buttonStyle(DSButtonStyle(tint: DSLevel.baja.ink, size: .xl, fullWidth: true))
        .padding(.top, 6)
}

private func dsFailure(_ outcome: LiveOutcome?) -> some View {
    Group {
        if case .failed(let why)? = outcome {
            Label(why, systemImage: "exclamationmark.triangle").dsFont(14).foregroundStyle(DSLevel.justa.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Countdown card of a running phase: optional step dashes, title, big clock, hint.
private struct DSRunCard: View {
    let run: LiveRun
    let title: String
    let hint: String
    var steps: [String] = []
    var current = 0

    var body: some View {
        TimelineView(.periodic(from: run.phaseStart, by: 0.5)) { ctx in
            VStack(spacing: 10) {
                if !steps.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(steps.indices, id: \.self) { i in
                            Capsule().fill(i < current ? DS.t3 : (i == current ? DS.t1 : DS.fill))
                                .frame(maxWidth: .infinity).frame(height: 5)
                        }
                    }
                    Text("Paso \(current + 1) de \(steps.count) · \(steps[min(current, steps.count - 1)])")
                        .dsFont(14).foregroundStyle(DS.t2).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(title).dsFont(22, .semibold, relativeTo: .title2).foregroundStyle(DS.t1).padding(.top, 8)
                if let left = run.remaining(at: ctx.date) {
                    Text(LiveView.duration(left.rounded(.up))).dsFont(76, .semibold, relativeTo: .largeTitle, maxScale: 1.15)
                        .foregroundStyle(DS.t1).contentTransition(.numericText())
                } else {
                    Text(LiveView.duration(ctx.date.timeIntervalSince(run.phaseStart))).dsFont(76, .semibold, relativeTo: .largeTitle, maxScale: 1.15)
                        .foregroundStyle(DS.t1)
                }
                Text(hint).dsFont(15).foregroundStyle(DS.t2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .dsCard(padding: 16)
        }
    }
}

private func beatsNote(_ run: LiveRun) -> some View {
    Group {
        if run.phaseLacksRR {
            Label("Llega pulso pero sin intervalos R-R en esta fase: no servirá para el cálculo. Ajusta la pulsera.",
                  systemImage: "exclamationmark.triangle").dsFont(13).foregroundStyle(DSLevel.justa.ink)
        } else {
            Text("Latidos con R-R en esta fase: \(run.beatsInPhase())").dsFont(13).foregroundStyle(DS.t3)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// Value with a small note under it, right-aligned (side table of a result).
private func resultRow(_ k: String, _ v: String, _ note: String? = nil) -> some View {
    HStack(alignment: .center) {
        Text(k).dsFont(15).foregroundStyle(DS.t2)
        Spacer(minLength: 6)
        VStack(alignment: .trailing, spacing: 1) {
            Text(v).dsFont(17, .semibold).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
            if let note { Text(note).dsFont(12.5).foregroundStyle(DS.t3).lineLimit(1).minimumScaleFactor(0.8) }
        }
    }
    .frame(minHeight: 46)
}

// MARK: - Scan (30)

struct ScanView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let run = model.liveLab.running(.scan)
        let outcome = model.liveLab.outcomes[.scan]
        let records = model.liveTests.filter { $0.kind == .scan }
        TestScreen(title: "Chequeo de 60 s", client: "scan") {
            if let run {
                DSRunCard(run: run, title: run.extended ? "Faltan latidos: alargando hasta 90 s" : "Escaneando…",
                          hint: "Quédate sentado, quieto y respirando normal. No hables.")
                beatsNote(run)
                dsCancel(model)
            } else {
                if case .scan(let r)? = outcome {
                    hero(state: r.state, label: r.label, stress: r.stress, rows: [
                        ("Pulso", "\(Int(r.hr.rounded())) lpm", r.hrDelta.map { "\(ActFmt.signedInt($0)) vs. tu calma" }),
                        ("VFC", r.rmssd.map { "\(Int($0.rounded())) ms" } ?? "–", r.hrvRatio.map { "\(Int(($0 * 100).rounded())) % de tu normal" }),
                        ("Respiración", r.respRate.map { "\(Fmt.dec($0)) rpm" } ?? "–", nil),
                    ], footer: "\(r.beats) latidos analizados · ahora")
                } else if let last = records.last {
                    hero(state: Int(last.value), label: last.detail, stress: last.stress, rows: [
                        ("Pulso", last.hr.map { "\(Int($0.rounded())) lpm" } ?? "–", nil),
                        ("VFC", last.rmssd.map { "\(Int($0.rounded())) ms" } ?? "–", nil),
                        ("Respiración", last.resp.map { "\(Fmt.dec($0)) rpm" } ?? "–", nil),
                    ], footer: "Último chequeo · \(ActHistory.date(last.date))")
                } else {
                    DSEmptyState(icon: "dot.radiowaves.left.and.right", title: "Un minuto quieto",
                                 message: "Siéntate, apoya el brazo y respira normal. Pulso compara tu pulso, tu VFC y tu respiración con tu normal en calma.")
                }
                dsFailure(outcome)
                DSStartTest(title: outcome == nil && records.isEmpty ? "Empezar chequeo" : "Repetir") { model.startLiveTest(.scan) }
            }
            ActHistory(rows: ActHistory.rows(records) { r in "\(Int(r.value)) · \(Fmt.int(r.hr)) lpm · VFC \(Fmt.int(r.rmssd))" })
        }
    }

    private func hero(state: Int?, label: String, stress: Double?, rows: [(String, String, String?)], footer: String) -> some View {
        let lv = stress.map { DSLevel(stress: $0) } ?? state.map { DSLevel(score: Double($0)) } ?? .justa
        var all = rows
        if let s = stress { all.append(("Estrés", "\(Fmt.dec(s)) / 3", s < 1 ? "Bajo" : (s < 2 ? "Medio" : "Alto"))) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 4) {
                    ScoreArc(progress: Double(state ?? 0) / 100, color: lv.mark, value: state.map(String.init) ?? "–", size: 118, line: 9)
                    ActLevelLine(text: label, color: lv.mark, ink: lv.ink).lineLimit(1).minimumScaleFactor(0.7)
                    Text("frente a tu calma").dsFont(14).foregroundStyle(DS.t2)
                }
                .frame(width: 136)
                VStack(spacing: 0) {
                    ForEach(all.indices, id: \.self) { i in
                        if i > 0 { DSDivider() }
                        resultRow(all[i].0, all[i].1, all[i].2)
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(DS.sep).frame(width: 0.5) }
            }
            Text(footer).dsFont(13).foregroundStyle(DS.t3)
        }
        .dsCard(padding: 14)
    }
}

// MARK: - Poincaré (34)

struct PoincareView: View {
    @EnvironmentObject var model: AppModel
    @State private var plot: LiveMetrics.Poincare?
    @State private var pairs = 0
    @State private var noRR = false
    @State private var updated: Date?

    var body: some View {
        TestScreen(title: "Poincaré", subtitle: updated.map { "actualizado \($0.formatted(.dateTime.hour().minute().second()))" },
                   back: "Actividad", client: "poincare") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cada punto: un latido frente al siguiente · últimos 5 min").dsFont(14).foregroundStyle(DS.t2)
                if let p = plot {
                    let lo = (p.points.map { min($0.x, $0.y) }.min() ?? 500) - 30
                    let hi = (p.points.map { max($0.x, $0.y) }.max() ?? 1200) + 30
                    Chart {
                        LineMark(x: .value("x", lo), y: .value("y", lo), series: .value("s", "diag"))
                            .foregroundStyle(DS.t3).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        LineMark(x: .value("x", hi), y: .value("y", hi), series: .value("s", "diag"))
                            .foregroundStyle(DS.t3).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(Array(p.points.enumerated()), id: \.offset) { i, q in
                            PointMark(x: .value("RRn", q.x), y: .value("RRn+1", q.y))
                                .symbolSize(22)
                                .foregroundStyle(DS.sueno.opacity(0.35 + 0.65 * Double(i) / Double(max(1, p.points.count))))
                        }
                    }
                    .chartXScale(domain: lo...hi)
                    .chartYScale(domain: lo...hi)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(DS.sep); AxisValueLabel().foregroundStyle(DS.t3) } }
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(DS.sep) } }
                    .chartXAxisLabel(position: .bottomTrailing) { Text("R-R n (ms)").dsFont(13).foregroundStyle(DS.t3) }
                    .chartYAxisLabel(position: .topLeading) { Text("R-R n+1").dsFont(13).foregroundStyle(DS.t3) }
                    .aspectRatio(1, contentMode: .fit)
                    DSDivider()
                    DSStatStrip(stats: [
                        DSStat(label: "SD1", value: "\(Int(p.sd1.rounded()))", unit: "ms"),
                        DSStat(label: "SD2", value: "\(Int(p.sd2.rounded()))", unit: "ms"),
                        DSStat(label: "SD1/SD2", value: Fmt.dec(p.sd1 / max(p.sd2, 1), 2)),
                        DSStat(label: "Pares", value: "\(p.points.count)"),
                    ])
                } else if noRR {
                    Label("Tu pulsera está enviando pulso sin intervalos R-R: no se puede dibujar.", systemImage: "exclamationmark.triangle")
                        .dsFont(14).foregroundStyle(DSLevel.justa.ink)
                } else if let why = model.liveToolBlocker {
                    Text(why).dsFont(15).foregroundStyle(DS.t2)
                } else {
                    Text("Juntando latidos: \(pairs) de 10 pares limpios. Quédate quieto.").dsFont(15).foregroundStyle(DS.t2)
                }
            }
            .dsCard(padding: 14)
            HStack(alignment: .top, spacing: 16) {
                legend("Ancha y redonda", "mucha variabilidad: calma")
                legend("Estrecha y alargada", "estrés, esfuerzo o cansancio")
            }
            .dsCard(padding: 14)
        }
        .task {
            while !Task.isCancelled {
                recompute()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func legend(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).dsFont(16, .semibold).foregroundStyle(DS.t1)
            Text(s).dsFont(15).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Orthostatic test (31)

struct OrthostaticTestView: View {
    @EnvironmentObject var model: AppModel
    private static let steps = ["Preparación", "Tumbado 2 min", "Levántate", "De pie 3 min", "Análisis", "Resultado"]

    var body: some View {
        let run = model.liveLab.running(.orthostatic)
        let outcome = model.liveLab.outcomes[.orthostatic]
        let records = model.liveTests.filter { $0.kind == .orthostatic }
        TestScreen(title: "Test ortostático", client: "orthostatic") {
            if let run {
                DSRunCard(run: run, title: title(run.phase), hint: hint(run.phase), steps: Self.steps, current: stepIndex(run.phase))
                pulseCard(run)
                dsCancel(model)
            } else {
                if case .orthostatic(let r)? = outcome {
                    resultCard(r)
                } else if let last = records.last {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Último test · \(ActHistory.date(last.date))").dsFont(14).foregroundStyle(DS.t2)
                        ActBigValue(value: ActFmt.signedInt(last.value), unit: "lpm", size: 60)
                        Text("Subida al levantarte · \(last.detail)").dsFont(15).foregroundStyle(DS.t2)
                    }
                    .dsCard(padding: 16)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Mejor por la mañana, nada más despertar y antes del café.", systemImage: "sunrise")
                        Label("15 s para tumbarte, 2 min tumbado y quieto, la pulsera vibra, te levantas y 3 min de pie.", systemImage: "figure.stand")
                        Label("Mide cómo se adapta tu sistema nervioso al cambio de postura: un indicador clásico de fatiga.", systemImage: "info.circle")
                    }
                    .dsFont(15).foregroundStyle(DS.t2)
                    .dsCard(padding: 16)
                }
                dsFailure(outcome)
                DSStartTest(title: outcome == nil && records.isEmpty ? "Empezar" : "Repetir") { model.startLiveTest(.orthostatic) }
            }
            ActHistory(rows: ActHistory.rows(records) { r in "\(ActFmt.signedInt(r.value)) lpm · \(r.detail)" })
        }
    }

    private func pulseCard(_ run: LiveRun) -> some View {
        let start = run.started.timeIntervalSince1970
        let pts = run.samples.map { ActHRChart.P(t: Date(timeIntervalSince1970: $0.t), v: $0.hr) }
        let standAt = run.standAt
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "heart.fill").font(.system(size: 14)).foregroundStyle(DS.cor)
                Text("Pulso").dsFont(16, .semibold).foregroundStyle(DS.t2)
                Spacer()
                HoyValue(value: model.liveHR.map(String.init) ?? "--", unit: "lpm", size: 20)
            }
            if pts.count >= 2 {
                let vals = pts.map(\.v)
                let lo = (vals.min() ?? 50) - 8, hi = (vals.max() ?? 100) + 8
                Chart {
                    if let a = pts.first?.t {
                        RectangleMark(xStart: .value("a", a), xEnd: .value("b", standAt ?? pts.last!.t),
                                      yStart: .value("lo", lo), yEnd: .value("hi", hi))
                            .foregroundStyle(DS.recarga.opacity(0.12))
                            .annotation(position: .overlay, alignment: .topLeading) {
                                Text("Tumbado").dsFont(12, .semibold, relativeTo: .caption1).foregroundStyle(DS.recarga).padding(4)
                            }
                    }
                    ForEach(pts) { p in
                        LineMark(x: .value("t", p.t), y: .value("v", p.v)).foregroundStyle(DS.cor)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round)).interpolationMethod(.monotone)
                    }
                    if let last = pts.last {
                        PointMark(x: .value("t", last.t), y: .value("v", last.v)).foregroundStyle(DS.cor).symbolSize(50)
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(DS.sep)
                        AxisValueLabel().foregroundStyle(DS.t3)
                    }
                }
                .frame(height: 130)
                HStack {
                    Text("0:00").foregroundStyle(DS.t3)
                    Spacer()
                    Text("Ahora").fontWeight(.semibold).foregroundStyle(DS.t1)
                    Text(LiveView.duration((pts.last?.t.timeIntervalSince1970 ?? start) - start)).foregroundStyle(DS.t3).padding(.leading, 12)
                }
                .dsFont(13, relativeTo: .footnote)
                .padding(.trailing, 30)
            }
            beatsNote(run)
        }
        .dsCard(padding: 14)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Subida al levantarte").dsFont(14).foregroundStyle(DS.t2)
            ActBigValue(value: ActFmt.signedInt(r.rise), unit: "lpm", size: 60)
            Text(r.verdict).dsFont(15).foregroundStyle(DS.t1).fixedSize(horizontal: false, vertical: true)
            DSDivider().padding(.vertical, 4)
            resultRow("Pulso tumbado", "\(Int(r.lyingHR)) lpm")
            DSDivider()
            resultRow("Pico al levantarte", "\(Int(r.peakHR)) lpm")
            DSDivider()
            resultRow("De pie (min 2–3)", "\(Int(r.standingHR)) lpm")
            DSDivider()
            resultRow("VFC tumbado → de pie", "\(Fmt.int(r.lyingRMSSD)) → \(Fmt.int(r.standingRMSSD)) ms")
            if let q = r.ratio3015 {
                DSDivider()
                resultRow("Índice 30:15", Fmt.dec(q, 2))
            }
            if let prev = model.liveTests.filter({ $0.kind == .orthostatic }).dropLast().last {
                Text("La vez anterior subiste \(Int(prev.value)) lpm. Una subida mayor de lo habitual por la mañana suele indicar fatiga acumulada.")
                    .dsFont(13).foregroundStyle(DS.t3).padding(.top, 4)
            }
        }
        .dsCard(padding: 16)
    }
}

// MARK: - Heart-rate recovery test (32)

struct RecoveryTestView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let run = model.liveLab.running(.recovery)
        let outcome = model.liveLab.outcomes[.recovery]
        let records = model.liveTests.filter { $0.kind == .recovery }
        TestScreen(title: "Recuperación FC", client: "hrr") {
            if let run {
                if run.phase == .recovering {
                    DSRunCard(run: run, title: "Recuperando", hint: "Quédate quieto (de pie o sentado), respira normal.")
                    Text("Lecturas de pulso desde que paraste: \(run.samplesInPhase())").dsFont(13).foregroundStyle(DS.t3)
                } else {
                    VStack(spacing: 10) {
                        ActBigValue(value: model.liveHR.map(String.init) ?? "--", unit: "lpm", size: 76)
                        Text("Haz tu esfuerzo (al menos 3 min intensos). Pulsa «He parado» justo cuando pares.")
                            .dsFont(15).foregroundStyle(DS.t2).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .dsCard(padding: 16)
                    Button("He parado") { model.markLiveStop() }
                        .buttonStyle(DSButtonStyle(tint: DS.act, size: .xl, fullWidth: true))
                }
                dsCancel(model)
            } else {
                if case .recovery(let r)? = outcome {
                    resultCard(r)
                } else if let last = records.last {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bajada en 1 minuto · \(ActHistory.date(last.date))").dsFont(14).foregroundStyle(DS.t2)
                        ActBigValue(value: "−\(Int(last.value.rounded()))", unit: "lpm", size: 60)
                        level(last.value)
                        if !last.detail.isEmpty { Text(last.detail).dsFont(15).foregroundStyle(DS.t2) }
                    }
                    .dsCard(padding: 16)
                } else {
                    Text("Haz un esfuerzo intenso (una subida, un sprint, un intervalo) y, al parar, quédate quieto 2 minutos. Pulso mide cuánto baja tu pulso.")
                        .dsFont(15).foregroundStyle(DS.t2).dsCard(padding: 16)
                }
                scale(drop: drop(outcome) ?? records.last?.value)
                dsFailure(outcome)
                DSStartTest(title: outcome == nil && records.isEmpty ? "Empezar" : "Repetir") { model.startLiveTest(.recovery) }
            }
            ActHistory(rows: ActHistory.rows(records) { r in "−\(Int(r.value.rounded())) lpm" })
        }
    }

    private func drop(_ o: LiveOutcome?) -> Double? {
        if case .recovery(let r)? = o { return r.drop60 }
        return nil
    }

    private func level(_ drop: Double) -> some View {
        let lv: DSLevel = drop >= 20 ? .buena : (drop >= 12 ? .justa : .baja)
        return ActLevelLine(text: lv.word, color: lv.mark, ink: lv.ink)
    }

    private func resultCard(_ r: LiveMetrics.Recovery) -> some View {
        var pts: [(Double, Double)] = [(0, r.peakHR), (60, r.hr60)]
        if let h = r.hr120 { pts.append((120, h)) }
        let lo = (pts.map(\.1).min() ?? 100) - 10, hi = (pts.map(\.1).max() ?? 160) + 6
        return VStack(alignment: .leading, spacing: 10) {
            Text("Bajada en 1 minuto").dsFont(14).foregroundStyle(DS.t2)
            ActBigValue(value: "−\(Int(r.drop60.rounded()))", unit: "lpm", size: 60)
            level(r.drop60)
            Chart {
                ForEach(pts, id: \.0) { p in
                    LineMark(x: .value("s", p.0), y: .value("lpm", p.1)).foregroundStyle(DS.cor)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round)).interpolationMethod(.monotone)
                    PointMark(x: .value("s", p.0), y: .value("lpm", p.1))
                        .symbol { Circle().stroke(DS.cor, lineWidth: 2).background(Circle().fill(DS.card)).frame(width: 12, height: 12) }
                }
                RuleMark(x: .value("s", 60)).foregroundStyle(DS.t3.opacity(0.6))
            }
            .chartXScale(domain: 0...Double(pts.last?.0 ?? 60))
            .chartYScale(domain: lo...hi)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(DS.sep)
                    AxisValueLabel().foregroundStyle(DS.t3)
                }
            }
            .frame(height: 140)
            DSDivider().padding(.vertical, 4)
            DSStatStrip(stats: [DSStat(label: "Al parar", value: "\(Int(r.peakHR))", unit: "lpm"),
                                DSStat(label: "A 60 s", value: "\(Int(r.hr60))", unit: "lpm")]
                        + (r.hr120.map { [DSStat(label: "A 120 s", value: "\(Int($0))", unit: "lpm")] } ?? []))
        }
        .dsCard(padding: 16)
    }

    /// «Cómo leerlo»: below 12 low, 12–20 fair, above 20 good (the app's thresholds), with your drop on it.
    @ViewBuilder
    private func scale(drop: Double?) -> some View {
        let lo = 0.0, hi = 35.0
        let p = { (v: Double) in (v - lo) / (hi - lo) }
        VStack(alignment: .leading, spacing: 8) {
            Text("Cómo leerlo").dsFont(17, .semibold).foregroundStyle(DS.t1)
            DSRangeBar(stretches: [.init(to: p(12), color: DS.baja), .init(to: p(20), color: DS.justa), .init(to: 1, color: DS.buena)],
                       marker: drop.map { min(max(p($0), 0), 1) })
            HStack {
                Text("Baja · menos de 12")
                Spacer()
                Text("Buena · más de 20")
            }
            .dsFont(13).foregroundStyle(DS.t3)
            Text("Compáralo siempre tras el mismo esfuerzo.").dsFont(15).foregroundStyle(DS.t2)
        }
        .dsCard(padding: 16)
    }
}

// MARK: - Max HR test (33)

struct MaxHRTestView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let run = model.liveLab.running(.maxHR)
        let outcome = model.liveLab.outcomes[.maxHR]
        let records = model.liveTests.filter { $0.kind == .maxHR }
        let m = model.heartRateModel
        TestScreen(title: "FC máxima", back: "Actividad", client: "maxhr") {
            if let run {
                VStack(spacing: 10) {
                    TimelineView(.periodic(from: run.started, by: 1)) { ctx in
                        Text(LiveView.duration(ctx.date.timeIntervalSince(run.started))).dsFont(17).foregroundStyle(DS.t2)
                    }
                    ActBigValue(value: model.liveHR.map(String.init) ?? "--", unit: "lpm", size: 76)
                    DSDivider()
                    resultRow("Máximo del test (media de 5 s)", run.peak.map { "\(Int($0.rounded())) lpm" } ?? "–")
                    DSDivider()
                    resultRow("Tu FC máx actual", "\(Int(m.maxHR)) lpm")
                }
                .dsCard(padding: 16)
                Button("Terminar") { model.finishLiveTestNow() }
                    .buttonStyle(DSButtonStyle(tint: DS.act, size: .xl, fullWidth: true))
                dsCancel(model)
            } else {
                if case .maxHR(let f)? = outcome {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pico del test").dsFont(14).foregroundStyle(DS.t2)
                        ActBigValue(value: "\(Int(f.rounded()))", unit: "lpm", size: 60)
                        if Int(f.rounded()) == model.profile.maxHROverride {
                            Text("Tus zonas, el esfuerzo y las calorías usan ya este valor.").dsFont(15).foregroundStyle(DS.t1)
                        } else if f > m.maxHR - 1 || model.profile.maxHROverride != nil {
                            DSDelta(text: "antes \(Int(m.maxHR)) lpm", up: f > m.maxHR)
                            Button("Usar \(Int(f.rounded())) lpm como mi FC máxima") { model.setMaxHR(Int(f.rounded())) }
                                .buttonStyle(DSButtonStyle(tint: DS.act, size: .large, fullWidth: true))
                            Text("Tus zonas, el esfuerzo y las calorías se calcularán con este valor.").dsFont(13).foregroundStyle(DS.t3)
                        } else {
                            Text("No has superado tu FC máx actual (\(Int(m.maxHR)) lpm): seguramente no era tu máximo de verdad.")
                                .dsFont(15).foregroundStyle(DS.t2)
                        }
                    }
                    .dsCard(padding: 16)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.profile.maxHROverride != nil ? "Tu FC máxima (medida)" : "Tu FC máxima (estimada)").dsFont(14).foregroundStyle(DS.t2)
                        ActBigValue(value: "\(Int(m.maxHR.rounded()))", unit: "lpm", size: 60)
                        if let last = records.last {
                            Text("Último test: \(Int(last.value)) lpm · \(ActHistory.date(last.date))").dsFont(14).foregroundStyle(DS.t2)
                        }
                    }
                    .dsCard(padding: 16)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Solo si estás sano y acostumbrado a entrenar fuerte. Si tienes dudas, consúltalo antes.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(DSLevel.justa.ink)
                        Label("10–15 min de calentamiento suave.", systemImage: "1.circle")
                        Label("3 min fuerte, 2 min suave.", systemImage: "2.circle")
                        Label("2–3 min a tope, acelerando hasta no poder más (mejor cuesta arriba).", systemImage: "3.circle")
                        Label("Pulsa Terminar. Pulso se queda con tu mejor media de 5 segundos.", systemImage: "4.circle")
                    }
                    .dsFont(15).foregroundStyle(DS.t2)
                    .dsCard(padding: 16)
                }
                DSSectionHeader("Tus zonas")
                VStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { z in
                        if z > 1 { DSDivider(inset: 24) }
                        ActZoneRow(zone: z, range: "\(ActZones.text(z, m)) lpm")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                dsFailure(outcome)
                DSStartTest(title: outcome == nil && records.isEmpty ? "Empezar test" : "Repetir") { model.startLiveTest(.maxHR) }
            }
            ActHistory(rows: ActHistory.rows(records) { r in "\(Int(r.value)) lpm" })
        }
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
