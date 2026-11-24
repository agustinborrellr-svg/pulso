import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntelligence

/// 01 · Actividad (02 without the band): the day's effort with steps, calories and zones, the day's activities with
/// Agregar / Iniciar, the week, your form (load | VO₂), the weekly plan, Respira, Recupera and Mídete.
/// Everything comes from the model; a part with no data is left out.
struct ActivityRootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    /// The "sin pulsera" capture draws the disconnected state.
    var forceDisconnected = false
    @AppStorage(AppModel.stressAlertKey) private var stressAlertOn = true
    @State private var stress: Double?
    @State private var lastSlow = Date.distantPast

    private var connected: Bool {
        if forceDisconnected { return false }
        return model.strapState.isConnected || ActShots.assumeConnected
    }

    var body: some View {
        let day = model.selected
        DSTabScreen(spacing: DS.stack) {
            ActividadHeader()
        } content: {
            if model.liveWorkout != nil { runningBanner }
            if !connected { connectNotice }
            effortCard(day)
            activities(day)
            week(day)
            form
            plan
            breathe
            recover
            measure
        }
        .onAppear { refreshSlow(force: true) }
        .onChange(of: model.liveHR) { _, _ in refreshSlow() }
    }

    // MARK: Running workout / band

    private var runningBanner: some View {
        Button { router.open(.actividad(.entrenoVivo)) } label: {
            HStack(spacing: 10) {
                DSDot(color: DS.act, size: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(model.liveWorkout?.sport ?? "Entreno") en curso").dsFont(16, .semibold).foregroundStyle(DS.t1)
                    if let w = model.liveWorkout {
                        TimelineView(.periodic(from: w.start, by: 1)) { ctx in
                            Text(LiveView.duration(ctx.date.timeIntervalSince(w.start))).dsFont(14).foregroundStyle(DS.t2)
                        }
                    }
                }
                Spacer()
                DSChevron()
            }
            .dsCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var connectNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "applewatch").font(.system(size: 18, weight: .semibold)).foregroundStyle(DSLevel.justa.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text("Pulsera desconectada").dsFont(16, .semibold).foregroundStyle(DS.t1)
                if let s = model.lastSync {
                    Text("Última sync \(Fmt.clock(s))").dsFont(14).foregroundStyle(DS.t2)
                }
            }
            Spacer(minLength: 8)
            RouteLink(.tu(.pulsera)) {
                Text("Conectar").dsFont(16, .semibold).foregroundStyle(DS.act)
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(DS.act.opacity(DS.tintOpacity), in: Capsule())
            }
        }
        .dsCard(padding: 14)
    }

    // MARK: Effort

    private func effortCard(_ day: DaySummary?) -> some View {
        let strain = day?.strain
        let prev = day.flatMap { model.day(DayKey.shift($0.day, days: -1)) }
        let target = day.flatMap { d in d.recovery == nil ? nil : model.coachAdvice(for: d).strainTarget }
        let left = target.flatMap { t in strain.map { t.lowerBound - $0 } }.flatMap { $0 > 0.05 ? $0 : nil }
        let zones = day?.zoneMinutes ?? []
        let light = zones.prefix(3).reduce(0, +), hard = zones.dropFirst(3).prefix(2).reduce(0, +)
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                RouteLink(.metric(.esfuerzo)) {
                    VStack(spacing: 2) {
                        ScoreArc(progress: (strain ?? 0) / 21, color: DS.act, value: Fmt.dec(strain),
                                 notch: target.map { $0.lowerBound / 21 }, size: 92, line: 8)
                            .padding(.bottom, 4)
                        Text("Esfuerzo").dsFont(17, .semibold).foregroundStyle(DS.t1)
                        if let t = target {
                            Text("Objetivo \(Int(t.lowerBound))–\(Int(t.upperBound))").dsFont(15, .semibold).foregroundStyle(DS.t2)
                        }
                        if let p = prev?.strain {
                            Text("ayer \(Fmt.dec(p))").dsFont(14).foregroundStyle(DS.t3)
                        }
                    }
                    .frame(width: 128)
                }
                VStack(spacing: 0) {
                    if let s = day?.steps, s > 0 {
                        RouteLink(.metric(.pasos)) { sideRow("Pasos", DSFmt.thousands(Double(s)), "", chevron: true) }
                    }
                    if let k = day?.kcal {
                        if (day?.steps ?? 0) > 0 { DSDivider() }
                        RouteLink(.metric(.calorias)) { sideRow("Calorías", DSFmt.thousands(k), "kcal", chevron: true) }
                    }
                    if let left {
                        DSDivider()
                        sideRow("Te quedan", Fmt.dec(left), "", chevron: false)
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(DS.sep).frame(width: 0.5) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            DSDivider()
            RouteLink(.metric(.zonas)) {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.fill").font(.system(size: 13)).foregroundStyle(DS.act)
                        Text("Zonas de FC").dsFont(16, .semibold).foregroundStyle(DS.t1)
                        Spacer(minLength: 6)
                        if light + hard >= 1 {
                            Group {
                                Text("1-3 ").foregroundStyle(DS.t3) + Text(ActFmt.hmm(light)).foregroundStyle(DS.t1).fontWeight(.semibold)
                                    + Text("  ·  4-5 ").foregroundStyle(DS.t3) + Text(ActFmt.hmm(hard)).foregroundStyle(DS.t1).fontWeight(.semibold)
                            }
                            .dsFont(14).lineLimit(1).minimumScaleFactor(0.8)
                        } else {
                            Text("sin tiempo en zonas").dsFont(14).foregroundStyle(DS.t3)
                        }
                        DSChevron()
                    }
                    ZoneBar(minutes: Array(zones.prefix(5)))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
        }
        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }

    private func sideRow(_ k: String, _ v: String, _ unit: String, chevron: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(k).dsFont(15).foregroundStyle(DS.t2)
            Spacer(minLength: 4)
            HoyValue(value: v, unit: unit, size: 17)
            if chevron { DSChevron() } else { Color.clear.frame(width: 8, height: 1) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: Activities

    private func activities(_ day: DaySummary?) -> some View {
        let items: [Workout] = day.map { d in
            model.activities(on: d).compactMap { a -> Workout? in
                if case .workout(let w) = a.kind { return w }
                return nil
            }
        } ?? []
        let isToday = model.selectedDay >= model.currentDayKey
        return Group {
            DSSectionHeader(isToday ? "Actividades de hoy" : "Actividades")
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isToday ? "Aún no hay actividades hoy" : "Sin actividades este día").dsFont(17, .semibold).foregroundStyle(DS.t1)
                        Text("Los entrenos se detectan solos al sincronizar.").dsFont(15).foregroundStyle(DS.t2)
                    }
                    .padding(.vertical, 4)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { i, w in
                    if i > 0 { DSDivider() }
                    activityRow(w)
                }
                HStack(spacing: 10) {
                    RouteLink(.hoy(.anadirActividad)) {
                        Label("Agregar actividad", systemImage: "plus")
                            .dsFont(15, .semibold).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(DS.fill, in: Capsule())
                    }
                    RouteLink(.hoy(.iniciarActividad)) {
                        Label("Iniciar actividad", systemImage: "timer")
                            .dsFont(15, .semibold).foregroundStyle(DS.act).lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(DS.act.opacity(DS.tintOpacity), in: Capsule())
                    }
                    .disabled(!connected)
                    .opacity(connected ? 1 : 0.45)
                }
                .padding(.top, 14)
            }
            .dsCard(padding: 14)
        }
    }

    @ViewBuilder
    private func activityRow(_ w: Workout) -> some View {
        let kind = Breathwork.Kind.allCases.first { Breathwork.activityName($0) == w.sport }
        let minutes = Double(w.end - w.start) / 60
        let row = DSActivityRow(icon: kind.map { ActBreath.icon($0) } ?? WorkoutDetailView.icon(w.sport),
                                color: kind.map { ActBreath.color($0) } ?? DS.act,
                                duration: Fmt.hmm(minutes), title: w.sport, subtitle: subtitle(w, breathing: kind != nil),
                                start: Fmt.time(w.start), end: Fmt.time(w.end))
        if kind != nil {
            RouteLink(.actividad(.respiraResumen(start: w.start))) { row }
        } else {
            RouteLink(.hoy(.workout(start: w.start))) { row }
        }
    }

    private func subtitle(_ w: Workout, breathing: Bool) -> String? {
        if breathing { return "respiración guiada" }
        if let m = w.distanceMeters, m > 50 {
            let km = m / 1000
            let pace = (Double(w.end - w.start) / 60) / km
            let p = pace.isFinite && pace < 20 ? String(format: " · %d:%02d /km", Int(pace), Int((pace - floor(pace)) * 60)) : ""
            return "\(Fmt.dec(km)) km\(p)"
        }
        return w.strain > 0 ? "esfuerzo \(Fmt.dec(w.strain))" : nil
    }

    // MARK: Week

    @ViewBuilder
    private func week(_ day: DaySummary?) -> some View {
        let end = day?.day ?? model.currentDayKey
        let keys = (0..<7).map { DayKey.shift(end, days: $0 - 6) }
        let values: [Double?] = keys.map { model.day($0)?.strain }
        if values.contains(where: { $0 != nil }) {
            let base = model.days.filter { $0.day < keys[0] && $0.day >= DayKey.shift(keys[0], days: -30) }.compactMap(\.strain)
            let stats: (mean: Double, sd: Double)? = {
                guard base.count >= 7 else { return nil }
                let m = base.reduce(0, +) / Double(base.count)
                let sd = sqrt(base.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(base.count - 1))
                return (m, max(sd, 0.3))
            }()
            let normal = stats.map { ($0.mean - $0.sd)...($0.mean + $0.sd) }
            let present = values.compactMap { $0 }
            RouteLink(.metric(.esfuerzo)) {
                DSSectionHeader("Esta semana", chevron: true, note: "Esfuerzo")
            }
            VStack(alignment: .leading, spacing: 12) {
                if let n = normal {
                    HStack(spacing: 14) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(DS.act.opacity(DS.bandOpacity))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(DS.act.opacity(DS.edgeOpacity), lineWidth: 0.5))
                                .frame(width: 14, height: 9)
                            Text("Tu normal \(Int(n.lowerBound.rounded()))–\(Int(n.upperBound.rounded()))")
                        }
                        HStack(spacing: 6) {
                            Text("---").foregroundStyle(DS.t2)
                            Text("Media")
                        }
                    }
                    .dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2)
                }
                WeekBars(keys: keys, values: values, normal: normal, mean: stats?.mean)
                    .frame(height: 150)
                DSStatStrip(stats: [
                    DSStat(label: "Media", value: Fmt.dec(present.reduce(0, +) / Double(max(present.count, 1)))),
                    DSStat(label: "Días ≥ 10", value: "\(present.filter { $0 >= 10 }.count)"),
                ] + (normal.map { n in [DSStat(label: "En tu normal", value: "\(present.filter { n.contains($0) }.count)", unit: "de \(present.count) días")] } ?? []))
            }
            .dsCard(padding: 14)
        }
    }

    // MARK: Form

    @ViewBuilder
    private var form: some View {
        let load = model.trainingLoad
        let acwr = load.last?.acwr
        let vo2 = model.days.last { $0.vo2max != nil }?.vo2max
        if acwr != nil || vo2 != nil {
            DSSectionHeader("Tu forma")
            HStack(alignment: .top, spacing: DS.stack) {
                if let acwr {
                    RouteLink(.metric(.carga)) { loadCard(acwr, status: TrainingLoad.status(load)) }
                }
                if let vo2 {
                    RouteLink(.metric(.vo2max)) { vo2Card(vo2) }
                }
            }
        }
    }

    private func loadCard(_ r: Double, status: TrainingLoad.Status) -> some View {
        let lv = ActLoad.level(status)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 13)).foregroundStyle(DS.act)
                Text("Carga").dsFont(16, .semibold).foregroundStyle(DS.t1)
                Spacer()
                DSChevron()
            }
            Text(Fmt.dec(r, 2)).dsFont(30, .semibold, relativeTo: .title1).foregroundStyle(DS.t1)
            ActLevelLine(text: ActLoad.word(status), color: lv?.mark ?? DS.t3, ink: lv?.ink ?? DS.t2)
            ActScale(stretches: ActLoad.stretches, marker: ActLoad.position(r)).padding(.top, 6)
            Text("7 días frente a 28").dsFont(13).foregroundStyle(DS.t3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 150, alignment: .top)
        .dsCard(padding: 14)
    }

    private func vo2Card(_ v: Double) -> some View {
        let age = model.profile.age, sex = model.profile.sex
        let bands = VO2Norms.bands(age: age, sex: sex)
        let band = VO2Norms.band(v, age: age, sex: sex)
        let i = bands.firstIndex(of: band) ?? 2
        let lo = bands.first!.lower, hi = bands.last!.upper
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.system(size: 13)).foregroundStyle(DS.act)
                Text("VO₂ máx").dsFont(16, .semibold).foregroundStyle(DS.t1)
                Spacer()
                DSChevron()
            }
            HoyValue(value: Fmt.dec(v), unit: "ml/kg/min", size: 30)
            ActLevelLine(text: band.label, color: ActVO2.colors[i], ink: i == 2 ? DS.t2 : ActVO2.colors[i])
                .lineLimit(1).minimumScaleFactor(0.7)
            ActScale(stretches: ActVO2.stretches(bands), marker: (v - lo) / max(hi - lo, 1)).padding(.top, 6)
            Text("para tu edad y sexo").dsFont(13).foregroundStyle(DS.t3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 150, alignment: .top)
        .dsCard(padding: 14)
    }

    // MARK: Plan

    @ViewBuilder
    private var plan: some View {
        let progress = model.planProgress
        let start = WeeklyPlan.weekStart(model.currentDayKey)
        let dayIndex = (DayKey.date(model.currentDayKey).flatMap { b in DayKey.date(start).map { a in
            Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0 } } ?? 0) + 1
        RouteLink(.actividad(.planSemanal)) {
            DSSectionHeader("Plan semanal", chevron: true, note: progress.isEmpty ? nil : "día \(dayIndex) de 7")
        }
        RouteLink(.actividad(.planSemanal)) {
            VStack(alignment: .leading, spacing: 10) {
                if progress.isEmpty {
                    Text("Ponte metas para esta semana").dsFont(17, .semibold).foregroundStyle(DS.t1)
                    Text("Esfuerzo, sueño, pasos o hábitos.").dsFont(15).foregroundStyle(DS.t2)
                } else {
                    Text("\(progress.filter(\.met).count) de \(progress.count) metas al ritmo").dsFont(17, .semibold).foregroundStyle(DS.t1)
                    HStack(spacing: 5) {
                        ForEach(progress, id: \.goal.id) { p in
                            Capsule().fill(ActPlan.level(p.level).mark).frame(width: 22, height: 4)
                        }
                    }
                }
            }
            .dsCard(padding: 14)
        }
    }

    // MARK: Respira

    private var breathe: some View {
        Group {
            DSSectionHeader("Respira")
            suggestion
            VStack(spacing: 0) {
                DSGroupInlineLabel("Actívate")
                breathRow(.alert)
                DSGroupInlineLabel("Cálmate")
                breathRow(.sigh)
                DSDivider(inset: 48)
                breathRow(.coherence)
                DSDivider(inset: 48)
                breathRow(.box)
                DSGroupInlineLabel("Duerme")
                breathRow(.sleep)
            }
            .padding(.bottom, 4)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            DSGroup {
                DSToggleRow(label: "Alerta de estrés", subtitle: "Vibra si llevas 5 min quieto con estrés alto", isOn: $stressAlertOn)
            }
        }
    }

    private var suggestion: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let (kind, why): (Breathwork.Kind, String) = {
            if let s = stress, s >= 1.8 { return (.sigh, "Estás activado: dos minutos te bajan el pulso") }
            if hour >= 21 || hour < 4 { return (.sleep, "Para ir bajando revoluciones antes de dormir") }
            if hour < 12 { return (.alert, "Empieza el día despierto y con energía") }
            return (.coherence, "Un rato para recargar a media jornada")
        }()
        return RouteLink(.actividad(.respiraDetalle(kind))) {
            HStack(spacing: 12) {
                Image(systemName: ActBreath.icon(kind)).font(.system(size: 17)).foregroundStyle(ActBreath.color(kind)).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Para ti ahora").dsFont(13, .semibold).foregroundStyle(ActBreath.color(kind))
                    Text(Breathwork.activityName(kind)).dsFont(17, .semibold).foregroundStyle(DS.t1)
                    Text(why).dsFont(15).foregroundStyle(DS.t2).lineLimit(2)
                }
                Spacer(minLength: 6)
                DSChevron()
            }
            .dsCard(padding: 14)
        }
    }

    private func breathRow(_ k: Breathwork.Kind) -> some View {
        let last = model.breathworkRecords.last { $0.summary.kind == k }?.summary
        return RouteLink(.actividad(.respiraDetalle(k))) {
            DSRow(icon: ActBreath.icon(k), iconColor: ActBreath.color(k), label: Breathwork.activityName(k),
                  subtitle: last.map(ActBreath.lastLine) ?? ActBreath.blurb(k), chevron: true)
        }
    }

    /// Breathing rate and stress need ~1 minute of beats: every 10 s is plenty.
    private func refreshSlow(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastSlow) >= 10 else { return }
        lastSlow = Date()
        let recent = model.beats(since: Date().addingTimeInterval(-90))
        stress = LiveMetrics.scan(recent, baseline: model.liveBaseline)?.stress
    }

    // MARK: Recupera

    private var recover: some View {
        let since = Int(Date().timeIntervalSince1970) - 90 * 86_400
        let recent = (try? model.db.workouts(from: since, to: Int(Date().timeIntervalSince1970) + 60)) ?? []
        return Group {
            DSSectionHeader("Recupera")
            HStack(spacing: DS.stack) {
                recoverCard("Sauna", "flame.fill", DS.act, recent.last { $0.sport == "Sauna" })
                recoverCard("Baño de hielo", "snowflake", DS.cons, recent.last { $0.sport == "Baño de hielo" })
            }
        }
    }

    private func recoverCard(_ sport: String, _ icon: String, _ color: Color, _ last: Workout?) -> some View {
        Button { model.startWorkout(sport: sport, plan: nil) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color).padding(.bottom, 18)
                Text(sport).dsFont(17, .semibold).foregroundStyle(DS.t1)
                Text(last.map { w in
                    "\(DSFmt.duration(Double(w.end - w.start) / 60))" + (w.maxHR > 0 ? " · pico \(Int(w.maxHR))" : "")
                } ?? "Temporizador y pulso pico")
                .dsFont(14).foregroundStyle(DS.t2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard(padding: 14)
        }
        .buttonStyle(.plain)
        .disabled(!connected || model.liveWorkout != nil)
        .opacity(connected ? 1 : 0.45)
    }

    // MARK: Mídete

    private var measure: some View {
        let tests = model.liveTests
        let scan = tests.last { $0.kind == .scan }
        let ortho = tests.last { $0.kind == .orthostatic }
        let rec = tests.last { $0.kind == .recovery }
        return Group {
            DSSectionHeader("Mídete")
            DSGroup {
                RouteLink(.actividad(.chequeo60s)) {
                    DSRow(icon: "dot.radiowaves.left.and.right", iconColor: DS.t1, label: "Chequeo de 60 s",
                          subtitle: "VFC, respiración y estrés", value: scan.map { "\($0.detail) · \(Int($0.value))" }, chevron: true)
                }
                RouteLink(.actividad(.ortostatico)) {
                    DSRow(icon: "figure.stand", iconColor: DSLevel.justa.ink, label: "Ortostático", subtitle: "Tumbado y de pie",
                          value: ortho.map { "\(ActFmt.signedInt($0.value)) lpm" }, chevron: true)
                }
                RouteLink(.actividad(.recuperacionFC)) {
                    DSRow(icon: "arrow.down.heart.fill", iconColor: DSLevel.buena.ink, label: "Recuperación FC", subtitle: "Cuánto baja en 1 min",
                          value: rec.map { "−\(Int($0.value.rounded())) lpm" }, chevron: true)
                }
                RouteLink(.actividad(.fcMaxima)) {
                    DSRow(icon: "bolt.heart.fill", iconColor: DSLevel.baja.ink, label: "FC máxima", subtitle: "Tu techo real",
                          value: "\(Int(model.heartRateModel.maxHR.rounded())) lpm", chevron: true)
                }
                RouteLink(.actividad(.poincare)) {
                    DSRow(icon: "circle.grid.cross.fill", iconColor: DS.sueno, label: "Poincaré", subtitle: "Tu VFC dibujada", chevron: true)
                }
                RouteLink(.actividad(.monitorVivo)) {
                    DSRow(icon: "waveform.path.ecg", iconColor: DS.recarga, label: "Todo lo que mide", subtitle: "Cada dato de la pulsera, con su hora", chevron: true)
                }
            }
            .disabled(!connected)
            .opacity(connected ? 1 : 0.45)
        }
    }
}

