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
    @State private var resp: Double?
    @State private var stress: Double?
    @State private var lastSlow = Date.distantPast

    static var sports: [String] { SportCatalog.names }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LiveRunBanner()
                    NavigationLink {
                        MonitorView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg.rectangle").font(.title2).foregroundStyle(Theme.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Monitor fisiológico").font(.headline).foregroundStyle(.white)
                                Text("Pulso, VFC, respiración, temperatura y más, con cuándo se midió").font(.caption).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.secondary)
                        }
                        .padding(16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    heartCard
                    NavigationLink {
                        ScanView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dot.radiowaves.left.and.right").font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Escanear").font(.headline)
                                Text("60 s quieto: pulso, VFC, respiración y estrés frente a tu normal").font(.caption).opacity(0.8)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(.black)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if model.liveWorkout != nil { workoutCard } else { startCard }
                    toolsGrid
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
            .onChange(of: model.liveHR) { _, _ in refreshSlow() }
        }
    }

    /// Breathing rate and stress need ~1 minute of beats and a spectrum: every 10 s is plenty.
    private func refreshSlow() {
        guard Date().timeIntervalSince(lastSlow) >= 10 else { return }
        lastSlow = Date()
        let recent = model.beats(since: Date().addingTimeInterval(-90))
        let scan = LiveMetrics.scan(recent, baseline: model.liveBaseline)
        resp = scan?.respRate
        stress = scan?.stress
    }

    private var zone: Int {
        guard let hr = model.liveHR else { return 0 }
        return model.heartRateModel.zone(Double(hr))
    }

    private var heartCard: some View {
        Card {
            // Re-evaluated every second so a reading that stops arriving stops the heart and says how old it is.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let age = model.lastLiveAt.map { ctx.date.timeIntervalSince($0) } ?? .infinity
            let fresh = model.liveHR != nil && age < 6
            HStack(alignment: .center, spacing: 14) {
                BeatingHeart(bpm: fresh ? model.liveHR : nil, color: fresh ? Theme.zoneColor(zone) : Theme.secondary)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(model.liveHR.map(String.init) ?? "--")
                            .scaledFont(64, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3)
                            .monospacedDigit()
                            .foregroundStyle(fresh ? .white : Theme.secondary)
                            .contentTransition(.numericText())
                        Text("lpm").foregroundStyle(Theme.secondary)
                    }
                    if model.liveHR != nil && !fresh && age.isFinite {
                        Text("Sin señal: última lectura hace \(Int(age)) s").font(.caption).foregroundStyle(Theme.yellow)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(zone == 0 ? "Reposo" : "Zona \(zone)").font(.headline).foregroundStyle(Theme.zoneColor(zone))
                    if let hr = model.liveHR {
                        Text("\(Int(Double(hr) / model.heartRateModel.maxHR * 100)) % FC máx").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
            }
            }
            if model.livePoints.count > 2 {
                let cut = Date().addingTimeInterval(-120)
                Chart(model.livePoints.filter { $0.date >= cut }) { p in
                    AreaMark(x: .value("t", p.date), yStart: .value("base", 40), yEnd: .value("FC", p.hr))
                        .foregroundStyle(LinearGradient(colors: [Theme.red.opacity(0.35), Theme.red.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("t", p.date), y: .value("FC", p.hr))
                        .foregroundStyle(Theme.red)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXScale(domain: cut...Date())
                .chartXAxis(.hidden)
                .frame(height: 110)
                .animation(.linear(duration: 1), value: model.livePoints.count)
            } else {
                Text(model.strapState.isConnected ? "Esperando latidos… (ponte bien la pulsera)" : "Conecta la pulsera para ver tu pulso en directo.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            let beats = Array(model.liveBeats.suffix(60))
            if beats.count > 10 {
                VStack(alignment: .leading, spacing: 4) {
                    Caps("Tacograma · cada latido", size: 10, color: Theme.secondary, weight: .semibold)
                    Chart(Array(beats.enumerated()), id: \.offset) { i, b in
                        LineMark(x: .value("latido", i), y: .value("R-R", b.rr))
                            .foregroundStyle(Theme.hrv)
                            .interpolationMethod(.stepCenter)
                        PointMark(x: .value("latido", i), y: .value("R-R", b.rr))
                            .symbolSize(10)
                            .foregroundStyle(Theme.hrv)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.tertiary) }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 70)
                }
            }
            HStack(spacing: 0) {
                miniStat("VFC 60 s", Fmt.int(model.liveRMSSD), "ms", Theme.hrv)
                miniStat("Respiración", Fmt.dec(resp), "rpm", Theme.link)
                miniStat("Estrés", stress.map { String(format: "%.1f", $0) } ?? "–", "/3", Theme.stress)
                miniStat("Esfuerzo hoy", Fmt.one(model.liveDayStrain), "", Theme.strain)
            }
        }
    }

    private func miniStat(_ k: String, _ v: String, _ unit: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(v).font(.headline.monospacedDigit()).foregroundStyle(c)
                Text(unit).scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.tertiary)
            }
            Text(k).scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var toolsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(text: "Herramientas")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tool("Respiración", "Guiada, con coherencia en directo", "wind", Theme.hrv) { BreathingView() }
                tool("Poincaré", "Tu variabilidad, latido a latido", "circle.grid.cross", Theme.sleep) { PoincareView() }
                tool("Test ortostático", "Tumbado → de pie, 5 min", "figure.stand", Theme.yellow) { OrthostaticTestView() }
                tool("Recuperación FC", "Cuánto baja en 1–2 min", "arrow.down.heart", Theme.green) { RecoveryTestView() }
                tool("FC máxima", "Test de esfuerzo máximo", "bolt.heart", Theme.red) { MaxHRTestView() }
            }
        }
    }

    private func tool<D: View>(_ title: String, _ sub: String, _ icon: String, _ c: Color, @ViewBuilder dest: @escaping () -> D) -> some View {
        NavigationLink {
            dest()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(c)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(sub).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
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
                let m = model.heartRateModel
                ZoneBandsChart(model: m, points: model.livePoints.filter { $0.date >= w.start.addingTimeInterval(-5) }, target: w.targetZone)
                    .frame(height: 150)
                Picker("Zona objetivo", selection: Binding(get: { w.targetZone ?? 0 }, set: { model.setTargetZone($0 == 0 ? nil : $0) })) {
                    Text("Sin zona objetivo").tag(0)
                    ForEach(1...5, id: \.self) { z in
                        Text("Mantener zona \(z) · \(Int(m.zoneFloor(z)))–\(Int(z >= 5 ? m.maxHR : m.zoneFloor(z + 1))) lpm").tag(z)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                if w.targetZone != nil {
                    Text("Si te sales más de 10 s, la pulsera vibra: 3 toques = baja el ritmo, 1 toque = súbelo.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                if !w.lapStats.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(w.lapStats.enumerated()), id: \.offset) { i, lap in
                            HStack {
                                Text("Vuelta \(i + 1)").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                Spacer()
                                Text(Self.duration(lap.duration)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondary)
                                Text("media \(Fmt.int(lap.avgHR))").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.red)
                                Text("máx \(Fmt.int(lap.maxHR))").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 10))
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
