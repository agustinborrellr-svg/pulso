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
                AxisValueLabel { Text("\(Int(v.as(Double.self) ?? 0))").font(.system(size: 9)).foregroundStyle(Theme.tertiary) }
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
            Text(text).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
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

/// Countdown shown while a test phase runs.
private struct PhaseClock: View {
    let start: Date
    let seconds: Double
    let title: String
    let hint: String

    var body: some View {
        TimelineView(.periodic(from: start, by: 0.5)) { ctx in
            let el = min(seconds, ctx.date.timeIntervalSince(start))
            VStack(spacing: 14) {
                LiveRing(value: el / seconds, text: LiveView.duration(seconds - el), color: Theme.link)
                    .frame(width: 200, height: 200)
                Text(title).font(.title3.bold()).foregroundStyle(.white)
                Text(hint).font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            }
        }
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

// MARK: - Scan

struct ScanView: View {
    @EnvironmentObject var model: AppModel
    @State private var start: Date?
    @State private var result: LiveMetrics.Scan?
    @State private var failed = false
    private let seconds = 60.0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let start {
                    PhaseClock(start: start, seconds: seconds, title: "Escaneando…",
                               hint: "Quédate sentado, quieto y respirando normal. No hables.")
                        .padding(.top, 12)
                } else if let r = result {
                    resultCard(r)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 54)).foregroundStyle(Theme.link)
                        Text("Siéntate, apoya el brazo y respira normal durante un minuto. Pulso compara tu pulso, tu VFC y tu respiración con tu normal en calma.")
                            .font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                }
                if failed {
                    Text("No llegaron suficientes latidos limpios. Ajusta la pulsera (un dedo por encima del hueso de la muñeca) y repite.")
                        .font(.footnote).foregroundStyle(Theme.yellow).multilineTextAlignment(.center)
                }
                if start == nil {
                    Button(result == nil ? "Empezar escaneo" : "Repetir") {
                        failed = false
                        result = nil
                        start = Date()
                    }
                    .buttonStyle(PrimaryCapsuleStyle())
                    .disabled(!model.strapState.isConnected)
                }
                history(model.liveTests.filter { $0.kind == .scan }) { r in
                    "\(Int(r.value)) · \(Fmt.int(r.hr)) lpm · VFC \(Fmt.int(r.rmssd))"
                }
            }
            .liveScreen("Escanear", client: "scan", model: model)
        }
        .background(PulsoBackground())
        .task(id: start) {
            guard let s = start else { return }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            finish(s)
        }
    }

    private func finish(_ s: Date) {
        start = nil
        guard let r = LiveMetrics.scan(model.beats(since: s), baseline: model.liveBaseline) else {
            failed = true
            return
        }
        result = r
        model.strap.buzz(loops: 1)
        model.saveLiveTest(LiveTestRecord(date: Date(), kind: .scan, value: Double(r.state ?? 0), hr: r.hr, rmssd: r.rmssd,
                                          resp: r.respRate, stress: r.stress, detail: r.label))
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
    @State private var last = Date.distantPast

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PCard {
                    CardHeader(title: "Diagrama de Poincaré", subtitle: "Cada punto: un latido (eje X) frente al siguiente (eje Y)")
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
                        .aspectRatio(1, contentMode: .fit)
                        HStack {
                            row("SD1 (corto plazo)", "\(Int(p.sd1)) ms")
                        }
                        row("SD2 (largo plazo)", "\(Int(p.sd2)) ms")
                        row("SD2 / SD1", String(format: "%.1f", p.sd2 / max(p.sd1, 1)))
                        Text("Una nube ancha y redonda = mucha variabilidad (relajado, buena recuperación). Un puro estrecho y alargado = el sistema nervioso acelerado manda (estrés, esfuerzo, cansancio).")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    } else {
                        Text("Juntando latidos… Quédate quieto un minuto.").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .liveScreen("Poincaré", client: "poincare", model: model)
        }
        .background(PulsoBackground())
        .onChange(of: model.liveHR) { _, _ in
            guard Date().timeIntervalSince(last) >= 3 else { return }
            last = Date()
            plot = LiveMetrics.poincare(model.beats(since: Date().addingTimeInterval(-300)))
        }
    }
}

// MARK: - Coherence biofeedback

