import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoFeatures

/// What a live-workout capture opens on top of the screen (studio C 12 / 13).
enum LivePanel: String, Hashable {
    case zona, terminar
}

/// 10 · Entreno en vivo (11 with an interval plan): full screen with ⌄ (back to the app, the workout keeps running)
/// and a lock. Pulse, zone ramp and the last 10 minutes against the target band; the clock and four figures; target
/// zone (12, own menu); laps; Vuelta / Terminar (13, confirmation). Sauna and ice bath use the same screen.
/// No GPS: no distance, pace or map.
struct LiveWorkoutView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    var initialPanel: LivePanel?
    @State private var zoneMenu = false
    @State private var confirmStop = false
    @State private var locked = false
    @State private var opened = false

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            if let w = model.liveWorkout {
                VStack(spacing: 0) {
                    nav(w)
                    ScrollView {
                        VStack(alignment: .leading, spacing: DS.stack) {
                            if let runner = model.intervalRunner, runner.plan.id == w.planID {
                                IntervalCard(plan: runner.plan, runner: runner, model: model.heartRateModel)
                                pulseCard(w)
                                timeCard(w)
                            } else {
                                pulseCard(w)
                                timeCard(w)
                            }
                            targetRow(w)
                            laps(w)
                        }
                        .padding(.horizontal, DS.gutter)
                        .padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)
                    controls
                }
                if zoneMenu { zoneMenuOverlay(w) }
            } else {
                VStack(spacing: 0) {
                    DSNavBar("Entreno", onBack: { dismiss() })
                    Spacer()
                    DSEmptyState(icon: "figure.run", title: "Sin entreno en curso",
                                 message: "Empieza uno desde «Iniciar actividad».", bare: true)
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("¿Terminar entreno?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Guardar") { stop(save: true) }
            Button("Descartar", role: .destructive) { stop(save: false) }
            Button("Cancelar", role: .cancel) {}
        }
        .onAppear {
            guard !opened else { return }
            opened = true
            guard let p = initialPanel else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                switch p {
                case .zona: zoneMenu = true
                case .terminar: confirmStop = true
                }
            }
        }
    }

    // MARK: Nav

    private func nav(_ w: LiveWorkout) -> some View {
        let plan = model.intervalRunner?.plan
        return ZStack {
            VStack(spacing: 1) {
                Text(plan?.name ?? w.sport).dsFont(17, .semibold, relativeTo: .headline).foregroundStyle(DS.t1).lineLimit(1)
                HStack(spacing: 5) {
                    DSDot(color: DS.act, size: 7)
                    Text(plan == nil ? "En curso" : "\(w.sport) en curso").dsFont(13).foregroundStyle(DS.t2).lineLimit(1)
                }
            }
            .frame(maxWidth: 220)
            HStack {
                Button { dismiss() } label: { DSCircleButton(icon: "chevron.down") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Minimizar; el entreno sigue")
                Spacer()
                Button { locked.toggle() } label: {
                    Image(systemName: locked ? "lock.fill" : "lock").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(locked ? DS.act : DS.t2)
                        .frame(width: 36, height: 36)
                        .background(DS.card, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(locked ? "Desbloquear la pantalla" : "Bloquear la pantalla")
            }
        }
        .frame(height: 52)
        .padding(.top, 4)
        .padding(.horizontal, DS.gutter)
    }

    // MARK: Pulse

    private var zoneBand: (range: ClosedRange<Double>, label: String, zones: ClosedRange<Int>)? {
        let m = model.heartRateModel
        if let r = model.intervalRunner, let w = model.liveWorkout, r.plan.id == w.planID {
            let pos = r.position(at: Int(Date().timeIntervalSince1970))
            if pos.index < r.plan.steps.count, let lo = r.plan.steps[pos.index].zoneLow, let hi = r.plan.steps[pos.index].zoneHigh {
                return (ActZones.span(lo, hi, m), lo == hi ? "Objetivo zona \(lo)" : "Objetivo zonas \(lo)-\(hi)", lo...hi)
            }
        }
        if let z = model.liveWorkout?.targetZone {
            return (ActZones.range(z, m), "Zona objetivo \(z)", z...z)
        }
        return nil
    }

    private func pulseCard(_ w: LiveWorkout) -> some View {
        let m = model.heartRateModel
        let hr = model.liveHR
        let zone = hr.map { m.zone(Double($0)) } ?? 0
        let band = zoneBand
        let note: String? = {
            guard let band else { return nil }
            if model.intervalRunner != nil, let hr {
                return band.range.contains(Double(hr)) ? "en zona" : (Double(hr) > band.range.upperBound ? "por encima" : "por debajo")
            }
            return w.targetZone.map { "objetivo zona \($0)" }
        }()
        let frac: Double = {
            guard let hr, zone >= 1 else { return 0 }
            let r = ActZones.range(zone, m)
            return (Double(hr) - r.lowerBound) / max(1, r.upperBound - r.lowerBound)
        }()
        let pts = model.livePoints.filter { $0.date >= w.start.addingTimeInterval(-5) }.map { ActHRChart.P(t: $0.date, v: Double($0.hr)) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill").font(.system(size: 14)).foregroundStyle(DS.cor)
                Text("Frecuencia cardíaca").dsFont(16, .semibold).foregroundStyle(DS.t2)
                Spacer()
                if let note { Text(note).dsFont(14).foregroundStyle(DS.t3) }
            }
            ActBigValue(value: hr.map(String.init) ?? "--", unit: "lpm", size: 92)
                .contentTransition(.numericText())
                .animation(.snappy, value: hr)
            if zone >= 1 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    DSDot(color: DS.zone(zone), size: 9)
                    Text("Zona \(zone) · \(ActZones.name(zone))").dsFont(17, .semibold).foregroundStyle(DS.t1)
                    Text("\(ActZones.text(zone, m)) lpm").dsFont(15).foregroundStyle(DS.t2)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
            }
            ActZoneRamp(zone: zone, fraction: frac)
            ActHRChart(points: pts, band: band?.range, bandLabel: band?.label)
                .padding(.top, 6)
        }
        .dsCard(padding: 14)
    }

    // MARK: Time and figures

    private func timeCard(_ w: LiveWorkout) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                Text("Tiempo").dsFont(15).foregroundStyle(DS.t2)
                Spacer()
                TimelineView(.periodic(from: w.start, by: 1)) { ctx in
                    Text(LiveView.duration(ctx.date.timeIntervalSince(w.start)))
                        .dsFont(56, .semibold, relativeTo: .largeTitle, maxScale: 1.15).foregroundStyle(DS.t1)
                        .contentTransition(.numericText())
                }
            }
            DSDivider()
            DSStatStrip(stats: [
                DSStat(label: "Esfuerzo", value: Fmt.dec(Strain.score(load: w.load))),
                DSStat(label: "Calorías", value: Fmt.int(w.kcal), unit: "kcal"),
                DSStat(label: "FC media", value: w.hrCount > 0 ? "\(Int(w.hrSum / Double(w.hrCount)))" : "–", unit: "lpm"),
                DSStat(label: "FC máx", value: w.maxHR > 0 ? "\(w.maxHR)" : "–", unit: "lpm"),
            ])
        }
        .dsCard(padding: 14)
    }

    // MARK: Target zone (12)

    private func targetRow(_ w: LiveWorkout) -> some View {
        let m = model.heartRateModel
        return Button { withAnimation(.easeOut(duration: 0.18)) { zoneMenu = true } } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zona objetivo").dsFont(17, .semibold).foregroundStyle(DS.t1)
                    Text("Vibra si te sales 10 s").dsFont(14).foregroundStyle(DS.t2)
                }
                Spacer(minLength: 8)
                Text(w.targetZone.map { "Zona \($0) · \(ActZones.text($0, m))" } ?? "Sin zona")
                    .dsFont(16, .semibold).foregroundStyle(w.targetZone == nil ? DS.t2 : DS.act)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(w.targetZone == nil ? DS.t3 : DS.act)
            }
            .dsCard(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private func zoneMenuOverlay(_ w: LiveWorkout) -> some View {
        let m = model.heartRateModel
        let options: [(Int, String)] = [(0, "Sin zona objetivo")] + (1...5).map { ($0, "Mantener zona \($0) · \(ActZones.text($0, m)) lpm") }
        return ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { zoneMenu = false } }
            VStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { i in
                    if i > 0 { DSDivider() }
                    Button {
                        model.setTargetZone(options[i].0 == 0 ? nil : options[i].0)
                        withAnimation(.easeOut(duration: 0.15)) { zoneMenu = false }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                                .opacity((w.targetZone ?? 0) == options[i].0 ? 1 : 0)
                            Text(options[i].1).dsFont(16).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(DS.t1)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 290)
            .background(DS.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.trailing, DS.gutter)
            .padding(.bottom, 110)
        }
        .transition(.opacity)
    }

    // MARK: Laps

    @ViewBuilder
    private func laps(_ w: LiveWorkout) -> some View {
        if !w.lapStats.isEmpty {
            DSSectionHeader("Vueltas")
            VStack(spacing: 0) {
                ForEach(Array(w.lapStats.enumerated()), id: \.offset) { i, lap in
                    if i > 0 { DSDivider() }
                    lapRow("Vuelta \(i + 1)", LiveView.duration(lap.duration), lap.avgHR.map { "\(Int($0)) lpm" } ?? "–", current: false)
                }
                DSDivider()
                let from = Double(w.laps.last ?? Int(w.start.timeIntervalSince1970))
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    lapRow("Vuelta \(w.lapStats.count + 1)", LiveView.duration(ctx.date.timeIntervalSince1970 - from), "en curso", current: true)
                }
            }
            .padding(.horizontal, 14)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        }
    }

    private func lapRow(_ name: String, _ time: String, _ hr: String, current: Bool) -> some View {
        HStack(spacing: 12) {
            Text(name).dsFont(16).foregroundStyle(current ? DS.act : DS.t1)
            Spacer()
            Text(time).dsFont(16, .semibold).foregroundStyle(current ? DS.act : DS.t1)
            Text(hr).dsFont(16).foregroundStyle(DS.t2).frame(width: 78, alignment: .trailing)
        }
        .frame(minHeight: 46)
    }

    // MARK: Controls (13)

    private var controls: some View {
        HStack(spacing: 10) {
            Button { model.markLap() } label: {
                Label("Vuelta", systemImage: "flag.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(DSButtonStyle(size: .xl, gray: true, fullWidth: true))
            Button { confirmStop = true } label: {
                Label("Terminar", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(DSButtonStyle(tint: DSLevel.baja.ink, size: .xl, fullWidth: true))
        }
        .disabled(locked)
        .opacity(locked ? 0.45 : 1)
        .padding(.horizontal, DS.gutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(DS.bg)
    }

    private func stop(save: Bool) {
        let start = model.liveWorkout.map { Int($0.start.timeIntervalSince1970) }
        let long = model.liveWorkout.map { Date().timeIntervalSince($0.start) >= 60 } ?? false
        model.stopWorkout(save: save)
        dismiss()
        if save, long, let start {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { router.open(.hoy(.workout(start: start))) }
        }
    }
}

// MARK: - Interval plan (11)

/// The step on now ("Serie 2 de 4 · Trabajo"), its countdown and what comes next, and the whole plan as a strip with
/// a marker at now.
private struct IntervalCard: View {
    let plan: IntervalPlan
    let runner: IntervalRunner
    let model: HeartRateModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = Int(ctx.date.timeIntervalSince1970)
            let pos = runner.position(at: now)
            let i = min(pos.index, plan.steps.count - 1)
            let step = plan.steps[i]
            let next = i + 1 < plan.steps.count ? plan.steps[i + 1] : nil
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(header(i)).dsFont(15, .semibold).foregroundStyle(DS.act)
                    Spacer()
                    if let next {
                        Text("después: \(next.kind.label) · \(DSFmt.duration(Double(next.seconds) / 60))")
                            .dsFont(14).foregroundStyle(DS.t3).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.kind.label).dsFont(28, .bold, relativeTo: .title1).foregroundStyle(DS.t1)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if let lo = step.zoneLow, let hi = step.zoneHigh {
                            let r = ActZones.span(lo, hi, model)
                            Text("\(step.zoneText ?? "") · \(Int(r.lowerBound))–\(Int(r.upperBound)) lpm")
                                .dsFont(15).foregroundStyle(DS.t2).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(LiveView.duration(TimeInterval(pos.remaining)))
                        .dsFont(60, .semibold, relativeTo: .largeTitle, maxScale: 1.15).foregroundStyle(DS.t1)
                        .contentTransition(.numericText())
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.fill)
                        Capsule().fill(DS.act)
                            .frame(width: max(6, g.size.width * CGFloat(pos.elapsed) / CGFloat(max(1, step.seconds))))
                    }
                }
                .frame(height: 6)
                DSDivider().padding(.vertical, 4)
                timeline(now: now)
            }
            .dsCard(padding: 14)
        }
    }

    private func header(_ i: Int) -> String {
        let works = plan.steps.indices.filter { plan.steps[$0].kind == .work }
        let step = plan.steps[i]
        if step.kind == .work || step.kind == .recover, let k = works.lastIndex(where: { $0 <= i }) {
            return "Serie \(k + 1) de \(works.count)"
        }
        return "Paso \(i + 1) de \(plan.steps.count)"
    }

    private func color(_ k: IntervalStep.Kind) -> Color {
        switch k {
        case .work: return DS.act
        case .recover: return DS.zone(1)
        case .warmup, .cooldown: return DS.fill2
        }
    }

    private func timeline(now: Int) -> some View {
        let total = Double(max(plan.totalSeconds, 1))
        let elapsed = Double(min(max(0, now - runner.start), plan.totalSeconds))
        return VStack(spacing: 6) {
            GeometryReader { g in
                let gap: CGFloat = 3
                let usable = g.size.width - gap * CGFloat(plan.steps.count - 1)
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(plan.steps.indices, id: \.self) { i in
                            let s = plan.steps[i]
                            let startAt = plan.steps.prefix(i).reduce(0) { $0 + $1.seconds }
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(color(s.kind).opacity(Double(startAt) > elapsed ? 0.4 : 1))
                                .frame(width: max(2, usable * CGFloat(Double(s.seconds) / total)))
                        }
                    }
                    Capsule().fill(DS.t1).frame(width: 2, height: 34)
                        .offset(x: g.size.width * CGFloat(elapsed / total) - 1)
                }
                .frame(height: 22)
            }
            .frame(height: 22)
            HStack {
                Text("0:00").foregroundStyle(DS.t3)
                Spacer()
                Text("Ahora").fontWeight(.semibold).foregroundStyle(DS.t1)
                Spacer()
                Text(LiveView.duration(total)).foregroundStyle(DS.t3)
            }
            .dsFont(13, relativeTo: .footnote)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plan de \(plan.steps.count) pasos")
    }
}
