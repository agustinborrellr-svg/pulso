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
    @AppStorage("pulso.dashboard") private var dashboardRaw = HomeView.defaultDashboard

    static let defaultDashboard = [
        TrendMetric.hrv, .rhr, .respRate, .sleepPerformance, .sleepHours, .sleepDebt, .efficiency, .strain, .avgHR,
        .calories, .steps, .zonesLight, .zonesHard, .vo2max, .recovery, .regularity, .restorativePct, .restorativeHours, .timeInBed,
    ].map(\.rawValue).joined(separator: ",")

    private var dashboard: [TrendMetric] {
        dashboardRaw.split(separator: ",").compactMap { TrendMetric(rawValue: String($0)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HomeTopBar()
                    pillarTabs
                    AlarmBanner()
                    if model.isEvening && model.selectedDay == DayKey.string(Date()) {
                        BedtimeCard()
                    }
                    if let day = model.selected {
                        PillarHero(day: day)
                        StrainRecoveryWeekCard()
                        if day.stressHourly.contains(where: { $0 != nil }) {
                            NavigationLink { StressMonitorView() } label: { StressPreviewCard(day: day) }
                                .buttonStyle(.plain)
                        }
                        SectionHeading(text: "Mi panel de control", trailing: "Personalizar") { customizing = true }
                        ForEach(dashboard) { m in
                            NavigationLink {
                                TrendDetailView(metric: m)
                            } label: {
                                DashboardRow(metric: m, day: day)
                            }
                            .buttonStyle(.plain)
                        }
                        JournalCard(day: model.selectedDay)
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
                DashboardEditor(raw: $dashboardRaw)
            }
            .sheet(isPresented: $showCoach) {
                if let day = model.selected { CoachSheet(day: day) }
            }
        }
    }

    private var pillarTabs: some View {
        let d = model.selected
        return HStack {
            NavigationLink { SleepDetailView() } label: {
                PillarTab(label: "Sueño", progress: d?.sleepPerformance ?? 0, color: Theme.sleep)
            }
            Spacer()
            NavigationLink { RecoveryDetailView() } label: {
                PillarTab(label: "Recuperación", progress: (d?.recovery ?? 0) / 100, color: Theme.recoveryColor(d?.recovery))
            }
            Spacer()
            NavigationLink { StrainDetailView() } label: {
                PillarTab(label: "Esfuerzo", progress: (d?.strain ?? 0) / 21, color: Theme.strain)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var firstRun: some View {
        VStack(spacing: 16) {
            EmptyState(icon: "sensor.tag.radiowaves.forward",
                       title: model.strapState.isConnected ? "Recopilando datos" : "Conecta tu pulsera",
                       message: model.strapState.isConnected
                           ? "Tu primera recuperación aparece tras la primera noche. Las líneas base se calibran en 4 noches."
                           : "Toca el icono de la pulsera arriba a la derecha para emparejar tu WHOOP 5.0.")
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
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Button { model.shiftSelectedDay(-1) } label: {
                    Image(systemName: "chevron.left").font(.subheadline.weight(.bold)).frame(width: 30, height: 34)
                }
                Caps(Fmt.cycleTitle(model.selectedDay), size: 12)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.cardHighlight, in: Capsule())
                Button { model.shiftSelectedDay(1) } label: {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).frame(width: 30, height: 34)
                }
                .disabled(model.selectedDay >= DayKey.string(Date()))
                .opacity(model.selectedDay >= DayKey.string(Date()) ? 0.3 : 1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            Spacer(minLength: 0)
            NavigationLink {
                DeviceView()
            } label: {
                HStack(spacing: 5) {
                    Text(model.battery.map { "\(Int($0)) %" } ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "applewatch.side.right")
                            .font(.system(size: 24, weight: .light))
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

// MARK: - Hero

/// The three dials, each opening its pillar.
struct PillarHero: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary

    var body: some View {
        PCard(padding: 18) {
            HStack(alignment: .top, spacing: 0) {
                NavigationLink { SleepDetailView() } label: {
                    dial(progress: day.sleepPerformance ?? 0, color: Theme.sleep,
                         value: day.sleepPerformance.map { "\(Int(($0 * 100).rounded()))" } ?? "–", unit: "%", label: "Sueño")
                }
                NavigationLink { RecoveryDetailView() } label: {
                    dial(progress: (day.recovery ?? 0) / 100, color: Theme.recoveryColor(day.recovery),
                         value: day.recovery.map { "\(Int($0))" } ?? (day.calibrating ? "…" : "–"), unit: day.recovery == nil ? "" : "%",
                         label: "Recuperación")
                }
                NavigationLink { StrainDetailView() } label: {
                    dial(progress: (day.strain ?? 0) / 21, color: Theme.strain, value: Fmt.dec(day.strain), unit: "", label: "Esfuerzo")
                }
            }
            .buttonStyle(.plain)
            if day.recovery == nil && day.calibrating {
                Text("Calibrando tus líneas base: la recuperación aparece tras 4 noches.")
                    .font(.caption).foregroundStyle(Theme.secondary)
            }
        }
    }

    private func dial(progress: Double, color: Color, value: String, unit: String, label: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Dial(progress: progress, color: color, lineWidth: 9)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value).font(.system(size: 26, weight: .bold)).monospacedDigit()
                    if !unit.isEmpty { Text(unit).font(.system(size: 12, weight: .bold)) }
                }
                .foregroundStyle(.white)
            }
            .frame(width: 92, height: 92)
            Caps(label, size: 11, color: color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Strain & recovery week

struct StrainRecoveryWeekCard: View {
    @EnvironmentObject var model: AppModel
    @State private var info = false

    var body: some View {
        let today = DayKey.string(Date())
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
                                Text("\(Int(r)) %").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.recoveryColor(r)).fixedSize()
                            }
                    }
                    if let s = byDay[k]?.strain {
                        LineMark(x: .value("Día", k), y: .value("Esfuerzo", s), series: .value("s", "str"))
                            .foregroundStyle(Theme.strain)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Día", k), y: .value("Esfuerzo", s))
                            .symbol { ring(Theme.strain) }
                            .annotation(position: .bottom, spacing: 3) {
                                Text(Fmt.dec(s)).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.strain).fixedSize()
                            }
                    }
                }
            }
            .chartYScale(domain: 0...21)
            .chartXScale(domain: keys)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 7, 14, 21]) { v in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.system(size: 10)).foregroundStyle(Theme.strain) }
                }
                AxisMarks(position: .trailing, values: [0, 7, 14, 21]) { v in
                    AxisValueLabel {
                        let pct = [0: "0%", 7: "33%", 14: "66%", 21: "100%"][v.as(Int.self) ?? 0] ?? ""
                        Text(pct).font(.system(size: 10)).foregroundStyle([0: Theme.red, 7: Theme.red, 14: Theme.yellow, 21: Theme.green][v.as(Int.self) ?? 0] ?? Theme.secondary)
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
        let hourly = day.stressHourly
        let lastHour = hourly.lastIndex { $0 != nil }
        let current = lastHour.flatMap { hourly[$0] }
        PCard {
            CardHeader(title: "Monitor de estrés", chevron: true)
            HStack {
                Text(lastHour.map { "Última actualización a las \($0):00" } ?? "Sin lecturas todavía")
                    .font(.subheadline).foregroundStyle(Color(white: 0.85))
                Spacer()
                if let current {
                    Caps(Theme.stressLevel(current), size: 12, color: Theme.stressColor(current))
                    Text(Fmt.dec(current)).font(.system(size: 20, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                }
            }
            StressLine(hourly: hourly, compact: true)
                .frame(height: 150)
        }
    }
}

/// Hourly stress as a line coloured by level.
struct StressLine: View {
    let hourly: [Double?]
    var compact = false
    var sleep: ClosedRange<Int>?

    var body: some View {
        Chart {
            if let sleep {
                RectangleMark(xStart: .value("a", sleep.lowerBound), xEnd: .value("b", sleep.upperBound), yStart: .value("y0", 0), yEnd: .value("y1", 3))
                    .foregroundStyle(Color.white.opacity(0.05))
                    .annotation(position: .top, alignment: .center) {
                        Image(systemName: "moon.fill").font(.caption).foregroundStyle(.white)
                    }
            }
            ForEach(Array(hourly.enumerated()), id: \.offset) { item in
                if let v = item.element {
                    LineMark(x: .value("Hora", item.offset), y: .value("Estrés", v))
                        .foregroundStyle(LinearGradient(colors: [Theme.stressLow, Theme.stressMid, Theme.stressHigh],
                                                        startPoint: .bottom, endPoint: .top))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                }
            }
        }
        .chartYScale(domain: 0...3)
        .chartXScale(domain: 0...23)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 1, 2, 3]) { v in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel { Text(Fmt.dec(v.as(Double.self))).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
            }
        }
        .chartXAxis {
            AxisMarks(values: compact ? [0, 8, 16, 23] : [0, 4, 8, 12, 16, 20, 23]) { v in
                AxisValueLabel { Text(String(format: "%02d:00", v.as(Int.self) ?? 0)).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardRow: View {
    @EnvironmentObject var model: AppModel
    let metric: TrendMetric
    let day: DaySummary

    var body: some View {
        let value = metric.value(day)
        let usual = TrendSeries.window(days: model.days.filter { $0.day < day.day }, value: { metric.value($0) }, period: .month,
                                       today: DayKey.shift(day.day, days: -1)).summary
        MetricRow(icon: metric.icon, title: metric.title, value: metric.format(value), baseline: usual.map { metric.format($0) },
                  delta: value == nil ? nil : Delta(value, usual, higherIsBetter: metric.higherIsBetter))
    }
}

/// Choose and order the dashboard rows.
struct DashboardEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var raw: String
    @State private var items: [TrendMetric] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { m in
                        Label(m.title, systemImage: m.icon)
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { items.remove(atOffsets: $0) }
                } header: {
                    Text("En tu panel")
                } footer: {
                    Text("Arrastra para ordenar; desliza para quitar.")
                }
                let hidden = TrendMetric.allCases.filter { !items.contains($0) }
                if !hidden.isEmpty {
                    Section("Añadir") {
                        ForEach(hidden) { m in
                            Button {
                                withAnimation { items.append(m) }
                            } label: {
                                HStack {
                                    Label(m.title, systemImage: m.icon)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.green)
                                }
                            }
                            .foregroundStyle(.white)
                        }
                    }
                }
                Section {
                    Button("Restablecer el orden original") { items = HomeView.defaultDashboard.split(separator: ",").compactMap { TrendMetric(rawValue: String($0)) } }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Mi panel de control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        raw = items.map(\.rawValue).joined(separator: ",")
                        dismiss()
                    }
                }
            }
            .onAppear { items = raw.split(separator: ",").compactMap { TrendMetric(rawValue: String($0)) } }
        }
        .preferredColorScheme(.dark)
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
                    .font(.system(size: 15, weight: .medium))
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
