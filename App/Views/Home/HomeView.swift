import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntelligence

/// Inicio: the three pillars, the week, the stress monitor and a dashboard you arrange yourself.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var customizing = false
    @State private var showCoach = false
    @AppStorage(HomeLayout.key) private var homeRaw = ""
    @State private var collapse: CGFloat = 0

    private var widgets: [HomeWidget] { HomeLayout.decode(homeRaw) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Room for the header floating above; where this sits drives its collapse.
                    Color.clear
                        .frame(height: HomeDialHeader.expandedHeight - 14)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: HomeScrollOffset.self, value: g.frame(in: .named("home")).minY)
                        })
                    if let day = model.selected {
                        if day.recovery == nil && day.calibrating {
                            Text("Calibrando tus líneas base: la recuperación aparece tras 4 noches.")
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                        if day.nightImported {
                            Label("Sueño y recuperación de la noche importados: la pulsera no estaba conectada a Pulso esa noche.",
                                  systemImage: "square.and.arrow.down")
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                    if !model.days.isEmpty {
                        // Each vital of last night against your range, then the stress level.
                        HomeHealthMonitorCard()
                        HomeStressStatusTile()
                    }
                    if let day = model.selected {
                        TodayActivitiesCard(day: day)
                    }
                    if let q = model.pendingSleepQuestions.first {
                        SleepQuestionCard(session: q)
                    }
                    AlarmBanner()
                    if model.selectedDay == model.currentDayKey, model.nightStatus != .ok {
                        NightPendingCard(status: model.nightStatus)
                    }
                    if model.isEvening && model.selectedDay == model.currentDayKey {
                        BedtimeCard()
                    }
                    if let day = model.selected {
                        ForEach(Array(HomeLayout.lines(widgets.filter { $0.kind != .hero }).enumerated()), id: \.offset) { _, line in
                            HomeWidgetLine(items: line, day: day)
                        }
                        Button { customizing = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                Caps("Personalizar Inicio", size: 11, color: Theme.secondary, weight: .semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondary)
                    } else if model.days.isEmpty {
                        firstRun
                    } else {
                        EmptyState(icon: "calendar.badge.exclamationmark", title: "Sin datos este día",
                                   message: "No hay datos de la pulsera para esta fecha.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .scrollIndicators(.hidden)
            .coordinateSpace(name: "home")
            .onPreferenceChange(HomeScrollOffset.self) { y in
                collapse = min(max(-y / HomeDialHeader.collapseDistance, 0), 1)
            }
            .overlay(alignment: .top) { HomeDialHeader(progress: collapse) }
            .background(PulsoBackground())
            .refreshable {
                model.syncNow()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if let day = model.selected {
                    CoachBanner(day: day) { showCoach = true }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
            }
            .sheet(isPresented: $customizing) {
                HomeEditor(raw: $homeRaw)
            }
            .sheet(isPresented: $showCoach) {
                if let day = model.selected { CoachSheet(day: day) }
            }
        }
    }

    private var firstRun: some View {
        VStack(spacing: 16) {
            EmptyState(icon: "sensor.tag.radiowaves.forward",
                       title: model.strapState.isConnected ? "Recopilando datos" : "Conecta tu pulsera",
                       message: model.strapState.isConnected
                           ? "Tu primera recuperación aparece tras la primera noche. Las líneas base se calibran en 4 noches."
                           : "Toca el icono de la pulsera arriba a la derecha para emparejar tu Pulse Band.")
            if model.rawSampleCount > 0 {
                Button("Analizar datos descargados") { model.recompute(fromDay: nil) }
                    .buttonStyle(PrimaryCapsuleStyle())
            }
        }
    }
}

// MARK: - Top bar

struct HomeTopBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                ProfileEditor(profile: model.profile)
            } label: {
                Image(systemName: "person.crop.circle")
                    .scaledFont(26, weight: .light, relativeTo: .title1)
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Button { model.shiftSelectedDay(-1) } label: {
                    Image(systemName: "chevron.left").font(.subheadline.weight(.bold)).frame(width: 30, height: 34)
                }
                Caps(model.cycleTitle(model.selectedDay), size: 12)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.cardHighlight, in: Capsule())
                Button { model.shiftSelectedDay(1) } label: {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).frame(width: 30, height: 34)
                }
                .disabled(model.selectedDay >= model.currentDayKey)
                .opacity(model.selectedDay >= model.currentDayKey ? 0.3 : 1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            NavigationLink {
                DeviceView()
            } label: {
                HStack(spacing: 5) {
                    Text(model.battery.map { "\(Int($0)) %" } ?? "")
                        .scaledFont(13, weight: .semibold, relativeTo: .caption1)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "applewatch.side.right")
                            .scaledFont(24, weight: .light, relativeTo: .title1)
                            .foregroundStyle(.white)
                        Circle().fill(statusColor).frame(width: 8, height: 8).offset(x: 3, y: -2)
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    private var statusColor: Color {
        switch model.strapState {
        case .ready, .syncing: return Theme.green
        case .connecting, .scanning, .pairing: return Theme.yellow
        default: return Theme.red
        }
    }
}

// MARK: - Strain & recovery week

struct StrainRecoveryWeekCard: View {
    @EnvironmentObject var model: AppModel
    @State private var info = false

    var body: some View {
        let today = model.currentDayKey
        let keys = (0..<7).map { DayKey.shift(today, days: $0 - 6) }
        let byDay = Dictionary(model.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        PCard {
            CardHeader(title: "Esfuerzo y recuperación", info: { info.toggle() })
            if info {
                Text("Azul: tu esfuerzo del día (0–21, escala izquierda). Puntos de color: tu recuperación (0–100 %, escala derecha). Si el esfuerzo va muy por encima de lo que permite tu recuperación varios días, toca descansar.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
            Chart {
                if let last = keys.last {
                    RectangleMark(x: .value("Día", last), yStart: .value("a", 0), yEnd: .value("b", 21), width: .ratio(0.8))
                        .foregroundStyle(Color.white.opacity(0.07))
                        .cornerRadius(4)
                }
                ForEach(keys, id: \.self) { k in
                    if let r = byDay[k]?.recovery {
                        LineMark(x: .value("Día", k), y: .value("Recuperación", r * 0.21), series: .value("s", "rec"))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        PointMark(x: .value("Día", k), y: .value("Recuperación", r * 0.21))
                            .symbol { ring(Theme.recoveryColor(r)) }
                            .annotation(position: .top, spacing: 3) {
                                Text("\(Int(r)) %").scaledFont(11, weight: .bold, relativeTo: .caption1).foregroundStyle(Theme.recoveryColor(r)).fixedSize()
                            }
                    }
                    if let s = byDay[k]?.strain {
                        LineMark(x: .value("Día", k), y: .value("Esfuerzo", s), series: .value("s", "str"))
                            .foregroundStyle(Theme.strain)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Día", k), y: .value("Esfuerzo", s))
                            .symbol { ring(Theme.strain) }
                            .annotation(position: .bottom, spacing: 3) {
                                Text(Fmt.dec(s)).scaledFont(11, weight: .bold, relativeTo: .caption1).foregroundStyle(Theme.strain).fixedSize()
                            }
                    }
                }
            }
            .chartYScale(domain: 0...21)
            .chartXScale(domain: keys)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 7, 14, 21]) { v in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.strain) }
                }
                AxisMarks(position: .trailing, values: [0, 7, 14, 21]) { v in
                    AxisValueLabel {
                        let pct = [0: "0%", 7: "33%", 14: "66%", 21: "100%"][v.as(Int.self) ?? 0] ?? ""
                        Text(pct).scaledFont(11, relativeTo: .caption1).foregroundStyle([0: Theme.red, 7: Theme.red, 14: Theme.yellow, 21: Theme.green][v.as(Int.self) ?? 0] ?? Theme.secondary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: keys) { v in
                    AxisValueLabel(centered: true) {
                        if let k = v.as(String.self) {
                            let (wd, d) = Fmt.weekdayAndDay(k)
                            VStack(spacing: 1) { Text("\(wd)."); Text(d) }
                                .font(.system(size: 10, weight: k == today ? .bold : .regular))
                                .foregroundStyle(k == today ? Color.white : Theme.secondary)
                        }
                    }
                }
            }
            .frame(height: 230)
        }
    }

    private func ring(_ c: Color) -> some View {
        Circle().strokeBorder(c, lineWidth: 2).background(Circle().fill(Theme.card)).frame(width: 10, height: 10)
    }
}

// MARK: - Stress preview

struct StressPreviewCard: View {
    let day: DaySummary

    var body: some View {
        let last = day.stressPoints.last
        PCard {
            CardHeader(title: "Monitor de estrés", chevron: true)
            HStack {
                Text(last.map { "Última actualización a las \(day.stressClock($0.x))" } ?? "Sin lecturas todavía")
                    .font(.subheadline).foregroundStyle(Color(white: 0.85))
                Spacer()
                if let current = last?.v {
                    Caps(Theme.stressLevel(current), size: 12, color: Theme.stressColor(current))
                    Text(Fmt.dec(current)).scaledFont(20, weight: .bold, relativeTo: .body).monospacedDigit().foregroundStyle(.white)
                }
            }
            StressLine(day: day, compact: true)
                .frame(height: 150)
        }
    }
}

/// Stress minute by minute as a line over a soft fill, both coloured by level (green low, yellow medium, orange
/// high). Runs from the hour the cycle started (waking up), so the hours after midnight come last instead of on the
/// left. Workouts are shaded (there the curve is physical effort); a stretch with the strap off leaves a gap.
struct StressLine: View {
    let day: DaySummary
    var compact = false
    /// Workouts of the day (timestamps), shaded behind the curve.
    var workouts: [ClosedRange<Int>] = []
    /// Minutes since the hour the cycle started, under the finger.
    var selected: Binding<Int?> = .constant(nil)

    private struct Point: Identifiable {
        var x: Int
        var v: Double
        var run: Int
        var id: Int { x }
    }

    /// Points split into runs wherever more than 10 minutes go by without a reading.
    private var points: [Point] {
        var run = 0
        var prev: Int?
        return day.stressPoints.map { p in
            if let q = prev, p.x - q > 10 { run += 1 }
            prev = p.x
            return Point(x: p.x, v: p.v, run: run)
        }
    }

    /// Colour stops for a vertical gradient that spans `lo`…`hi` in stress units, so each height gets the colour
    /// of its own level (a gradient on a mark spans the mark's own bounds, not the axis).
    static func stops(_ lo: Double, _ hi: Double, opacity: (Double) -> Double = { _ in 1 }) -> [Gradient.Stop] {
        let span = max(hi - lo, 0.001)
        func loc(_ v: Double) -> CGFloat { CGFloat(min(max((v - lo) / span, 0), 1)) }
        func stop(_ v: Double, at l: Double) -> Gradient.Stop {
            .init(color: Theme.stressColor(v).opacity(opacity(l)), location: loc(l))
        }
        var out = [stop(lo, at: lo)]
        for t in [1.0, 2.0] where t > lo && t < hi {
            out.append(stop(t - 0.01, at: max(lo, t - 0.15)))
            out.append(stop(t, at: min(hi, t + 0.15)))
        }
        out.append(stop(hi, at: hi))
        return out
    }

    var body: some View {
        let pts = points
        let lo = pts.map(\.v).min() ?? 0, hi = pts.map(\.v).max() ?? 0
        let line = LinearGradient(stops: Self.stops(lo, hi), startPoint: .bottom, endPoint: .top)
        let fill = LinearGradient(stops: Self.stops(0, max(hi, 0.01), opacity: { 0.04 + 0.30 * $0 / max(hi, 0.01) }),
                                  startPoint: .bottom, endPoint: .top)
        // A tick every 5 minutes while scrubbing, not one per minute.
        let scrub = Binding<Int?>(get: { selected.wrappedValue }, set: { selected.wrappedValue = $0.map { $0 / 5 * 5 } })
        let bands = workouts.compactMap { w in day.stressX(w.lowerBound).flatMap { a in day.stressX(w.upperBound).map { a...$0 } } }
        Chart {
            ForEach(Array(bands.enumerated()), id: \.offset) { _, b in
                RectangleMark(xStart: .value("Inicio", b.lowerBound), xEnd: .value("Fin", b.upperBound),
                              yStart: .value("Base", 0.0), yEnd: .value("Tope", 3.0))
                    .foregroundStyle(Color.white.opacity(0.08))
                    .annotation(position: .overlay, alignment: .top) {
                        if !compact { Caps("Entreno", size: 9, color: Theme.secondary, weight: .semibold) }
                    }
            }
            ForEach(pts) { p in
                AreaMark(x: .value("Minuto", p.x), yStart: .value("Base", 0), yEnd: .value("Estrés", p.v),
                         series: .value("Tramo", p.run))
                    .foregroundStyle(fill)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Minuto", p.x), y: .value("Estrés", p.v), series: .value("Tramo", p.run))
                    .foregroundStyle(line)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: compact ? 1.5 : 2, lineCap: .round, lineJoin: .round))
            }
            if let p = pts.last {
                PointMark(x: .value("Minuto", p.x), y: .value("Estrés", p.v))
                    .foregroundStyle(pts.count == 1 ? Theme.stressColor(p.v) : .white)
                    .symbolSize(pts.count == 1 ? 30 : 28)
            }
            if let k = selected.wrappedValue, let p = pts.min(by: { abs($0.x - k) < abs($1.x - k) }) {
                RuleMark(x: .value("Minuto", p.x))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Minuto", p.x), y: .value("Estrés", p.v))
                    .foregroundStyle(Theme.stressColor(p.v))
                    .symbolSize(110)
            }
        }
        .chartScrub(scrub)
        .chartYScale(domain: 0...3)
        .chartXScale(domain: 0...max(1439, pts.last?.x ?? 0))
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 1, 2, 3]) { v in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel { Text(Fmt.dec(v.as(Double.self))).scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary) }
            }
        }
        .chartXAxis {
            AxisMarks(values: compact ? [0, 480, 960, 1380] : [0, 240, 480, 720, 960, 1200, 1380]) { v in
                AxisValueLabel {
                    Text(String(format: "%02d:00", ((v.as(Int.self) ?? 0) / 60 + day.cycleStartHour) % 24))
                        .scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}

extension DaySummary {
    /// Local hour the cycle started (waking up); 0 when unknown.
    var cycleStartHour: Int {
        cycleStart.map { Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval($0))) } ?? 0
    }

    /// Stress readings as minutes since the hour the cycle started. Days analysed before stress was kept per minute
    /// only have hourly means, drawn at the half hour.
    var stressPoints: [(x: Int, v: Double)] {
        if !stressMinutes.isEmpty, let start = cycleStart {
            let offset = Calendar.current.component(.minute, from: Date(timeIntervalSince1970: TimeInterval(start)))
            return stressMinutes.enumerated().compactMap { i, v in v.map { (offset + i, $0) } }
        }
        return (0..<24).compactMap { k in
            let h = (cycleStartHour + k) % 24
            guard h < stressHourly.count, let v = stressHourly[h] else { return nil }
            return (k * 60 + 30, v)
        }
    }

    /// Chart position (minutes since the hour the cycle started) of a timestamp.
    func stressX(_ ts: Int) -> Int? {
        guard let start = cycleStart else { return nil }
        let offset = Calendar.current.component(.minute, from: Date(timeIntervalSince1970: TimeInterval(start)))
        return offset + (ts - (start - start % 60)) / 60
    }

    /// Clock time ("14:05") of a stress point.
    func stressClock(_ x: Int) -> String {
        String(format: "%02d:%02d", (cycleStartHour + x / 60) % 24, x % 60)
    }
}

// MARK: - Dashboard

struct DashboardRow: View {
    @EnvironmentObject var model: AppModel
    let metric: TrendMetric
    let day: DaySummary
    var period = 30

    var body: some View {
        let c = HomeComparison(metric, day: day, period: period, model: model)
        MetricRow(icon: metric.icon, title: HomeLayout.title(metric), value: c.value, baseline: c.caption, delta: c.delta)
    }
}

// MARK: - Coach

/// Floating one-liner with today's advice; tap for the whole plan.
struct CoachBanner: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary
    let open: () -> Void

    var body: some View {
        let advice = model.coachAdvice(for: day)
        let name = model.profile.name.isEmpty ? "" : ", \(model.profile.name.uppercased())"
        Button(action: open) {
            HStack(spacing: 12) {
                Image("Logo")
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Theme.link.opacity(0.6), lineWidth: 1.5))
                Text("\(advice.headline)\(name)")
                    .scaledFont(15, weight: .medium, relativeTo: .body)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up").font(.subheadline.weight(.bold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.link.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct CoachSheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: DaySummary

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    CoachCard(day: day)
                    RecoveryBreakdown(day: day)
                }
                .padding(16)
            }
            .background(PulsoBackground())
            .navigationTitle("Tu plan de hoy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
