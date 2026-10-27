import SwiftUI
import PulsoStore
import PulsoECG

/// ECG history, recording (WHOOP MG) and Apple Watch imports.
struct ECGListView: View {
    @EnvironmentObject var model: AppModel
    @State private var recording = false
    @State private var simulate = false

    var body: some View {
        List {
            Section {
                if model.ecgAvailable {
                    Button {
                        simulate = false
                        recording = true
                    } label: {
                        Label("Hacer un ECG (30 s)", systemImage: "waveform.path.ecg")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(model.identity.isMG ? "ECG de la WHOOP MG: pendiente" : "Tu pulsera no tiene ECG",
                              systemImage: "waveform.path.ecg.rectangle")
                            .font(.headline)
                        Text(model.identity.isMG
                             ? "Tu pulsera es una MG, pero su protocolo de ECG aún no está documentado. Con el Laboratorio puedes capturar las tramas y, cuando se conozca el formato, se activa aquí sin cambiar nada más."
                             : "El electrocardiograma necesita los electrodos de la WHOOP MG. Todo está preparado: cuando tengas una, aparecerá aquí el botón para grabar.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                }
                Button {
                    simulate = true
                    recording = true
                } label: {
                    Label("Probar con un ECG simulado", systemImage: "play.circle")
                }
                if model.profile.healthKitEnabled {
                    Button {
                        model.importAppleWatchECGs()
                    } label: {
                        Label("Importar ECG del Apple Watch", systemImage: "applewatch")
                    }
                }
            } footer: {
                Text(Rhythm.disclaimer)
            }

            Section("Historial") {
                if model.ecgRecordings.isEmpty {
                    Text("Sin registros todavía.").foregroundStyle(Theme.secondary)
                }
                ForEach(model.ecgRecordings) { r in
                    NavigationLink {
                        ECGDetailView(recording: r)
                    } label: {
                        ECGRow(recording: r)
                    }
                }
                .onDelete { idx in
                    for i in idx { model.deleteECG(model.ecgRecordings[i]) }
                }
            }
        }
        .navigationTitle("Electrocardiograma")
        .fullScreenCover(isPresented: $recording) {
            ECGRecordView(simulated: simulate) { recording = false }
                .environmentObject(model)
        }
    }
}

struct ECGRow: View {
    let recording: ECGRecording

    var body: some View {
        let rhythm = recording.rhythm.flatMap(Rhythm.init(rawValue:)) ?? .inconclusive
        HStack {
            Image(systemName: icon(rhythm)).foregroundStyle(color(rhythm)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(rhythm.title).font(.subheadline.bold())
                Text("\(Fmt.dayTitle(DayKey.string(ts: recording.start))) \(Fmt.time(recording.start)) · \(source)")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Spacer()
            if let hr = recording.avgHR { Text("\(Int(hr)) lpm").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondary) }
        }
    }

    private var source: String {
        switch recording.source {
        case .whoopMG: return "WHOOP MG"
        case .appleWatch: return "Apple Watch"
        case .simulated: return "simulado"
        }
    }

    func icon(_ r: Rhythm) -> String {
        switch r {
        case .sinus: return "heart.fill"
        case .irregular: return "exclamationmark.triangle.fill"
        case .inconclusive: return "questionmark.circle"
        default: return "heart"
        }
    }

    func color(_ r: Rhythm) -> Color {
        switch r {
        case .sinus: return Theme.green
        case .irregular: return Theme.red
        case .inconclusive: return Theme.secondary
        default: return Theme.yellow
        }
    }
}

/// 30-second recording screen.
struct ECGRecordView: View {
    @EnvironmentObject var model: AppModel
    let simulated: Bool
    let onClose: () -> Void
    @State private var started = false
    @State private var result: ECGRecording?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let r = result {
                    ECGDetailContent(recording: r)
                } else if started {
                    Spacer()
                    ZStack {
                        Circle().stroke(Theme.red.opacity(0.2), lineWidth: 14)
                        Circle().trim(from: 0, to: model.ecgProgress)
                            .stroke(Theme.red, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: model.ecgProgress)
                        VStack {
                            Text("\(Int(30 - model.ecgProgress * 30))").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("segundos").foregroundStyle(Theme.secondary)
                        }
                    }
                    .frame(width: 220, height: 220)
                    Text(simulated ? "Generando un ECG simulado…" : "No te muevas y mantén el dedo sobre la pulsera.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                } else {
                    Spacer()
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 64)).foregroundStyle(Theme.red)
                    Text(simulated ? "ECG simulado" : "Antes de empezar").font(.title2.bold())
                    Text(simulated
                         ? "Recorre todo el proceso con datos sintéticos: grabación, análisis, trazado y PDF. No es un registro real."
                         : "Siéntate, apoya el brazo en una mesa y toca el sensor de la pulsera con un dedo de la otra mano durante 30 segundos.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal)
                    Spacer()
                    Button {
                        started = true
                        model.startECG(simulated: simulated)
                    } label: {
                        Text("Empezar").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.red)
                    .padding(.horizontal)
                }
            }
            .padding(.bottom)
            .background(PulsoBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancelar" : "Cerrar") {
                        if result == nil { model.cancelECG() }
                        onClose()
                    }
                }
            }
            .onChange(of: model.lastFinishedECG) { _, id in
                guard started, let id else { return }
                result = model.ecgRecordings.first { $0.id == id }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ECGDetailView: View {
    let recording: ECGRecording

    var body: some View {
        ScrollView { ECGDetailContent(recording: recording) }
            .background(PulsoBackground())
            .navigationTitle("ECG")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct ECGDetailContent: View {
    @EnvironmentObject var model: AppModel
    let recording: ECGRecording
    @State private var full: ECGRecording?
    @State private var analysis: ECGAnalysis?
    @State private var pdfURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let a = analysis {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.rhythm.title).font(.title2.bold())
                            Text("\(Fmt.dayTitle(DayKey.string(ts: recording.start))) · \(Fmt.time(recording.start))")
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        if let hr = a.heartRate {
                            VStack {
                                Text("\(Int(hr.rounded()))").font(.title.bold().monospacedDigit())
                                Text("lpm").font(.caption).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                    Text(a.rhythm.explanation).font(.footnote).foregroundStyle(Theme.secondary)
                    if recording.source == .simulated {
                        Label("Registro simulado: no es tu corazón.", systemImage: "info.circle").font(.caption).foregroundStyle(Theme.yellow)
                    }
                }
            }
            if let f = full {
                ECGStrip(recording: f, peaks: analysis?.rPeaks ?? [])
            }
            if let url = pdfURL {
                ShareLink(item: url) {
                    Label("Compartir PDF para el médico", systemImage: "doc.richtext").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.red)
            }
            Text(Rhythm.disclaimer).font(.caption2).foregroundStyle(Theme.tertiary)
        }
        .padding(16)
        .onAppear {
            full = model.fullECG(recording) ?? recording
            if let f = full { analysis = ECGAnalyzer.analyze(f) }
            pdfURL = model.ecgPDF(recording)
        }
    }
}

/// The trace on ECG paper (25 mm/s, 10 mm/mV), scrollable, 10 s per row.
struct ECGStrip: View {
    let recording: ECGRecording
    let peaks: [Int]

    var body: some View {
        let filtered = ECGAnalyzer.displaySignal(recording.samples, rate: recording.sampleRate)
        let rows = max(1, Int(ceil(recording.durationSeconds / 10)))
        VStack(spacing: 8) {
            ForEach(0..<rows, id: \.self) { r in
                Canvas { ctx, size in
                    let pxPerSec = size.width / 10
                    let pxPerMV = pxPerSec * 0.4 // 10 mm/mV vs 25 mm/s
                    // Grid: 1 mm (0.04 s) minor, 5 mm major.
                    for k in 0...250 {
                        let x = CGFloat(k) * pxPerSec * 0.04
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(p, with: .color(Color.red.opacity(k % 5 == 0 ? 0.35 : 0.12)), lineWidth: k % 5 == 0 ? 0.8 : 0.4)
                    }
                    var y: CGFloat = 0
                    var k = 0
                    while y <= size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: .color(Color.red.opacity(k % 5 == 0 ? 0.35 : 0.12)), lineWidth: k % 5 == 0 ? 0.8 : 0.4)
                        y += pxPerSec * 0.04
                        k += 1
                    }
                    let a = Int(Double(r) * 10 * recording.sampleRate)
                    let b = min(filtered.count, Int(Double(r + 1) * 10 * recording.sampleRate))
                    guard a < b else { return }
                    let mid = size.height / 2
                    var trace = Path()
                    let step = max(1, Int(recording.sampleRate / 200))
                    var i = a
                    while i < b {
                        let pt = CGPoint(x: CGFloat(Double(i - a) / recording.sampleRate) * pxPerSec,
                                         y: mid - CGFloat(max(-2, min(2, filtered[i]))) * pxPerMV)
                        if i == a { trace.move(to: pt) } else { trace.addLine(to: pt) }
                        i += step
                    }
                    ctx.stroke(trace, with: .color(.white), lineWidth: 1.2)
                    for p in peaks where p >= a && p < b {
                        let x = CGFloat(Double(p - a) / recording.sampleRate) * pxPerSec
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: 4, width: 4, height: 4)), with: .color(Theme.yellow))
                    }
                }
                .frame(height: 130)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
