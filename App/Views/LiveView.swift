import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntegrations

struct LiveView: View {
    @EnvironmentObject var model: AppModel
    @State private var sport = "Carrera"
    @State private var planID = ""
    @State private var confirmStop = false

    static var sports: [String] { SportCatalog.names }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heartCard
                    if model.liveWorkout != nil { workoutCard } else { startCard }
                    breathingCard
                    Button {
                        model.buzz()
                    } label: {
                        Label("Hacer vibrar la pulsera", systemImage: "iphone.radiowaves.left.and.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.strapState.isConnected)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(PulsoBackground())
            .pulsoTitle("En vivo")
            .onAppear { model.setLive(true) }
            .onDisappear { if model.liveWorkout == nil { model.setLive(false) } }
        }
    }

    private var zone: Int {
        guard let hr = model.liveHR else { return 0 }
        return model.heartRateModel.zone(Double(hr))
    }

    private var heartCard: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.zoneColor(zone))
                    .symbolEffect(.pulse, isActive: model.liveHR != nil)
                Text(model.liveHR.map(String.init) ?? "--")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("lpm").foregroundStyle(Theme.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(zone == 0 ? "Reposo" : "Zona \(zone)").font(.headline).foregroundStyle(Theme.zoneColor(zone))
                    if let hr = model.liveHR {
                        let pct = Double(hr) / model.heartRateModel.maxHR * 100
                        Text("\(Int(pct))% FC máx").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }
            if model.livePoints.count > 2 {
                Chart(model.livePoints) { p in
                    LineMark(x: .value("t", p.date), y: .value("FC", p.hr))
                        .foregroundStyle(Theme.red)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .frame(height: 120)
            } else {
                Text(model.strapState.isConnected ? "Esperando latidos… (ponte bien la pulsera)" : "Conecta la pulsera para ver tu pulso en directo.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            HStack {
                Label("VFC en vivo \(Fmt.int(model.liveRMSSD)) ms", systemImage: "waveform.path.ecg")
                Spacer()
                Label("FC máx \(Int(model.heartRateModel.maxHR))", systemImage: "arrow.up.heart")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondary)
        }
    }

    private var startCard: some View {
        Card {
            SectionTitle(title: "Registrar entreno", subtitle: "Esfuerzo y calorías en tiempo real")
            Picker("Deporte", selection: $sport) {
                ForEach(Self.sports, id: \.self) { Text($0) }
            }
            .pickerStyle(.menu)
            .tint(.white)
            Picker("Plan", selection: $planID) {
                Text("Libre").tag("")
                ForEach(IntervalPlan.presets) { p in Text(p.name).tag(p.id) }
            }
            .pickerStyle(.menu)
            .tint(.white)
            if let plan = IntervalPlan.presets.first(where: { $0.id == planID }) {
                Text("\(plan.detail) · \(plan.totalSeconds / 60) min. La pulsera vibra en cada cambio y si te sales de la zona\(model.settings.voiceCues ? ", y una voz te guía" : "").")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
            Button {
                model.startWorkout(sport: sport, plan: IntervalPlan.presets.first { $0.id == planID })
            } label: {
                Label("Empezar", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.green)
            .disabled(!model.strapState.isConnected)
        }
    }

    private var workoutCard: some View {
        Card {
            if let w = model.liveWorkout {
                HStack {
                    SectionTitle(title: w.sport)
                    Spacer()
                    TimelineView(.periodic(from: w.start, by: 1)) { ctx in
                        Text(Self.duration(ctx.date.timeIntervalSince(w.start)))
                            .font(.title3.monospacedDigit().bold())
                            .foregroundStyle(.white)
                    }
                }
                if let st = model.intervalStatus {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(st.step).font(.headline).foregroundStyle(Theme.yellow)
                            Spacer()
                            Text(Self.duration(TimeInterval(st.remaining))).font(.title2.bold().monospacedDigit()).foregroundStyle(.white)
                        }
                        if let next = st.next {
                            Text("Después: \(next)").font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(12)
                    .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    liveStat("Esfuerzo", Fmt.one(Strain.score(load: w.load)), Theme.strain)
                    liveStat("kcal", Fmt.int(w.kcal), Theme.stress)
                    liveStat("FC media", w.hrCount > 0 ? "\(Int(w.hrSum / Double(w.hrCount)))" : "–", Theme.red)
                    liveStat("FC máx", w.maxHR > 0 ? "\(w.maxHR)" : "–", Theme.red)
                }
                if !w.laps.isEmpty {
                    Text("\(w.laps.count) vuelta\(w.laps.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Theme.secondary)
                }
                Button {
                    model.markLap()
                } label: {
                    Label("Vuelta", systemImage: "flag.checkered").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    confirmStop = true
                } label: {
                    Label("Terminar", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.red)
                .confirmationDialog("¿Terminar entreno?", isPresented: $confirmStop) {
                    Button("Guardar") { model.stopWorkout(save: true) }
                    Button("Descartar", role: .destructive) { model.stopWorkout(save: false) }
                }
            }
        }
    }

    private func liveStat(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.bold().monospacedDigit()).foregroundStyle(c)
            Text(k).font(.caption2).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    static func duration(_ s: TimeInterval) -> String {
        let t = Int(s)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) : String(format: "%02d:%02d", t / 60, t % 60)
    }

    private var breathingCard: some View {
        NavigationLink {
            BreathingView()
        } label: {
            HStack {
                Image(systemName: "wind").font(.title2).foregroundStyle(Theme.hrv)
                VStack(alignment: .leading) {
                    Text("Respiración guiada").font(.headline).foregroundStyle(.white)
                    Text("6 respiraciones/min con biofeedback de VFC").font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

/// Resonance-frequency breathing (≈ 6/min) with live HRV feedback from the strap.
struct BreathingView: View {
    @EnvironmentObject var model: AppModel
    @State private var start = Date()
    @State private var startRMSSD: Double?

    var body: some View {
        VStack(spacing: 24) {
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                let phase = t.truncatingRemainder(dividingBy: 10) // 4 s in, 6 s out
                let inhale = phase < 4
                let scale = inhale ? 0.55 + 0.45 * (phase / 4) : 1.0 - 0.45 * ((phase - 4) / 6)
                VStack(spacing: 20) {
                    ZStack {
                        Circle().fill(Theme.hrv.opacity(0.15)).frame(width: 260, height: 260)
                        Circle().fill(Theme.hrv.opacity(0.6)).frame(width: 260 * scale, height: 260 * scale)
                    }
                    Text(inhale ? "Inspira" : "Espira").font(.title.bold()).foregroundStyle(.white)
                    Text(LiveView.duration(t)).font(.headline.monospacedDigit()).foregroundStyle(Theme.secondary)
                }
            }
            HStack {
                VStack {
                    Text(Fmt.int(startRMSSD)).font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.secondary)
                    Text("VFC inicial").font(.caption).foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity)
                VStack {
                    Text(Fmt.int(model.liveRMSSD)).font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.hrv)
                    Text("VFC ahora (ms)").font(.caption).foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity)
                VStack {
                    Text(model.liveHR.map(String.init) ?? "–").font(.title2.bold().monospacedDigit()).foregroundStyle(Theme.red)
                    Text("FC").font(.caption).foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
            Spacer()
        }
        .padding()
        .background(PulsoBackground())
        .pulsoTitle("Respiración")
        .onDisappear { model.setLive(false, client: "breathing-view") }
        .onAppear {
            start = Date()
            model.setLive(true, client: "breathing-view")
            Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                startRMSSD = model.liveRMSSD
            }
        }
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var points: [LivePoint] = []
    @State private var confirmDelete = false

    static func icon(_ sport: String) -> String {
        SportCatalog.named(sport).symbol
    }

    @State private var files: [URL] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    HStack {
                        Image(systemName: Self.icon(workout.sport)).font(.largeTitle).foregroundStyle(Theme.strain)
                        VStack(alignment: .leading) {
                            Picker("Deporte", selection: $workout.sport) {
                                ForEach(LiveView.sports, id: \.self) { Text($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(.white)
                            Text("\(Fmt.time(workout.start)) – \(Fmt.time(workout.end))").font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Text(Fmt.one(workout.strain)).font(.largeTitle.bold().monospacedDigit()).foregroundStyle(Theme.strain)
                    }
                    HStack {
                        stat("Duración", Fmt.hm(workout.durationMinutes))
                        stat("kcal", Fmt.int(workout.kcal))
                        stat("FC media", Fmt.int(workout.avgHR))
                        stat("FC máx", Fmt.int(workout.maxHR))
                    }
                }
                if points.count > 2 {
                    Card {
                        SectionTitle(title: "Frecuencia cardiaca")
                        Chart(points) { p in
                            LineMark(x: .value("t", p.date), y: .value("FC", p.hr))
                                .foregroundStyle(Theme.red)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 160)
                    }
                }
                Card {
                    SectionTitle(title: "Zonas")
                    StackedBar(parts: workout.zoneMinutes.enumerated().map { (value: $0.element, color: Theme.zoneColor($0.offset + 1)) })
                    ForEach(0..<min(5, workout.zoneMinutes.count), id: \.self) { i in
                        HStack {
                            Text("Zona \(i + 1)").foregroundStyle(Theme.zoneColor(i + 1))
                            Spacer()
                            Text(Fmt.hm(workout.zoneMinutes[i])).foregroundStyle(.white)
                        }
                        .font(.subheadline)
                    }
                }
                WorkoutCardiacCard(workout: workout)
                Card {
                    SectionTitle(title: "Compartir")
                    if let app = workout.externalApp {
                        Label("Registrado con \(app)", systemImage: "app.connected.to.app.below.fill").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    if let d = workout.distanceMeters {
                        Label(String(format: "%.2f km", d / 1000), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.caption).foregroundStyle(Theme.secondary)
                    }
                    if workout.externalID("strava") != nil {
                        Label("En Strava", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Theme.green)
                    } else if workout.source != .strava {
                        Button {
                            model.uploadToStrava(workout)
                        } label: {
                            Label("Subir a Strava", systemImage: "arrow.up.circle")
                        }
                        .disabled(!model.strava.connected)
                    }
                    if workout.externalID("health") != nil {
                        Label("En Apple Salud", systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Theme.green)
                    } else if workout.source != .health && model.profile.healthKitEnabled {
                        Button {
                            model.saveWorkoutToHealth(workout)
                        } label: {
                            Label("Guardar en Apple Salud", systemImage: "heart.text.square")
                        }
                    }
                    Button {
                        files = model.exportWorkoutFiles(workout)
                    } label: {
                        Label("Exportar FIT / TCX", systemImage: "doc.badge.arrow.up")
                    }
                    if !files.isEmpty {
                        ShareLink(items: files) {
                            Label("Compartir \(files.count) archivos", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let status = model.importStatus {
                        Text(status).font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                Button("Eliminar entreno", role: .destructive) { confirmDelete = true }
                    .confirmationDialog("¿Eliminar este entreno?", isPresented: $confirmDelete) {
                        Button("Eliminar", role: .destructive) {
                            model.deleteWorkout(workout)
                            dismiss()
                        }
                    }
            }
            .padding(16)
        }
        .background(PulsoBackground())
        .pulsoTitle("Entreno")
        .onAppear {
            let s = model.samples(from: Date(timeIntervalSince1970: TimeInterval(workout.start)),
                                  to: Date(timeIntervalSince1970: TimeInterval(workout.end)))
            var out: [LivePoint] = []
            var i = 0
            while i < s.count {
                let chunk = s[i..<min(s.count, i + 15)].compactMap { $0.hr }
                if !chunk.isEmpty {
                    out.append(LivePoint(date: Date(timeIntervalSince1970: TimeInterval(s[i].ts)), hr: chunk.reduce(0, +) / chunk.count))
                }
                i += 15
            }
            points = out
        }
        .onChange(of: workout.sport) { _, _ in
            var w = workout
            if w.source == .auto { w.source = .manual }
            model.saveWorkout(w)
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit()).foregroundStyle(.white)
            Text(k).font(.caption2).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