struct CoherenceView: View {
    @EnvironmentObject var model: AppModel
    @State private var start = Date()
    @State private var coherence: LiveMetrics.Coherence?
    @State private var history: [Double] = []
    @State private var last = Date.distantPast
    @State private var pace = 6.0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                TimelineView(.animation) { ctx in
                    let period = 60 / pace
                    let t = ctx.date.timeIntervalSince(start).truncatingRemainder(dividingBy: period)
                    let inhale = t < period * 0.45
                    let x = inhale ? t / (period * 0.45) : 1 - (t - period * 0.45) / (period * 0.55)
                    let s = 0.5 + 0.5 * (0.5 - 0.5 * cos(.pi * x))
                    let c = coherenceColor
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(c.opacity(0.12)).frame(width: 240, height: 240)
                            Circle().fill(c.opacity(0.55)).frame(width: 240 * s, height: 240 * s)
                            VStack(spacing: 0) {
                                Text(coherence.map { "\($0.score)" } ?? "–").font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                Caps(coherence?.level ?? "Midiendo", size: 11, color: .white.opacity(0.8))
                            }
                        }
                        Text(inhale ? "Inspira" : "Espira").font(.title2.bold()).foregroundStyle(.white)
                    }
                }
                if history.count > 2 {
                    Chart(Array(history.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("coherencia", v)).foregroundStyle(Theme.hrv).interpolationMethod(.catmullRom)
                        AreaMark(x: .value("t", i), y: .value("coherencia", v))
                            .foregroundStyle(LinearGradient(colors: [Theme.hrv.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .frame(height: 90)
                }
                Stepper("Ritmo: \(String(format: "%.1f", pace)) respiraciones/min", value: $pace, in: 4.5...7, step: 0.5)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                if let c = coherence {
                    Text("Tu corazón sigue un ritmo de \(String(format: "%.1f", c.peakPerMinute)) por minuto. Cuanto más se parezca a tu respiración y más suave sea, más alta la coherencia.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Text("Respira por la nariz siguiendo el círculo. Coherencia alta = el pulso sube y baja como una ola con cada respiración: es el estado en el que el cuerpo se recupera mejor. 5–10 minutos al día.")
                    .font(.caption).foregroundStyle(Theme.tertiary)
            }
            .liveScreen("Coherencia", client: "coherence", model: model)
        }
        .background(PulsoBackground())
        .onAppear { start = Date() }
        .onChange(of: model.liveHR) { _, _ in
            guard Date().timeIntervalSince(last) >= 5 else { return }
            last = Date()
            coherence = LiveMetrics.coherence(model.liveBeats)
            if let c = coherence { history.append(Double(c.score)) }
        }
    }

    private var coherenceColor: Color {
        guard let c = coherence else { return Theme.hrv }
        return c.score >= 70 ? Theme.green : c.score >= 40 ? Theme.hrv : Theme.stress
    }
}

// MARK: - Orthostatic test

struct OrthostaticTestView: View {
    @EnvironmentObject var model: AppModel
    @State private var lyingStart: Date?
    @State private var standAt: Date?
    @State private var result: LiveMetrics.Orthostatic?
    @State private var failed = false
    private let lying = 120.0, standing = 180.0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let s = standAt {
                    PhaseClock(start: s, seconds: standing, title: "De pie, quieto", hint: "Brazos relajados, sin hablar ni moverte.")
                } else if let l = lyingStart {
                    PhaseClock(start: l, seconds: lying, title: "Tumbado, quieto", hint: "Cuando acabe, la pulsera vibra: levántate en ese momento.")
                } else if let r = result {
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
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Mejor por la mañana, nada más despertar y antes del café.", systemImage: "sunrise")
                        Label("2 min tumbado y quieto, luego 3 min de pie.", systemImage: "figure.stand")
                        Label("Mide cómo se adapta tu sistema nervioso al cambio de postura: un indicador clásico de fatiga y sobreentrenamiento.", systemImage: "info.circle")
                    }
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                if failed {
                    Text("Faltan latidos limpios para calcularlo. Ajusta la pulsera y repite.").font(.footnote).foregroundStyle(Theme.yellow)
                }
                if lyingStart == nil && standAt == nil {
                    Button(result == nil ? "Empezar (túmbate)" : "Repetir") {
                        result = nil
                        failed = false
                        lyingStart = Date()
                    }
                    .buttonStyle(PrimaryCapsuleStyle())
                    .disabled(!model.strapState.isConnected)
                }
                history(model.liveTests.filter { $0.kind == .orthostatic }) { r in "+\(Int(r.value)) lpm · \(r.detail)" }
            }
            .liveScreen("Test ortostático", client: "orthostatic", model: model)
        }
        .background(PulsoBackground())
        .task(id: lyingStart) {
            guard lyingStart != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(lying * 1_000_000_000))
            guard !Task.isCancelled, lyingStart != nil else { return }
            model.strap.buzz(loops: 2)
            if model.settings.voiceCues { model.voice.say("Levántate") }
            standAt = Date()
            lyingStart = nil
        }
        .task(id: standAt) {
            guard let s = standAt else { return }
            try? await Task.sleep(nanoseconds: UInt64(standing * 1_000_000_000))
            guard !Task.isCancelled else { return }
            standAt = nil
            model.strap.buzz(loops: 1)
            if let r = LiveMetrics.orthostatic(model.liveBeats, standAt: s.timeIntervalSince1970) {
                result = r
                model.saveLiveTest(LiveTestRecord(date: Date(), kind: .orthostatic, value: r.rise.rounded(), hr: r.standingHR,
                                                  rmssd: r.standingRMSSD, detail: "\(Int(r.lyingHR))→\(Int(r.standingHR)) lpm"))
            } else {
                failed = true
            }
        }
    }
}

// MARK: - Heart-rate recovery test

