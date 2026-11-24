import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoFeatures

/// Tab «Sueño» (studio B-sueno 01, and 20 without a night): the night's score and factors, phases, timing, need,
/// night vitals, naps, tonight and the last 7 nights. Every row opens its route (`Routes+Sueno.swift`).
struct SleepTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    /// Screenshot runs only: draw the morning without a night (20).
    var previewEmpty = false
    @State private var adding = false
    @State private var addingNap = false
    @State private var editing: SleepSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.stack) {
                HoyHeader()
                if model.days.isEmpty {
                    DSEmptyState(icon: "moon.zzz", title: "Aún no hay noches",
                                 message: "Duerme con la pulsera y sincroniza por la mañana: aquí verás tu sueño.")
                        .padding(.top, 8)
                } else if let day = model.selected, !previewEmpty, let s = session(day) {
                    scoreCard(day, s)
                    phases(day, s)
                    timing(day)
                    need(day)
                    vitals(day, s)
                    naps
                    tonight
                    week(day)
                    adjustButton(day)
                } else {
                    missingNight
                    emptyScore
                    if let day = model.selected ?? model.days.last { week(day) }
                    tonight
                }
            }
            .padding(.horizontal, DS.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if model.showDayPicker {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.28)) { model.showDayPicker = false } }
                        .accessibilityLabel("Cerrar calendario")
                        .accessibilityAddTraits(.isButton)
                        .transition(.opacity)
                    HomeDayPicker()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .dsBackground()
        .refreshable {
            model.syncNow()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $adding) { SleepEditSheet(session: nil, forDay: model.selectedDay).environmentObject(model) }
        .sheet(isPresented: $addingNap) { SleepEditSheet(session: nil, napDefault: true).environmentObject(model) }
        .sheet(item: $editing) { SleepEditSheet(session: $0).environmentObject(model) }
    }

    private func session(_ day: DaySummary) -> SleepSession? {
        model.sleep(for: day) ?? HistoryMerge.summarySleep(day)
    }

    // MARK: Score + factors

    private func scoreCard(_ day: DaySummary, _ s: SleepSession) -> some View {
        let score = day.sleepPerformance.map { $0 * 100 }
        let prev = model.days.last { $0.day < day.day && $0.sleepPerformance != nil }
        let factors = SleepFactors.of(day)
        return VStack(spacing: 0) {
            RouteLink(.sueno(.noche(day: nil))) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(spacing: 2) {
                        ScoreArc(progress: (score ?? 0) / 100, color: DS.sueno, value: score.map { "\(Int($0.rounded()))" } ?? "–",
                                 size: 96, line: 8)
                            .padding(.bottom, 2)
                        Text("Sueño").dsFont(16, .semibold).foregroundStyle(DS.t1)
                        if let score {
                            let lv = DSLevel(score: score)
                            HStack(spacing: 5) {
                                HoyDot(color: lv.mark)
                                Text(lv.word).dsFont(14, .semibold).foregroundStyle(lv.ink)
                            }
                        }
                        if let p = prev?.sleepPerformance {
                            Text("ayer \(Int((p * 100).rounded()))").dsFont(13).foregroundStyle(DS.t3)
                        }
                    }
                    .frame(width: 118)
                    Rectangle().fill(DS.sep).frame(width: 0.5, height: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dormido").dsFont(13).foregroundStyle(DS.t2)
                        hoursValue(day.sleepMinutes ?? s.asleepMinutes, size: 34)
                        HStack(spacing: 8) {
                            Image(systemName: "moon.fill").font(.system(size: 11)).foregroundStyle(DS.sueno)
                            Text(SFmt.clock(s.start))
                            Rectangle().fill(DS.t3).frame(width: 14, height: 1)
                            Image(systemName: "sun.max").font(.system(size: 11)).foregroundStyle(DS.t2)
                            Text(SFmt.clock(s.end))
                        }
                        .dsFont(15, .semibold).foregroundStyle(DS.t1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            ForEach(factors) { f in
                DSDivider()
                RouteLink(.metric(factorKind(f.key))) {
                    HStack(spacing: 10) {
                        Text(factorLabel(f)).dsFont(16).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        DSMeter(SuenoLevel.factor(f))
                        Text("\(Int(f.value.rounded())) %").dsFont(16, .semibold).foregroundStyle(DS.t1)
                            .frame(minWidth: 48, alignment: .trailing)
                        DSChevron()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
            }
        }
        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(DS.hair, lineWidth: 0.5))
        .padding(.top, 4)
    }

    private func factorKind(_ key: String) -> MetricKind {
        switch key {
        case "hoursVsNeed": return .necesidadSueno
        case "regularity": return .regularidad
        case "efficiency": return .eficiencia
        default: return .reparador
        }
    }

    private func factorLabel(_ f: SleepFactors.Factor) -> String {
        switch f.key {
        case "regularity": return "Regularidad"
        case "efficiency": return "Eficiencia"
        default: return f.label
        }
    }

    /// "7 h 12 min" with small units.
    private func hoursValue(_ minutes: Double, size: CGFloat) -> some View {
        let m = Int(minutes.rounded())
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            if m >= 60 {
                Text("\(m / 60)").dsFont(size, .semibold).foregroundStyle(DS.t1)
                Text("h").dsFont(size * 0.5, .medium).foregroundStyle(DS.t2).padding(.trailing, 4)
            }
            Text(m >= 60 ? String(format: "%02d", m % 60) : "\(m)").dsFont(size, .semibold).foregroundStyle(DS.t1)
            Text("min").dsFont(size * 0.5, .medium).foregroundStyle(DS.t2)
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    // MARK: Phases

    @ViewBuilder
    private func phases(_ day: DaySummary, _ s: SleepSession) -> some View {
        let parts: [(SleepStage, Double)] = [(.deep, day.deepMinutes ?? s.minutesDeep), (.rem, day.remMinutes ?? s.minutesREM),
                                             (.light, day.lightMinutes ?? s.minutesLight), (.awake, day.awakeMinutes ?? s.minutesAwake)]
        if parts.contains(where: { $0.1 > 0 }) {
            RouteLink(.sueno(.noche(day: nil))) { DSSectionHeader("Fases", chevron: true) }
            VStack(alignment: .leading, spacing: 14) {
                if !s.stages.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        StageCurve(session: s).frame(height: 128)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach([SleepStage.awake, .rem, .light, .deep], id: \.self) { st in
                                HStack(spacing: 5) {
                                    HoyDot(color: st == .awake ? DS.t3 : DS.stage(st))
                                    Text(Theme.stageName(st)).dsFont(11, .medium, relativeTo: .caption2).foregroundStyle(DS.t2)
                                }
                                .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(height: 104)
                        .padding(.top, 2)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    ForEach(parts, id: \.0) { st, m in
                        RouteLink(.metric(.fase(st))) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    HoyDot(color: st == .awake ? DS.t3 : DS.stage(st))
                                    Text(Theme.stageName(st)).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                }
                                let p = DSFmt.durationParts(m)
                                HoyValue(value: p.0, unit: p.1, size: 18)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .dsCard(padding: 16)
        }
    }

    // MARK: Timing

    @ViewBuilder
    private func timing(_ day: DaySummary) -> some View {
        let bed = SuenoClock.window(model, evening: true, before: day.day)
        let wake = SuenoClock.window(model, evening: false, before: day.day)
        if let a = day.sleepStart, let b = day.sleepEnd, bed != nil || wake != nil {
            RouteLink(.metric(.regularidad)) { DSSectionHeader("Horario", chevron: true) }
            VStack(spacing: 16) {
                if let bed { SuenoTimingRow(title: "Te acostaste", actual: SuenoClock.minutes(a, evening: true), window: bed) }
                if let wake { SuenoTimingRow(title: "Te levantaste", actual: SuenoClock.minutes(b, evening: false), window: wake) }
            }
            .dsCard(padding: 16)
        }
    }

    // MARK: Need

    @ViewBuilder
    private func need(_ day: DaySummary) -> some View {
        if let need = day.sleepNeedMinutes, need > 0, let slept = day.sleepMinutes {
            let short = need - slept
            RouteLink(.metric(.necesidadSueno)) { DSSectionHeader("Necesidad", chevron: true) }
            RouteLink(.metric(.necesidadSueno)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Necesitabas").dsFont(13).foregroundStyle(DS.t2)
                            hoursValue(need, size: 26)
                        }
                        Spacer()
                        if let debt = day.sleepDebtMinutes {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Deuda de sueño").dsFont(13).foregroundStyle(DS.t2)
                                let p = DSFmt.durationParts(debt)
                                HoyValue(value: p.0, unit: p.1, size: 22)
                            }
                        }
                    }
                    GeometryReader { g in
                        let scale = g.size.width / max(need, slept, 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.fill).frame(height: 8)
                            if short > 0 {
                                Capsule().fill(DSLevel.justa.mark).frame(width: need * scale, height: 8)
                            }
                            Capsule().fill(DS.sueno).frame(width: max(8, min(slept, need) * scale), height: 8)
                            if short <= 0 {
                                Rectangle().fill(DS.t1).frame(width: 2, height: 16).offset(x: need * scale - 1)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                    HStack {
                        Text(short > 0 ? "te faltaron \(DSFmt.duration(short))" : (short < -1 ? "dormiste \(DSFmt.duration(-short)) de más" : "lo justo"))
                            .dsFont(13, .semibold).foregroundStyle(short > 0 ? DSLevel.justa.ink : DSLevel.buena.ink)
                        Spacer()
                        Text("necesitabas").dsFont(12).foregroundStyle(DS.t3)
                    }
                }
                .dsCard(padding: 16)
            }
        }
    }

    // MARK: Night vitals

    @ViewBuilder
    private func vitals(_ day: DaySummary, _ s: SleepSession) -> some View {
        let rows = vitalRows(day, s)
        if !rows.isEmpty {
            DSSectionHeader("Constantes de la noche")
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    if i > 0 { DSDivider(inset: 48) }
                    let r = rows[i]
                    RouteLink(.metric(r.kind)) {
                        HStack(spacing: 12) {
                            Image(systemName: r.icon).font(.system(size: 15)).foregroundStyle(r.color).frame(width: 22)
                            Text(r.label).dsFont(16).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 6)
                            if let n = r.normal { SuenoMiniRange(value: r.value, normal: n, color: r.color) }
                            HoyValue(value: r.text, unit: r.unit, size: 18)
                                .frame(minWidth: 70, alignment: .trailing)
                            DSChevron()
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                }
            }
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(DS.hair, lineWidth: 0.5))
        }
    }

    private struct VitalRow {
        let icon: String
        let color: Color
        let label: String
        let value: Double
        let text: String
        let unit: String
        let normal: ClosedRange<Double>?
        let kind: MetricKind
    }

    private func vitalRows(_ day: DaySummary, _ s: SleepSession) -> [VitalRow] {
        var out: [VitalRow] = []
        func dec(_ v: Double, _ p: Int = 1) -> String { String(format: "%.\(p)f", v).replacingOccurrences(of: ".", with: ",") }
        if let v = s.hrv ?? day.hrv {
            out.append(VitalRow(icon: "waveform.path.ecg", color: DS.cor, label: "VFC", value: v, text: "\(Int(v.rounded()))", unit: "ms",
                                normal: SuenoSpec.normal(model, before: day.day) { $0.hrv }, kind: .hrv))
        }
        if let v = s.rhr ?? day.rhr {
            out.append(VitalRow(icon: "heart.fill", color: DS.cor, label: "FC en reposo", value: v, text: "\(Int(v.rounded()))", unit: "lpm",
                                normal: SuenoSpec.normal(model, before: day.day) { $0.rhr }, kind: .rhr))
        }
        if let v = s.respRate ?? day.respRate {
            out.append(VitalRow(icon: "lungs.fill", color: DS.cons, label: "Respiración", value: v, text: dec(v), unit: "rpm",
                                normal: SuenoSpec.normal(model, before: day.day) { $0.respRate }, kind: .resp))
        }
        if let v = s.spo2 ?? day.spo2 {
            out.append(VitalRow(icon: "drop.fill", color: DS.cons, label: "SpO₂", value: v, text: "\(Int(v.rounded()))", unit: "%",
                                normal: SuenoSpec.normal(model, before: day.day) { $0.spo2 }, kind: .spo2))
        }
        if let v = day.skinTempDeviation {
            out.append(VitalRow(icon: "thermometer.medium", color: DS.cons, label: "Temp. piel", value: v,
                                text: (v >= 0 ? "+" : "−") + dec(abs(v)), unit: "°C",
                                normal: SuenoSpec.normal(model, before: day.day) { $0.skinTempDeviation }, kind: .temp))
        } else if let v = s.skinTemp ?? day.skinTemp {
            out.append(VitalRow(icon: "thermometer.medium", color: DS.cons, label: "Temp. piel", value: v, text: dec(v), unit: "°C",
                                normal: SuenoSpec.normal(model, before: day.day) { $0.skinTemp }, kind: .temp))
        }
        if model.sleep(for: day) != nil {
            out.append(VitalRow(icon: "hourglass", color: DS.sueno, label: "Latencia", value: s.latencyMinutes,
                                text: "\(Int(s.latencyMinutes.rounded()))", unit: "min", normal: nil, kind: .latencia))
        }
        return out
    }

    // MARK: Naps

    private var naps: some View {
        let list = model.daytimeSleeps(on: model.selectedDay)
        return VStack(alignment: .leading, spacing: DS.stack) {
            RouteLink(.sueno(.siestas)) { DSSectionHeader("Siestas", chevron: true) }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(list) { n in
                    RouteLink(.sueno(.siestas)) { SuenoNapRow(nap: n) }
                    DSDivider()
                }
                Button { addingNap = true } label: {
                    Label("Añadir siesta", systemImage: "plus").dsFont(16, .semibold).foregroundStyle(DS.sueno)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .dsCard(padding: 16)
        }
    }

    // MARK: Tonight

    @ViewBuilder
    private var tonight: some View {
        let plan = model.tonightPlan
        let alarm = model.nextAlarm
        if plan != nil || alarm != nil {
            RouteLink(.sueno(.alarmas)) { DSSectionHeader("Esta noche", chevron: true) }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 0) {
                    if let plan {
                        RouteLink(.sueno(.meVoyADormir)) {
                            half(icon: "bed.double.fill", title: "Acuéstate", value: Fmt.clock(plan.bedtime))
                        }
                    }
                    if plan != nil, alarm != nil {
                        Rectangle().fill(DS.sep).frame(width: 0.5, height: 44).padding(.horizontal, 14)
                    }
                    if let a = alarm {
                        RouteLink(.sueno(.alarmas)) {
                            half(icon: "alarm", title: "Despertador",
                                 value: a.isSmart ? "\(Fmt.clock(a.earliest)) – \(Fmt.clock(a.latest))" : Fmt.clock(a.latest))
                        }
                    }
                }
                if let plan, model.selected.flatMap({ session($0) }) != nil, !previewEmpty {
                    DSDivider()
                    HStack {
                        Text("Necesitas esta noche").dsFont(16).foregroundStyle(DS.t1)
                        Spacer()
                        Text(DSFmt.duration(plan.needMinutes)).dsFont(16, .semibold).foregroundStyle(DS.t1)
                    }
                    Button { router.open(.sueno(.meVoyADormir)) } label: {
                        Label("Me voy a dormir", systemImage: "moon.fill")
                    }
                    .buttonStyle(DSButtonStyle(tint: DS.sueno, fullWidth: true))
                }
            }
            .dsCard(padding: 16)
        }
    }

    private func half(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(DS.sueno)
                Text(title).dsFont(14, relativeTo: .footnote).foregroundStyle(DS.t2)
            }
            Text(value).dsFont(24, .semibold, relativeTo: .title2).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Week

    @ViewBuilder
    private func week(_ day: DaySummary) -> some View {
        let keys = (0..<7).map { DayKey.shift(day.day, days: $0 - 6) }
        let bars = keys.map { k in SuenoNightBars.Bar(day: k, minutes: previewEmpty && k == day.day ? nil : model.day(k)?.sleepMinutes) }
        let vals = bars.compactMap(\.minutes)
        if !vals.isEmpty {
            let normal = SuenoSpec.normal(model, before: day.day) { $0.sleepMinutes }
            RouteLink(.sueno(.historial)) { DSSectionHeader("Últimas 7 noches", chevron: true) }
            RouteLink(.sueno(.historial)) {
                VStack(alignment: .leading, spacing: 12) {
                    if let n = normal {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(DS.sueno.opacity(0.30))
                                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(DS.sueno.opacity(DS.edgeOpacity), lineWidth: 0.5))
                                .frame(width: 14, height: 9)
                            Text("Tu normal \(DSFmt.duration(n.lowerBound)) – \(DSFmt.duration(n.upperBound))")
                                .dsFont(13).foregroundStyle(DS.t2)
                        }
                    }
                    SuenoNightBars(bars: bars, normal: normal, highlight: day.day, height: 140)
                    if !previewEmpty {
                        DSDivider()
                        DSStatStrip(stats: weekStats(vals, normal: normal))
                    }
                }
                .dsCard(padding: 16)
            }
        }
    }

    private func weekStats(_ vals: [Double], normal: ClosedRange<Double>?) -> [DSStat] {
        var out = [DSStat(label: "Media", value: DSFmt.duration(vals.reduce(0, +) / Double(vals.count)))]
        if let n = normal {
            out.append(DSStat(label: "En tu normal", value: "\(vals.filter { n.contains($0) }.count)", unit: "de \(vals.count) noches"))
        }
        if let hi = vals.max() { out.append(DSStat(label: "Más larga", value: DSFmt.duration(hi))) }
        return out
    }

    @ViewBuilder
    private func adjustButton(_ day: DaySummary) -> some View {
        if let s = model.sleep(for: day) {
            Button { editing = s } label: {
                Label("Ajustar horas de sueño", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(DSButtonStyle(size: .small, gray: true))
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
        }
    }

    // MARK: Without a night (20)

    private var missingNight: some View {
        let pending = model.selectedDay >= model.currentDayKey && model.nightStatus == .awaitingData
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "moon.fill").font(.system(size: 18)).foregroundStyle(DS.sueno).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pending ? "Tu noche aún no está descargada" : "No encuentro tu noche")
                        .dsFont(18, .semibold).foregroundStyle(DS.t1)
                    Text(pending ? "La pulsera tiene la noche guardada: sincroniza para verla."
                                 : "No hay ningún sueño principal en este día. Si dormiste, añade las horas.")
                        .dsFont(14).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button { adding = true } label: { Label("Añadir sueño", systemImage: "plus").frame(maxWidth: .infinity) }
                    .buttonStyle(DSButtonStyle(tint: DS.sueno, size: .small, fullWidth: true))
                Button { model.syncNow() } label: { Text(pending ? "Sincronizar ahora" : "Sincronizar").frame(maxWidth: .infinity) }
                    .buttonStyle(DSButtonStyle(size: .small, gray: true, fullWidth: true))
                    .disabled(!model.strapState.isConnected)
            }
        }
        .dsCard(padding: 16)
        .padding(.top, 4)
    }

    private var emptyScore: some View {
        HStack(spacing: 18) {
            ScoreArc(progress: 0, color: DS.sueno, value: "", size: 96, line: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text("Sin calificación").dsFont(20, .semibold).foregroundStyle(DS.t2)
                Text("Se calcula al tener tu noche").dsFont(14).foregroundStyle(DS.t3)
            }
            Spacer(minLength: 0)
        }
        .dsCard(padding: 16)
    }
}