// MARK: - Header

/// Date, the day pill (‹ Hoy ›, the middle opens the calendar) and the band's battery.
struct ActividadHeader: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let isToday = model.selectedDay >= model.currentDayKey
        ZStack {
            HStack {
                Text(DSFmt.shortDate(model.selectedDay)).dsFont(15, .semibold, relativeTo: .subheadline).foregroundStyle(DS.t2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                RouteLink(.tu(.pulsera)) {
                    HStack(spacing: 5) {
                        Image(systemName: "applewatch").font(.system(size: 14, weight: .semibold))
                        if let b = model.battery { Text("\(Int(b)) %").dsFont(15, .semibold, relativeTo: .subheadline) }
                    }
                    .foregroundStyle(model.battery.map { $0 < 20 } == true ? DSLevel.baja.ink : DS.t2)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(model.battery.map { "Pulsera, batería \(Int($0)) %" } ?? "Pulsera")
            }
            HStack(spacing: 0) {
                Button { model.shiftSelectedDay(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 38).contentShape(Rectangle())
                }
                .accessibilityLabel("Día anterior")
                RouteLink(.hoy(.calendario)) {
                    Text(pillTitle).dsFont(17, .semibold, relativeTo: .headline).foregroundStyle(DS.t1)
                        .fixedSize().frame(minWidth: 56, minHeight: 38).contentShape(Rectangle())
                }
                .accessibilityHint("Abre el calendario")
                Button { model.shiftSelectedDay(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 38).contentShape(Rectangle())
                }
                .accessibilityLabel("Día siguiente")
                .disabled(isToday)
                .foregroundStyle(isToday ? DS.t3 : DS.t1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.t1)
            .background(DS.card, in: Capsule())
        }
        .padding(.top, 4)
    }

    private var pillTitle: String {
        let k = model.selectedDay
        if k >= model.currentDayKey { return "Hoy" }
        if k == DayKey.shift(model.currentDayKey, days: -1) { return "Ayer" }
        guard let a = DayKey.date(k), let b = DayKey.date(model.currentDayKey) else { return k }
        return "Hace \(Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0) días"
    }
}

// MARK: - Pieces

/// Grey sub-label inside a `DSGroup` ("Actívate", "Cálmate").
struct DSGroupInlineLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).dsFont(13, .semibold, relativeTo: .footnote).foregroundStyle(DS.t2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 0)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Time in each zone as one bar of five stretches (empty track when there is none).
struct ZoneBar: View {
    let minutes: [Double]