struct RecoveryTestView: View {
    @EnvironmentObject var model: AppModel
    @State private var effortStart: Date?
    @State private var stopAt: Date?
    @State private var result: LiveMetrics.Recovery?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let s = stopAt {
                    PhaseClock(start: s, seconds: 125, title: "Recuperando", hint: "Quédate quieto (de pie o sentado), respira normal.")
                } else if effortStart != nil {
                    VStack(spacing: 10) {
                        BeatingHeart(bpm: model.liveHR, color: Theme.red).frame(width: 70, height: 70)
                        Text("\(model.liveHR.map(String.init) ?? "--") lpm").font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text("Haz tu esfuerzo (al menos 3 min intensos). Pulsa «He parado» justo cuando pares.")
                            .font(.footnote).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    }
                    Button("He parado") {
                        stopAt = Date()
                        effortStart = nil
                    }
                    .buttonStyle(PrimaryCapsuleStyle())
                } else if let r = result {
                    PCard {
                        CardHeader(title: "Bajada en 1 minuto")
                        HStack(alignment: .firstTextBaseline) {
                            Text("−\(Int(r.drop60.rounded()))").font(.system(size: 52, weight: .bold, design: .rounded)).foregroundStyle(.white)
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
                if failed {
                    Text("No hay pulso suficiente alrededor del final. Repite con la pulsera bien ajustada.").font(.footnote).foregroundStyle(Theme.yellow)
                }
                if effortStart == nil && stopAt == nil {
                    Button(result == nil ? "Empezar" : "Repetir") {
                        result = nil
                        failed = false
                        effortStart = Date()
                    }
                    .buttonStyle(PrimaryCapsuleStyle())
                    .disabled(!model.strapState.isConnected)
                }
                history(model.liveTests.filter { $0.kind == .recovery }) { r in "−\(Int(r.value)) lpm · \(r.detail)" }
            }
            .liveScreen("Recuperación FC", client: "hrr", model: model)
        }
        .background(PulsoBackground())
        .task(id: stopAt) {
            guard let s = stopAt else { return }
            try? await Task.sleep(nanoseconds: 125_000_000_000)
            guard !Task.isCancelled else { return }
            stopAt = nil
            model.strap.buzz(loops: 1)
            let samples = model.liveSamples(since: s.addingTimeInterval(-40))
            if let r = LiveMetrics.recovery(samples, stopAt: s.timeIntervalSince1970) {
                result = r
                model.saveLiveTest(LiveTestRecord(date: Date(), kind: .recovery, value: r.drop60.rounded(), hr: r.peakHR, detail: r.level))
            } else {
                failed = true
            }
        }
    }
}

// MARK: - Max HR test

struct MaxHRTestView: View {
    @EnvironmentObject var model: AppModel
    @State private var start: Date?
    @State private var peak: Double?
    @State private var final: Double?
    @State private var last = Date.distantPast

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let start {
                    TimelineView(.periodic(from: start, by: 1)) { ctx in
                        Text(LiveView.duration(ctx.date.timeIntervalSince(start))).font(.title3.monospacedDigit()).foregroundStyle(Theme.secondary)
                    }
                    BeatingHeart(bpm: model.liveHR, color: Theme.red).frame(width: 70, height: 70)
                    Text("\(model.liveHR.map(String.init) ?? "--") lpm").font(.system(size: 56, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    row("Máximo del test (5 s)", peak.map { "\(Int($0)) lpm" } ?? "–")
                    row("Tu FC máx actual", "\(Int(model.heartRateModel.maxHR)) lpm")
                    Button("Terminar") {
                        final = peak
                        self.start = nil
                        if let p = final {
                            model.saveLiveTest(LiveTestRecord(date: Date(), kind: .maxHR, value: p.rounded(), hr: p, detail: "test"))
                        }
                    }
                    .buttonStyle(PrimaryCapsuleStyle())
                } else if let f = final {
                    PCard {
                        CardHeader(title: "Resultado")
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(f))").font(.system(size: 52, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("lpm").foregroundStyle(Theme.secondary)
                        }
                        if f > model.heartRateModel.maxHR - 1 || model.profile.maxHROverride != nil {
                            Button("Usar \(Int(f)) lpm como mi FC máxima") { model.setMaxHR(Int(f)) }
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
                if start == nil {
                    Button(final == nil ? "Empezar test" : "Repetir") {
                        final = nil
                        peak = nil
                        start = Date()
                    }
                    .buttonStyle(PrimaryCapsuleStyle())
                    .disabled(!model.strapState.isConnected)
                }
                history(model.liveTests.filter { $0.kind == .maxHR }) { r in "\(Int(r.value)) lpm" }
            }
            .liveScreen("FC máxima", client: "maxhr", model: model)
        }
        .background(PulsoBackground())
        .onChange(of: model.liveHR) { _, _ in
            guard let s = start, Date().timeIntervalSince(last) >= 2 else { return }
            last = Date()
            peak = LiveMetrics.peakHR(model.liveSamples(since: s))
        }
    }
}
