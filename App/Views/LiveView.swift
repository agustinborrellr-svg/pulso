import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntegrations

/// The old «Live» tab is now the Actividad root (`ActivityRootView`); the name stays for its helpers.
struct LiveView: View {
    static var sports: [String] { SportCatalog.names }

    var body: some View { ActivityRootView() }

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
                        Label("\(Fmt.dec(d / 1000, 2)) km", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
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

/// The session's pulse as a single white line on a soft fill; the target zone, when set, as a faint band.
/// Live points are kept for the last 10 minutes, so a longer session shows its latest stretch.
struct SessionPulseChart: View {
    let points: [LivePoint]
    let target: ClosedRange<Double>?

    var body: some View {
        // Median of each reading and its neighbours: a single dropped reading doesn't draw a spike to the floor.
        let values = points.indices.map { i -> Double in
            let w = points[max(0, i - 1)...min(points.count - 1, i + 1)].map { Double($0.hr) }.sorted()
            return w[w.count / 2]
        }
        let lo = min(values.min() ?? 60, target?.lowerBound ?? .infinity) - 5
        let hi = max(values.max() ?? 120, target?.upperBound ?? 0) + 5
        let trimmed = points.first.map { Date().timeIntervalSince($0.date) > 590 } == true
        VStack(alignment: .leading, spacing: 6) {
            Caps(trimmed ? "Pulso · últimos 10 min" : "Pulso de la sesión", size: 10, color: Theme.secondary, weight: .semibold)
            if points.count >= 2 {
                Chart {
                    if let t = target, let a = points.first?.date, let b = points.last?.date {
                        RectangleMark(xStart: .value("Inicio", a), xEnd: .value("Fin", b),
                                      yStart: .value("Zona", t.lowerBound), yEnd: .value("Zona", t.upperBound))
                            .foregroundStyle(Color.white.opacity(0.08))
                    }
                    ForEach(points.indices, id: \.self) { i in
                        let p = points[i]
                        AreaMark(x: .value("Hora", p.date), yStart: .value("Base", lo), yEnd: .value("Pulso", values[i]))
                            .foregroundStyle(LinearGradient(colors: [Color.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Hora", p.date), y: .value("Pulso", values[i]))
                            .foregroundStyle(.white)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary) }
                    }
                }
            } else {
                Text("Esperando latidos…").font(.caption).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