    var body: some View {
        let total = minutes.reduce(0, +)
        GeometryReader { g in
            if total < 1 {
                Capsule().fill(DS.fill)
            } else {
                let parts = minutes.enumerated().filter { $0.element > 0 }
                let gap: CGFloat = 3
                let usable = g.size.width - gap * CGFloat(max(0, parts.count - 1))
                HStack(spacing: gap) {
                    ForEach(parts, id: \.offset) { p in
                        Capsule().fill(DS.zone(p.offset + 1)).frame(width: max(3, usable * CGFloat(p.element / total)))
                    }
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// A short coloured scale with a knob (carga, VO₂).
struct ActScale: View {
    let stretches: [DSRangeBar.Stretch]
    let marker: Double

    var body: some View {
        DSRangeBar(stretches: stretches, marker: min(max(marker, 0), 1))
    }
}

/// The week's daily effort as bars, today in orange, "tu normal" as a band and the mean as a dashed line.
private struct WeekBars: View {
    let keys: [String]
    let values: [Double?]
    let normal: ClosedRange<Double>?
    let mean: Double?

    var body: some View {
        let top = max(14, (values.compactMap { $0 }.max() ?? 0) + 1, normal?.upperBound ?? 0)
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width - 26
                let h = g.size.height
                let y = { (v: Double) in h - h * CGFloat(v / top) }
                ZStack(alignment: .topLeading) {
                    ForEach([0.0, 7, 14].filter { $0 <= top }, id: \.self) { t in
                        Rectangle().fill(DS.sep).frame(width: w, height: 0.5).offset(y: y(t))
                        Text("\(Int(t))").dsFont(11, relativeTo: .caption2).foregroundStyle(DS.t3)
                            .position(x: w + 14, y: y(t))
                    }
                    if let n = normal {
                        Rectangle().fill(DS.act.opacity(DS.bandOpacity))
                            .overlay(Rectangle().stroke(DS.act.opacity(DS.edgeOpacity), lineWidth: 0.5))
                            .frame(width: w, height: max(2, y(n.lowerBound) - y(n.upperBound)))
                            .offset(y: y(n.upperBound))
                        Text("tu normal").dsFont(11, .semibold, relativeTo: .caption2).foregroundStyle(DS.act)
                            .offset(x: 4, y: y(n.upperBound) + 2)
                    }
                    let slot = w / CGFloat(values.count)
                    ForEach(values.indices, id: \.self) { i in
                        if let v = values[i] {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(i == values.count - 1 ? DS.act : DS.fill2)
                                .frame(width: slot * 0.56, height: max(2, h - y(v)))
                                .offset(x: slot * CGFloat(i) + slot * 0.22, y: y(v))
                        }
                    }
                    if let mean {
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y(mean)))
                            p.addLine(to: CGPoint(x: w, y: y(mean)))
                        }
                        .stroke(DS.t2, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(keys.indices, id: \.self) { i in
                    Text(ActWeek.initial(keys[i])).dsFont(12, i == keys.count - 1 ? .bold : .medium, relativeTo: .caption1)
                        .foregroundStyle(i == keys.count - 1 ? DS.t1 : DS.t3)
                        .frame(maxWidth: .infinity)
                }
                Color.clear.frame(width: 26, height: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Esfuerzo de los últimos 7 días")
    }
}

// MARK: - Shared mappings

enum ActWeek {
    /// "L", "M", "X"…
    static func initial(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return "" }
        return ["D", "L", "M", "X", "J", "V", "S"][Calendar.current.component(.weekday, from: d) - 1]
    }
}

/// Colour and icon of each breathing session (identity colour, no tile): Actívate orange, suspiro blue, coherencia pink,
/// caja and 4-7-8 violet.
enum ActBreath {
    static func color(_ k: Breathwork.Kind) -> Color {
        switch k {
        case .alert: return DS.act
        case .sigh: return DS.recarga
        case .coherence: return DS.cor
        case .box, .sleep: return DS.sueno
        }
    }

    static func icon(_ k: Breathwork.Kind) -> String {
        switch k {
        case .alert: return "gauge.with.dots.needle.67percent"
        case .sigh: return "wind"
        case .coherence: return "waveform.path.ecg"
        case .box: return "square"
        case .sleep: return "moon.fill"
        }
    }

    static func blurb(_ k: Breathwork.Kind) -> String {
        switch k {
        case .alert: return "Respiración rápida con retenciones"
        case .sigh: return "Doble inspiración y espiración larga"
        case .coherence: return "6 respiraciones por minuto"
        case .box: return "4-4-4-4 antes de algo importante"
        case .sleep: return "4-7-8 en la cama"
        }
    }

    static func lastLine(_ s: Breathwork.Summary) -> String {
        if s.kind == .alert, let best = s.retentions.max() { return "Última: retención \(LiveView.duration(best))" }
        if let c = s.stressChange { return "Última: estrés \(c <= 0 ? "−" : "+")\(Fmt.dec(abs(c)))" }
        return "Última: \(Fmt.dayTitle(DayKey.string(ts: s.start)).lowercased())"
    }
}

enum ActLoad {
    static let cuts = [0.8, 1.0, 1.3, 1.5]
    static let lo = 0.5, hi = 1.8

    static func position(_ r: Double) -> Double { (r - lo) / (hi - lo) }

    static var stretches: [DSRangeBar.Stretch] {
        [.init(to: position(0.8), color: DS.fill2), .init(to: position(1.0), color: DS.fill2),
         .init(to: position(1.3), color: DS.buena), .init(to: position(1.5), color: DS.justa), .init(to: 1, color: DS.baja)]
    }

    static func level(_ s: TrainingLoad.Status) -> DSLevel? {
        switch s {
        case .optimal: return .buena
        case .overreaching: return .justa
        case .risk: return .baja
        default: return nil
        }
    }

    static func word(_ s: TrainingLoad.Status) -> String {
        switch s {
        case .optimal: return "Óptima"
        case .maintaining: return "Mantiene"
        case .detraining: return "Baja"
        case .overreaching: return "Alta"
        case .risk: return "Riesgo"
        case .calibrating: return "Calibrando"
        }
    }
}

enum ActVO2 {
    static let colors: [Color] = [DS.baja, DS.justa, DS.t3, DS.buena, DS.excelente]

    static func stretches(_ bands: [VO2Norms.Band]) -> [DSRangeBar.Stretch] {
        let lo = bands.first!.lower, hi = bands.last!.upper
        return bands.indices.map { .init(to: (bands[$0].upper - lo) / max(hi - lo, 1), color: colors[$0]) }
    }
}

enum ActPlan {
    /// Por detrás / Al límite / Al ritmo for the plan's three levels (the plan's rules are unchanged).
    static func level(_ l: Int) -> DSLevel { [DSLevel.baja, .justa, .buena][min(max(l, 0), 2)] }
    static func word(_ l: Int) -> String { ["Por detrás", "Al límite", "Al ritmo"][min(max(l, 0), 2)] }
}
