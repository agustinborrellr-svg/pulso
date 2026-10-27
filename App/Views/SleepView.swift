import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

struct SleepView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: SleepSession?
    @State private var addingSleep = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DayHeader()
                    if let day = model.selected, let session = model.sleep(for: day) {
                        summary(day)
                        Hypnogram(session: session)
                        stages(session)
                        NightTrend(session: session)
                        nightVitals(day, session)
                        naps
                        Button {
                            editing = session
                        } label: {
                            Label("Ajustar horas de sueño", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.sleep)
                    } else {
                        EmptyState(icon: "moon.zzz", title: "Sin sueño registrado",
                                   message: "Duerme con la pulsera y sincroniza por la mañana. Si la detección falla, añádelo a mano.")
                        naps
                        Button {
                            addingSleep = true
                        } label: {
                            Label("Añadir sueño manualmente", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.sleep)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(PulsoBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editing) { s in
                SleepEditSheet(session: s)
            }
            .sheet(isPresented: $addingSleep) {
                SleepEditSheet(session: nil)
            }
        }
    }

    @ViewBuilder
    private var naps: some View {
        let list = model.naps(on: model.selectedDay)
        if !list.isEmpty {
            Card {
                SectionTitle(title: "Siestas")
                ForEach(list) { n in
                    HStack {
                        Image(systemName: "powersleep").foregroundStyle(Theme.sleep)
                        Text("\(Fmt.time(n.start)) – \(Fmt.time(n.end))").foregroundStyle(.white)
                        Spacer()
                        Text(Fmt.hm(n.asleepMinutes)).foregroundStyle(Theme.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func summary(_ d: DaySummary) -> some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                ScoreRing(progress: d.sleepPerformance ?? 0, color: Theme.sleep,
                          value: d.sleepPerformance.map { "\(Int(($0 * 100).rounded()))" } ?? "–",
                          label: "Rendimiento", unit: "%", size: 96)
                VStack(alignment: .leading, spacing: 8) {
                    row("Dormido", Fmt.hm(d.sleepMinutes))
                    row("Necesitabas", Fmt.hm(d.sleepNeedMinutes))
                    row("En cama", "\(Fmt.time(d.sleepStart)) – \(Fmt.time(d.sleepEnd))")
                    row("Deuda de sueño", Fmt.hm(d.sleepDebtMinutes))
                }
            }
            HStack {
                pill("Eficiencia", Fmt.pct(d.sleepEfficiency))
                pill("Consistencia", d.sleepConsistency.map { "\(Int($0))%" } ?? "–")
                pill("Despertares", d.disturbances.map(String.init) ?? "–")
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.subheadline).foregroundStyle(Theme.secondary)
            Spacer()
            Text(v).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
        }
    }

    private func pill(_ k: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit()).foregroundStyle(.white)
            Text(k).font(.caption2).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 12))
    }

    private func stages(_ s: SleepSession) -> some View {
        let total = max(1, s.inBedMinutes)
        let items: [(SleepStage, Double)] = [(.awake, s.minutesAwake), (.light, s.minutesLight), (.deep, s.minutesDeep), (.rem, s.minutesREM)]
        return Card {
            SectionTitle(title: "Fases")
            StackedBar(parts: items.map { (value: $0.1, color: Theme.stageColor($0.0)) }, height: 12)
            ForEach(0..<items.count, id: \.self) { i in
                let item = items[i]
                HStack {
                    Circle().fill(Theme.stageColor(item.0)).frame(width: 10, height: 10)
                    Text(Theme.stageName(item.0)).font(.subheadline).foregroundStyle(.white)
                    Spacer()
                    Text(Fmt.hm(item.1)).font(.subheadline.monospacedDigit()).foregroundStyle(.white)
                    Text("\(Int((item.1 / total * 100).rounded()))%").font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.secondary).frame(width: 40, alignment: .trailing)
                }
            }
            Text("Sueño reparador (profundo + REM): \(Fmt.hm(s.restorativeMinutes))")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
    }

    private func nightVitals(_ d: DaySummary, _ s: SleepSession) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricTile(title: "VFC (RMSSD)", value: Fmt.int(s.hrv), unit: "ms", detail: s.hrvSDNN.map { "SDNN \(Int($0)) ms" },
                       icon: "waveform.path.ecg", tint: Theme.hrv)
            MetricTile(title: "FC reposo", value: Fmt.int(s.rhr), unit: "lpm", detail: s.minHR.map { "mínima \(Int($0)) lpm" },
                       icon: "heart.fill", tint: Theme.red)
            MetricTile(title: "Respiración", value: Fmt.one(s.respRate), unit: "rpm", icon: "lungs.fill", tint: Theme.hrv)
            MetricTile(title: "SpO₂", value: Fmt.one(s.spo2), unit: "%", icon: "drop.fill", tint: Theme.red)
            MetricTile(title: "Temp. piel", value: Fmt.one(s.skinTemp), unit: "°C",
                       detail: d.skinTempDeviation.map { String(format: "%+.2f °C vs tu media", $0) }, icon: "thermometer.medium", tint: Theme.yellow)
            MetricTile(title: "Latencia", value: Fmt.int(s.latencyMinutes), unit: "min", icon: "hourglass", tint: Theme.sleep)
        }
    }
}

