import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntegrations

struct LiveView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmStop = false
    @State private var resp: Double?
    @State private var stress: Double?
    @State private var lastSlow = Date.distantPast

    static var sports: [String] { SportCatalog.names }

    @State private var startingWorkout = false
    @AppStorage(AppModel.stressAlertKey) private var stressAlertOn = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    LiveRunBanner()
                    if model.liveWorkout != nil {
                        // Only while an activity runs: the live line, the minis and the workout itself.
                        LiveHeroMonitor()
                        liveStats
                        workoutCard
                    } else {
                        // Your state now, then what to do with it.
                        LiveHeroMonitor()
                        liveStats
                        suggestion
                        group("Actívate", "Sube el pulso y la energía", [.alert])
                        group("Cálmate", "Baja el pulso y el estrés en minutos", [.sigh, .coherence, .box])
                        group("Duerme", "Suelta el día antes de dormir", [.sleep])
                        recover
                        measure
                        alertToggle
                    }
                    LiveHRHistoryCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(PulsoBackground())
            .pulsoTitle("Live")
            .onAppear { model.setLive(true) }
            .onDisappear { if model.liveWorkout == nil { model.setLive(false) } }
            .onChange(of: model.liveHR) { _, _ in refreshSlow() }
            .sheet(isPresented: $startingWorkout) {
                StartActivitySheet(isPresented: $startingWorkout)
                    .presentationDetents([.medium, .large])
                    .preferredColorScheme(.dark)
            }
        }
    }

    /// The live minis under the monitor: HRV of the last minute, breathing, stress and the day's strain so far.
    private var liveStats: some View {
        HStack(spacing: 0) {
            miniStat("VFC 60 s", Fmt.int(model.liveRMSSD), "ms", Theme.hrv)
            miniStat("Respiración", Fmt.dec(resp), "rpm", Theme.link)
            miniStat("Estrés", stress.map { Fmt.dec($0) } ?? "–", "/3", Theme.stress)
            miniStat("Esfuerzo hoy", Fmt.one(model.liveDayStrain), "", Theme.strain)
        }
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    /// One suggestion from how you are right now and the time of day.
    private var suggestion: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let (kind, why): (Breathwork.Kind, String) = {
            if let s = stress, s >= 1.8 { return (.sigh, "Estás activado (estrés \(Fmt.dec(s))). Dos minutos de suspiro fisiológico te bajan el pulso.") }
            if hour >= 21 || hour < 4 { return (.sleep, "Es hora de ir bajando revoluciones: 4-7-8 en la cama, guiado por la pulsera.") }
            if hour < 12 { return (.alert, "Empieza el día despierto: tres rondas y llegas con energía.") }
            return (.coherence, "Un rato de coherencia para recargar a media jornada.")
        }()
        let info = BreathworkInfo.of(kind)
        return NavigationLink { BreathworkDetailView(kind: kind) } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title3).foregroundStyle(info.color)
                VStack(alignment: .leading, spacing: 3) {
                    Caps("Para ti ahora · \(info.title)", size: 10.5, color: info.color)
                    Text(why).font(.subheadline).foregroundStyle(.white).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.tertiary)
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(info.color.opacity(0.6), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }

    private func group(_ title: String, _ subtitle: String, _ kinds: [Breathwork.Kind]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Caps(title, size: 13)
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.top, 8)
            ForEach(kinds, id: \.self) { BreathworkCard(kind: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sauna and cold, timed live: pulse, peak and how fast it comes back; saved as recovery activities.
    private var recover: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Caps("Recupera", size: 13)
                Text("Sauna y frío con tu pulso en directo").font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.top, 8)
            HStack(spacing: 10) {
                recoverButton("Sauna", "flame.fill", Theme.stressHigh)
                recoverButton("Baño de hielo", "snowflake", Theme.link)
            }
            if !model.strapState.isConnected {
                Text("Conecta la pulsera para medirlo en directo.").font(.caption).foregroundStyle(Theme.yellow)
            }
        }
    }

    private func recoverButton(_ sport: String, _ icon: String, _ color: Color) -> some View {
        Button { model.startWorkout(sport: sport, plan: nil) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.title2).foregroundStyle(color)
                Caps(sport, size: 12)
                Text("Temporizador, pulso pico y vuelta a la calma").font(.caption2).foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(LinearGradient(colors: [color.opacity(0.16), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!model.strapState.isConnected)
    }

    /// The tests, as a grid.
    private var measure: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Caps("Mídete", size: 13)
                Text("Pruebas de un minuto a unos pocos, con su historial").font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                test("Chequeo de 60 s", "dot.radiowaves.left.and.right", .white, "VFC, respiración y estrés") { ScanView() }
                test("Ortostático", "figure.stand", Theme.yellow, "Tumbado y de pie") { OrthostaticTestView() }
                test("Recuperación FC", "arrow.down.heart", Theme.green, "Cuánto baja en 1 min") { RecoveryTestView() }
                test("FC máxima", "bolt.heart", Theme.red, "Tu techo real") { MaxHRTestView() }
                test("Poincaré", "circle.grid.cross", Theme.sleep, "Tu VFC dibujada") { PoincareView() }
                test("Monitor", "waveform.path.ecg.rectangle", Theme.link, "Todo en directo") { MonitorView() }
            }
        }
    }

    private func test<D: View>(_ title: String, _ icon: String, _ color: Color, _ sub: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(color)
                Caps(title, size: 11)
                Text(sub).font(.caption2).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var alertToggle: some View {
        PCard {
            Toggle(isOn: $stressAlertOn) {
                VStack(alignment: .leading, spacing: 3) {
                    Caps("Alerta de estrés", size: 12)
                    Text("Si llevas 5 minutos quieto con el estrés alto, la pulsera vibra y te propone dos minutos de respiración. Como mucho una vez por hora.")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            .tint(Theme.green)
        }
        .padding(.top, 8)
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

/// «Registrar actividad»: start one now (live chart, zones, strain) or add one you already did.
struct StartActivitySheet: View {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool
    @State private var sport = "Carrera"
    @State private var planID = ""
    @State private var addingManual = false

    var body: some View {
        NavigationStack {
            ScrollView { card.padding(16) }
                .background(PulsoBackground())
                .pulsoTitle("Registrar actividad")
                .onChange(of: model.liveWorkout != nil) { _, started in if started { isPresented = false } }
        }
    }

    private var card: some View {
        Card {
            SectionTitle(title: "Empezar ahora", subtitle: "Pulso, zonas, esfuerzo y calorías en directo")
            Picker("Deporte", selection: $sport) {
                ForEach(LiveView.sports, id: \.self) { Text($0) }
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
            if !model.strapState.isConnected {
                Text("Conecta la pulsera para registrarla en directo.").font(.caption).foregroundStyle(Theme.yellow)
            }
            Button { addingManual = true } label: {
                Label("¿Ya la hiciste? Añádela a mano", systemImage: "clock.arrow.circlepath").font(.subheadline)
            }
            .foregroundStyle(Theme.link)
            .sheet(isPresented: $addingManual, onDismiss: { isPresented = false }) { AddActivitySheet() }
        }
    }

}

/// The sheet on its own, for the screenshot run.
struct StartActivityPreview: View {
    @State private var open = true
    var body: some View { StartActivitySheet(isPresented: $open) }
}

/// En vivo without an activity: one big «+» to start one. The live chart appears only once it runs.
struct StartActivityCard: View {
    @EnvironmentObject var model: AppModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 60, height: 60)
                    .background(Color.white, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Caps("Registrar actividad", size: 14)
                    Text(model.liveHR.map { "Ahora \($0) lpm · verás tu pulso, zonas y esfuerzo en directo" }
                         ?? (model.strapState.isConnected ? "Verás tu pulso, zonas y esfuerzo en directo" : "Conecta la pulsera para empezar"))
                        .font(.caption).foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
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
