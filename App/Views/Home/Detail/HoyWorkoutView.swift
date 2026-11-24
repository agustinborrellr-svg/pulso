import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoIntegrations
import PulsoIntelligence

/// 13 Detalle de entreno: its strain, duration, calories, distance / pace when Apple Salud (or the app that recorded it)
/// gave them, the pulse with the zone bands, zones, the heart-rate recovery, sharing and delete. No map: the band
/// records no GPS.
struct HoyWorkoutView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var points: [DSPoint] = []
    @State private var analysis: WorkoutAnalysis.Result?
    @State private var files: [URL] = []
    @State private var confirmDelete = false
    @State private var selection: Date?

    var body: some View {
        let w = workout
        DSScreen(w.sport, subtitle: "\(DSFmt.shortDate(DayKey.string(ts: w.start))) · \(Fmt.time(w.start))–\(Fmt.time(w.end))", back: "Hoy") {
            hero(w)
            if points.count > 2 {
                DSSectionHeader("Pulso")
                pulse(w)
            }
            if w.zoneMinutes.reduce(0, +) > 0 {
                DSSectionHeader("Zonas de pulso")
                HoyZonesCard(minutes: w.zoneMinutes)
            }
            if let rec = analysis?.recovery, rec.curve.count >= 4 {
                DSSectionHeader("Recuperación del pulso")
                recovery(rec)
            }
            DSSectionHeader("Compartir")
            share(w)
            Button { confirmDelete = true } label: {
                Text("Eliminar entreno").dsFont(17, .semibold).foregroundStyle(DSLevel.baja.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .confirmationDialog("¿Eliminar este entreno?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    model.deleteWorkout(workout)
                    dismiss()
                }
            }
        }
        .task(id: workout.start) { load() }
        .onChange(of: workout.sport) { _, _ in
            var x = workout
            if x.source == .auto { x.source = .manual }
            model.saveWorkout(x)
        }
    }

    private func load() {
        let w = workout
        let s = model.samples(from: Date(timeIntervalSince1970: TimeInterval(w.start)), to: Date(timeIntervalSince1970: TimeInterval(w.end)))
        var out: [DSPoint] = []
        var i = 0
        while i < s.count {
            let chunk = s[i..<min(s.count, i + 15)].compactMap { $0.hr }
            if !chunk.isEmpty {
                out.append(DSPoint(date: Date(timeIntervalSince1970: TimeInterval(s[i].ts)), value: Double(chunk.reduce(0, +)) / Double(chunk.count)))
            }
            i += 15
        }
        points = out
        analysis = model.workoutHasHeartData(w) ? model.workoutAnalysis(w) : nil
    }

    private var sourceText: String? {
        switch workout.source {
        case .auto: return "Detectada sola"
        case .manual: return "Añadida a mano"
        default:
            if let app = workout.externalApp { return "Importada de \(app)" }
            return workout.source.isExternal ? "Importada" : nil
        }
    }

    private func hero(_ w: Workout) -> some View {
        var side: [(String, String)] = [("Duración", DSFmt.duration(w.durationMinutes))]
        if w.kcal > 0 { side.append(("Calorías", "\(DSFmt.thousands(w.kcal)) kcal")) }
        var stats: [DSStat] = []
        var paceNote: String?
        if let m = w.distanceMeters, m > 50 {
            stats.append(DSStat(label: "Distancia", value: Fmt.dec(m / 1000), unit: "km"))
            let pace = w.durationMinutes / (m / 1000)
            if pace.isFinite, pace < 20 {
                stats.append(DSStat(label: "Ritmo", value: String(format: "%d:%02d", Int(pace), Int((pace - floor(pace)) * 60)), unit: "/km"))
            }
            paceNote = "Distancia y ritmo de \(w.externalApp ?? "Apple Salud")"
        }
        if w.avgHR > 0 { stats.append(DSStat(label: "FC media", value: "\(Int(w.avgHR.rounded()))", unit: "lpm")) }
        if stats.count < 3, w.maxHR > 0 { stats.append(DSStat(label: "FC máxima", value: "\(Int(w.maxHR.rounded()))", unit: "lpm")) }
        return HoyHero(value: Fmt.dec(w.strain), side: side) {
            Text("Esfuerzo").dsFont(16, .semibold).foregroundStyle(DS.t2)
            if let s = sourceText { Text(s).dsFont(14).foregroundStyle(DS.t3) }
        } footer: {
            if !stats.isEmpty {
                DSDivider().padding(.top, 14)
                DSStatStrip(stats: stats).padding(.top, 12)
                if let paceNote {
                    Text(paceNote).dsFont(13).foregroundStyle(DS.t3).padding(.top, 10)
                }
            }
        }
    }

    private func pulse(_ w: Workout) -> some View {
        let hrm = model.heartRateModel
        let floors = (1...5).map { hrm.zoneFloor($0) }
        let vals = points.map(\.value)
        let lo = min(vals.min() ?? 60, floors[0]) - 5, hi = max(vals.max() ?? 150, floors[4]) + 5
        let peak = points.max { $0.value < $1.value }
        let sel = selection.flatMap { s in points.min { abs($0.date.timeIntervalSince(s)) < abs($1.date.timeIntervalSince(s)) } }
        let a = points.first?.date ?? Date(), b = points.last?.date ?? Date()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                if w.avgHR > 0 {
                    HStack(spacing: 6) { Text("---").tracking(-1); Text("FC media") }
                }
                HStack(spacing: 6) { Circle().fill(DS.zone(3)).frame(width: 7, height: 7); Text("Zonas de pulso") }
            }
            .dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2)
            Chart {
                ForEach(0..<5, id: \.self) { z in
                    RectangleMark(xStart: .value("a", a), xEnd: .value("b", b),
                                  yStart: .value("lo", max(floors[z], lo)), yEnd: .value("hi", min(z < 4 ? floors[z + 1] : hi, hi)))
                        .foregroundStyle(DS.zone(z + 1).opacity(0.06 + 0.03 * Double(z)))
                }
                if w.avgHR > 0 {
                    RuleMark(y: .value("Media", w.avgHR)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3])).foregroundStyle(DS.t2.opacity(0.7))
                }
                ForEach(points) { p in
                    LineMark(x: .value("t", p.date), y: .value("FC", p.value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(DS.cor)
                }
                if let p = sel ?? peak {
                    PointMark(x: .value("t", p.date), y: .value("FC", p.value))
                        .symbol { Circle().strokeBorder(DS.cor, lineWidth: 2.5).background(Circle().fill(DS.card)).frame(width: 13, height: 13) }
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Text(sel == nil ? "Máx · \(Int(p.value.rounded())) lpm" : "\(Fmt.time(Int(p.date.timeIntervalSince1970))) · \(Int(p.value.rounded())) lpm")
                                .dsFont(14, .semibold).foregroundStyle(DS.bg)
                                .padding(.horizontal, 12).frame(height: 28).background(DS.t1, in: Capsule())
                        }
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: floors.map { $0 + 1 }) { v in
                    AxisValueLabel {
                        let z = (floors.firstIndex { abs($0 + 1 - (v.as(Double.self) ?? 0)) < 0.5 } ?? 0) + 1
                        Text("Z\(z)").dsFont(11, .semibold).foregroundStyle(DS.zone(z))
                    }
                }
            }
            .chartScrub($selection)
            .padding(.top, 24)
            .frame(height: 190)
            HStack {
                Text(Fmt.time(w.start))
                Spacer()
                Text(Fmt.time((w.start + w.end) / 2))
                Spacer()
                Text(Fmt.time(w.end))
            }
            .dsFont(12, .medium, relativeTo: .caption1).foregroundStyle(DS.t3)
            .padding(.trailing, 30)
        }
        .dsCard(padding: 14)
    }

    private func recovery(_ rec: WorkoutAnalysis.Recovery) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(rec.curve, id: \.t) { p in
                    LineMark(x: .value("s", p.t), y: .value("lpm", p.hr))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(DS.cor)
                }
                RuleMark(x: .value("s", 60)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3])).foregroundStyle(DS.t3)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [0, 60, 120, 180]) { v in
                    AxisValueLabel {
                        let s = v.as(Int.self) ?? 0
                        Text(s == 0 ? "0 s" : "\(s / 60) min").dsFont(12, .medium).foregroundStyle(DS.t3)
                    }
                }
            }
            .frame(height: 100)
            DSDivider()
            DSStatStrip(stats: [
                rec.drop60.map { DSStat(label: "Bajada en 1 min", value: "\(Int($0.rounded()))", unit: "lpm") },
                rec.tau.map { DSStat(label: "Constante τ", value: "\(Int($0.rounded()))", unit: "s") },
            ].compactMap { $0 })
            Text("Cuánto baja tu pulso al terminar: más bajada, mejor recuperación.").dsFont(13).foregroundStyle(DS.t3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dsCard(padding: 14)
    }

    private func share(_ w: Workout) -> some View {
        DSGroup {
            Menu {
                Picker("Deporte", selection: $workout.sport) {
                    ForEach(SportCatalog.names, id: \.self) { Text($0) }
                }
            } label: {
                DSRow(icon: "arrow.left.arrow.right", label: "Deporte", value: w.sport, chevron: true)
            }
            .buttonStyle(.plain)
            if w.externalID("strava") != nil {
                DSRow(icon: "square.and.arrow.up", label: "Strava", value: "Subido")
            } else if w.source != .strava, model.strava.connected {
                Button { model.uploadToStrava(w) } label: {
                    DSRow(icon: "square.and.arrow.up", label: "Subir a Strava", chevron: true)
                }
                .buttonStyle(.plain)
            }
            if w.externalID("health") != nil {
                DSRow(icon: "heart.fill", iconColor: DS.cor, label: "Apple Salud") {
                    Text("Guardado").dsFont(15, .semibold).foregroundStyle(DSLevel.buena.ink)
                }
            } else if w.source != .health, model.profile.healthKitEnabled {
                Button { model.saveWorkoutToHealth(w) } label: {
                    DSRow(icon: "heart.fill", iconColor: DS.cor, label: "Guardar en Apple Salud", chevron: true)
                }
                .buttonStyle(.plain)
            }
            if files.isEmpty {
                Button { files = model.exportWorkoutFiles(w) } label: {
                    DSRow(icon: "doc.text", label: "Exportar FIT / TCX", chevron: true)
                }
                .buttonStyle(.plain)
            } else {
                ShareLink(items: files) {
                    DSRow(icon: "doc.text", label: "Compartir \(files.count) archivos", chevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