struct StageSegment: Identifiable {
    let id: Int
    let start: Date
    let end: Date
    let stage: SleepStage
}

struct Hypnogram: View {
    let session: SleepSession

    var segments: [StageSegment] {
        var out: [StageSegment] = []
        var i = 0
        while i < session.stages.count {
            let st = session.stages[i]
            var j = i
            while j + 1 < session.stages.count && session.stages[j + 1] == st { j += 1 }
            out.append(StageSegment(id: i,
                                    start: Date(timeIntervalSince1970: TimeInterval(session.start + i * 60)),
                                    end: Date(timeIntervalSince1970: TimeInterval(session.start + (j + 1) * 60)),
                                    stage: st))
            i = j + 1
        }
        return out
    }

    static func levelName(_ d: Double?) -> String {
        guard let d else { return "" }
        return ["Prof.", "Ligero", "REM", "Desp."][min(3, max(0, Int(d)))]
    }

    private func level(_ s: SleepStage) -> Int {
        switch s {
        case .awake: return 3
        case .rem: return 2
        case .light: return 1
        case .deep: return 0
        }
    }

    var body: some View {
        Card {
            SectionTitle(title: "Hipnograma", subtitle: "\(Fmt.time(session.start)) – \(Fmt.time(session.end))")
            Chart(segments) { seg in
                RectangleMark(
                    xStart: .value("Inicio", seg.start),
                    xEnd: .value("Fin", seg.end),
                    yStart: .value("Fase", Double(level(seg.stage)) + 0.1),
                    yEnd: .value("Fase", Double(level(seg.stage)) + 0.9)
                )
                .foregroundStyle(Theme.stageColor(seg.stage))
                .cornerRadius(2)
            }
            .chartYScale(domain: 0...4)
            .chartYAxis {
                AxisMarks(values: [0.5, 1.5, 2.5, 3.5]) { v in
                    AxisValueLabel {
                        Text(Self.levelName(v.as(Double.self)))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 170)
        }
    }
}

struct NightTrend: View {
    let session: SleepSession

    var body: some View {
        let points = session.trend
        if points.contains(where: { $0.hr != nil }) {
            Card {
                SectionTitle(title: "Corazón durante la noche", subtitle: "FC (rojo) y VFC (turquesa) cada 5 min")
                Chart {
                    ForEach(points, id: \.ts) { p in
                        if let hr = p.hr {
                            LineMark(x: .value("Hora", Date(timeIntervalSince1970: TimeInterval(p.ts))), y: .value("FC", hr),
                                     series: .value("Serie", "FC"))
                                .foregroundStyle(Theme.red)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisValueLabel(format: .dateTime.hour()) }
                }
                .frame(height: 110)
                Chart {
                    ForEach(points, id: \.ts) { p in
                        if let v = p.hrv {
                            LineMark(x: .value("Hora", Date(timeIntervalSince1970: TimeInterval(p.ts))), y: .value("VFC", v))
                                .foregroundStyle(Theme.hrv)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisValueLabel(format: .dateTime.hour()) }
                }
                .frame(height: 110)
            }
        }
    }
}

struct SleepEditSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: SleepSession?
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
                } else if let d = DayKey.date(model.selectedDay) {
                    start = d.addingTimeInterval(-60 * 60)
                    end = d.addingTimeInterval(7 * 3600)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
