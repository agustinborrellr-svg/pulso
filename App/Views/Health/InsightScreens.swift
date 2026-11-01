import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoIntelligence
import PulsoFeatures
import PulsoIntegrations

// MARK: - Behaviours

/// «Información sobre comportamientos»: what helps and what hurts your recovery, and what still needs days.
struct BehaviorsView: View {
    @EnvironmentObject var model: AppModel
    @State private var report: Behaviors.Report?

    var body: some View {
        DetailScreen(title: "Comportamientos") {
            if let r = report {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Análisis del impacto en tu recuperación").scaledFont(22, weight: .semibold).foregroundStyle(.white)
                    Text("Cuánto cambia tu recuperación los días con cada comportamiento frente a los días sin él. Pulso detecta algunos solo; el resto sale de tu diario.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
                if r.impact.isEmpty {
                    PCard {
                        Text("Aún no hay ningún comportamiento con 5 días con y 5 sin. Sigue llevando la pulsera y apuntando el diario.")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                } else {
                    HStack {
                        Label("Afecta", systemImage: "arrowtriangle.down.square.fill").foregroundStyle(Theme.worse)
                        Spacer()
                        Caps("% del impacto", size: 11, color: .white)
                        Spacer()
                        Label("Ayuda", systemImage: "arrowtriangle.up.square.fill").foregroundStyle(Theme.better)
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                    .font(.caption.weight(.bold))
                    let scale = max(10, r.impact.map { abs($0.impactPct ?? 0) }.max() ?? 10)
                    ForEach(r.impact) { item in BehaviorImpactRow(item: item, scale: scale) }
                }
                if !r.locked.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Caps("Sigue registrando para desbloquear", size: 13)
                        Text("Cada comportamiento se desbloquea con al menos \(Behaviors.minEach) días con él y \(Behaviors.minEach) sin él.")
                            .font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                    .padding(.top, 10)
                    ForEach(r.locked) { item in BehaviorLockedRow(item: item) }
                }
                ExplainerCard(title: "Cómo se calcula",
                              text: "Para cada comportamiento se comparan las recuperaciones de los días con él y sin él (los del diario y el ejercicio cuentan para el día siguiente; los del sueño, para ese mismo día). El porcentaje es la diferencia respecto a los días sin él. Los automáticos usan tu propia mediana como corte para que los dos grupos se llenen. Son asociaciones con tus datos, no causas.")
            } else {
                PulseLoader(phase: .running(progress: nil))
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task { report = model.behaviorReport() }
    }
}

private struct BehaviorImpactRow: View {
    let item: Behaviors.Item
    let scale: Double

    var body: some View {
        let p = item.impactPct ?? 0
        let color: Color = item.helps == true ? Theme.better : item.helps == false ? Theme.worse : Color(white: 0.55)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(item.label).font(.headline).foregroundStyle(.white).lineLimit(2)
                if item.automatic {
                    Image(systemName: "sparkles").font(.caption).foregroundStyle(Theme.link)
                        .padding(5).background(Theme.link.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Detectado por Pulso")
                }
                Spacer()
            }
            HStack(spacing: 12) {
                GeometryReader { g in
                    let mid = g.size.width / 2
                    let w = min(mid, mid * abs(p) / scale)
                    ZStack(alignment: .leading) {
                        Hatch().fill(Color.white.opacity(0.10)).frame(height: 14)
                        Capsule().fill(color).frame(width: max(w, 2), height: 14)
                            .offset(x: p >= 0 ? mid : mid - w)
                        Circle().fill(.black).frame(width: 14, height: 14)
                            .overlay(Circle().fill(.white).frame(width: 5, height: 5))
                            .offset(x: mid - 7)
                    }
                }
                .frame(height: 14)
                Text((p >= 0 ? "+" : "−") + "\(Int(abs(p).rounded())) %")
                    .font(.headline.monospacedDigit()).foregroundStyle(color)
                    .frame(minWidth: 56, alignment: .trailing)
            }
            if let a = item.withMean, let b = item.withoutMean {
                Text("Con: \(Int(a.rounded())) % · sin: \(Int(b.rounded())) % · \(item.yes) y \(item.no) días")
                    .font(.caption).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct BehaviorLockedRow: View {
    let item: Behaviors.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.label).font(.headline).foregroundStyle(.white).lineLimit(2)
            HStack(spacing: 12) {
                ZStack {
                    Hatch().fill(Color.white.opacity(0.10)).frame(height: 14)
                    Circle().fill(.black).frame(width: 14, height: 14).overlay(Circle().fill(.white).frame(width: 5, height: 5))
                }
                count("xmark", item.no)
                count("checkmark", item.yes)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1.5))
    }

    private func count(_ icon: String, _ n: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2.bold())
                .frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.6), lineWidth: 1.2))
            Text("\(n)").font(.subheadline.monospacedDigit()).frame(minWidth: 14, alignment: .leading)
        }
        .foregroundStyle(n >= Behaviors.minEach ? Theme.better : Color.white.opacity(0.8))
        .accessibilityLabel(icon == "xmark" ? "\(n) días sin" : "\(n) días con")
    }
}

// MARK: - Period averages (trend view)

/// The daily line with each month's average drawn over it and the change from the month before.
struct PeriodAveragesChart: View {
    let metric: TrendMetric
    let days: [DaySummary]

    var body: some View {
        let pts = days.compactMap { d in metric.value(d).map { (day: d.day, value: $0) } }
        let segs = PeriodAverages.segments(pts)
        if segs.count >= 2 {
            PCard {
                CardHeader(title: "Media por mes", subtitle: "Y su cambio frente al mes anterior")
                Chart {
                    ForEach(pts, id: \.day) { p in
                        LineMark(x: .value("Día", DayKey.date(p.day) ?? Date()), y: .value(metric.title, p.value), series: .value("s", "día"))
                            .foregroundStyle(Color.white.opacity(0.18))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    ForEach(segs) { s in
                        let color = changeColor(s)
                        RuleMark(xStart: .value("de", DayKey.date(s.start) ?? Date()), xEnd: .value("a", DayKey.date(s.end) ?? Date()),
                                 y: .value("media", s.mean))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .annotation(position: .top, alignment: .leading, spacing: 4) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(metric.format(s.mean)).font(.caption.bold().monospacedDigit()).foregroundStyle(.white)
                                    if let c = s.changePct {
                                        Text((c >= 0 ? "+" : "−") + "\(Int(abs(c).rounded())) %").font(.caption2.bold()).foregroundStyle(color)
                                    }
                                }
                            }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { v in
                        AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private func changeColor(_ s: PeriodAverages.Segment) -> Color {
        guard let c = s.changePct, abs(c) >= 3, let hib = metric.higherIsBetter else { return .white }
        return (c > 0) == hib ? Theme.better : Theme.worse
    }
}

// MARK: - Menstrual cycle calendar

struct CycleCalendarView: View {
    @EnvironmentObject var model: AppModel
    @State private var month = String(DayKey.string(Date()).prefix(7))
    @State private var logging = false
    @State private var logDate = Date()

    var body: some View {
        let estimate = CycleTracker.estimate(model.days)
        let starts = model.cycleStarts + estimate.periodStarts
        let today = model.currentDayKey
        let map = CyclePhases.map(starts: starts, ovulations: estimate.ovulations, averageLength: estimate.averageCycleDays,
                                  through: MonthlyReport.shiftMonth(month, 1) + "-01", today: today)
        DetailScreen(title: "Ciclo menstrual") {
            if let t = map[today] {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Día \(t.cycleDay) del ciclo").scaledFont(26, weight: .bold).foregroundStyle(.white)
                        Text(t.phase.label).scaledFont(26, weight: .bold).foregroundStyle(Self.color(t.phase))
                    }
                    if let next = nextStart(map: map, after: today) {
                        Text("Próxima regla en unos \(next) días").font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                }
            } else {
                Text("Registra el primer día de tu regla para ver el calendario por fases.")
                    .font(.subheadline).foregroundStyle(Theme.secondary)
            }
            HStack {
                Button { month = MonthlyReport.shiftMonth(month, -1) } label: { Image(systemName: "chevron.left") }
                Caps(monthTitle, size: 14)
                Button { month = MonthlyReport.shiftMonth(month, 1) } label: { Image(systemName: "chevron.right") }
                Spacer()
            }
            .foregroundStyle(.white)
            grid(map: map, today: today)
            legend
            Button {
                logDate = Date()
                logging = true
            } label: {
                HStack {
                    Image(systemName: "drop").padding(8).overlay(Circle().stroke(Theme.hairline))
                    Caps("Registrar regla", size: 13)
                    Spacer()
                    Image(systemName: "plus").font(.headline).foregroundStyle(.black).padding(8).background(.white, in: Circle())
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            if !model.cycleStarts.isEmpty {
                PCard {
                    CardHeader(title: "Reglas registradas")
                    ForEach(model.cycleStarts.sorted().reversed(), id: \.self) { d in
                        HStack {
                            Text(Fmt.dayTitle(d)).foregroundStyle(.white)
                            Spacer()
                            Button(role: .destructive) { model.removeCycleStart(d) } label: { Image(systemName: "trash") }
                        }
                        .font(.subheadline)
                    }
                }
            }
            Text("Las fases se calculan con los días de regla que registras y con la subida de temperatura nocturna de la pulsera. Orientativo: no sirve como método anticonceptivo.")
                .font(.caption).foregroundStyle(Theme.tertiary)
        }
        .sheet(isPresented: $logging) {
            NavigationStack {
                Form {
                    DatePicker("Primer día de la regla", selection: $logDate, in: ...Date(), displayedComponents: .date)
                }
                .pulsoList()
                .pulsoTitle("Registrar regla")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { logging = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar") {
                            model.addCycleStart(DayKey.string(logDate))
                            logging = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }

    static func color(_ p: CyclePhases.Phase) -> Color {
        switch p {
        case .menstrual: return Color(red: 0.94, green: 0.45, blue: 0.40)
        case .follicular: return Color(red: 0.62, green: 0.60, blue: 0.86)
        case .ovulatory: return Color(red: 0.30, green: 0.55, blue: 0.70)
        case .luteal: return Color(red: 0.55, green: 0.33, blue: 0.80)
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: month) else { return month }
        f.dateFormat = "LLLL"
        return f.string(from: d)
    }

    private func nextStart(map: [String: CyclePhases.Day], after today: String) -> Int? {
        for i in 1...60 {
            let d = DayKey.shift(today, days: i)
            if map[d]?.cycleDay == 1 { return i }
        }
        return nil
    }

    private func grid(map: [String: CyclePhases.Day], today: String) -> some View {
        let first = DayKey.date(month + "-01") ?? Date()
        let cal = Calendar.current
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let offset = (cal.component(.weekday, from: first) + 5) % 7
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(["LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB", "DOM"], id: \.self) {
                    Text($0).font(.caption2.bold()).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 10) {
                ForEach(0..<(offset + count), id: \.self) { i in
                    if i < offset {
                        Color.clear.frame(height: 34)
                    } else {
                        let n = i - offset + 1
                        let key = String(format: "%@-%02d", month, n)
                        let d = map[key]
                        let prev = map[DayKey.shift(key, days: -1)], next = map[DayKey.shift(key, days: 1)]
                        let col = (i % 7)
                        let joinLeft = col > 0 && prev?.phase == d?.phase && d != nil && n > 1
                        let joinRight = col < 6 && next?.phase == d?.phase && d != nil && n < count
                        ZStack {
                            if let d {
                                UnevenRoundedRectangle(topLeadingRadius: joinLeft ? 0 : 17, bottomLeadingRadius: joinLeft ? 0 : 17,
                                                       bottomTrailingRadius: joinRight ? 0 : 17, topTrailingRadius: joinRight ? 0 : 17)
                                    .fill(Self.color(d.phase).opacity(d.predicted ? 0.35 : 0.85))
                                if d.phase == .menstrual {
                                    Circle().fill(Self.color(.menstrual)).frame(width: 30, height: 30)
                                }
                            }
                            if key == today {
                                Circle().stroke(.white, lineWidth: 2).frame(width: 36, height: 36)
                            }
                            Text("\(n)").font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(d == nil ? Theme.secondary : .white)
                        }
                        .frame(height: 34)
                    }
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(CyclePhases.Phase.allCases, id: \.self) { p in
                HStack(spacing: 5) {
                    Capsule().fill(Self.color(p)).frame(width: 18, height: 10)
                    Text(p.label).font(.caption).foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - Blood pressure

struct BloodPressureView: View {
    @EnvironmentObject var model: AppModel
    @State private var range = 7
    @State private var adding = false
    @State private var sys = 120
    @State private var dia = 80
    @State private var pulse = 70

    var body: some View {
        let readings = model.bloodPressure
        let avg = BloodPressure.average(readings, days: range)
        let from = Int(Date().timeIntervalSince1970) - range * 86400
        let daily = BloodPressure.daily(readings.filter { $0.ts >= from })
        DetailScreen(title: "Tensión arterial") {
            ZStack {
                Circle().trim(from: 0.12, to: 0.88)
                    .stroke(AngularGradient(colors: [Theme.green, Theme.yellow, Theme.stress], center: .center,
                                            startAngle: .degrees(130), endAngle: .degrees(410)),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .frame(width: 250, height: 250)
                if let avg {
                    let pos = min(1, max(0, (Double(avg.systolic) - 100) / 60))
                    Circle().fill(.white).frame(width: 18, height: 18)
                        .offset(y: -125)
                        .rotationEffect(.degrees(-133 + pos * 266))
                }
                VStack(spacing: 6) {
                    Caps(range == 7 ? "Media de la semana" : "Media del periodo", size: 11, color: Theme.secondary)
                    Text(avg.map { "\($0.systolic)/\($0.diastolic)" } ?? "–").scaledFont(44, weight: .bold).foregroundStyle(.white)
                    if let avg {
                        let c = BloodPressure.category(systolic: avg.systolic, diastolic: avg.diastolic)
                        Text(c.label).font(.subheadline.bold()).foregroundStyle(c <= .elevated ? Theme.green : c == .stage1 ? Theme.yellow : Theme.red)
                    } else {
                        Text("Sin lecturas").font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            Picker("Periodo", selection: $range) {
                Text("S").tag(7)
                Text("M").tag(30)
                Text("6M").tag(182)
            }
            .pickerStyle(.segmented)
            if daily.isEmpty {
                PCard {
                    Text("Mide tu tensión con un tensiómetro y apúntala aquí: Pulso te enseña la tendencia y te avisa si sube. La pulsera no tiene un sensor de tensión validado, así que no la inventa.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
            } else {
                Chart(daily) { d in
                    RectangleMark(x: .value("Día", d.day), yStart: .value("min", d.systolic.lowerBound - 2), yEnd: .value("max", d.systolic.upperBound + 2), width: .ratio(0.35))
                        .foregroundStyle(Color.white.opacity(0.12)).cornerRadius(6)
                    RectangleMark(x: .value("Día", d.day), yStart: .value("min", d.diastolic.lowerBound - 2), yEnd: .value("max", d.diastolic.upperBound + 2), width: .ratio(0.35))
                        .foregroundStyle(Color.white.opacity(0.12)).cornerRadius(6)
                    let s = (d.systolic.lowerBound + d.systolic.upperBound) / 2
                    let di = (d.diastolic.lowerBound + d.diastolic.upperBound) / 2
                    let c = BloodPressure.category(systolic: s, diastolic: di)
                    PointMark(x: .value("Día", d.day), y: .value("Sistólica", s))
                        .symbol(.square).symbolSize(70)
                        .foregroundStyle(c <= .elevated ? Theme.green : c == .stage1 ? Theme.yellow : Theme.red)
                    PointMark(x: .value("Día", d.day), y: .value("Diastólica", di))
                        .symbol(.square).symbolSize(70)
                        .foregroundStyle(c <= .elevated ? Theme.green : c == .stage1 ? Theme.yellow : Theme.red)
                }
                .chartXScale(domain: daily.map(\.day))
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel { Text(Fmt.weekdayAndDay(v.as(String.self) ?? "").0).font(.caption2).foregroundStyle(Theme.secondary) }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 240)
                PCard {
                    CardHeader(title: "Lecturas")
                    ForEach(readings.sorted { $0.ts > $1.ts }.prefix(20)) { r in
                        HStack {
                            Text(Date(timeIntervalSince1970: TimeInterval(r.ts)).formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                .font(.caption).foregroundStyle(Theme.secondary)
                            Spacer()
                            Text("\(r.systolic)/\(r.diastolic)").font(.headline.monospacedDigit()).foregroundStyle(.white)
                            if let p = r.pulse { Text("\(p) lpm").font(.caption).foregroundStyle(Theme.secondary) }
                            Button(role: .destructive) { model.removeBloodPressure(r) } label: { Image(systemName: "trash").font(.caption) }
                        }
                    }
                }
            }
            Button {
                adding = true
            } label: {
                Label("Añadir lectura", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryCapsuleStyle())
            Text("Categorías de la AHA (2017). Si la media pasa de 140/90 o una lectura de 180/120, consúltalo con tu médico.")
                .font(.caption).foregroundStyle(Theme.tertiary)
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    Stepper("Sistólica (alta): \(sys)", value: $sys, in: 70...250)
                    Stepper("Diastólica (baja): \(dia)", value: $dia, in: 40...150)
                    Stepper("Pulso: \(pulse) lpm", value: $pulse, in: 30...200)
                }
                .pulsoList()
                .pulsoTitle("Nueva lectura")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar") {
                            model.addBloodPressure(BloodPressureReading(ts: Int(Date().timeIntervalSince1970), systolic: sys, diastolic: dia, pulse: pulse))
                            adding = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Double tap

/// What a double tap on the strap does, with the extra actions (voice, scan, web call, Shortcut).
struct DoubleTapView: View {
    @EnvironmentObject var model: AppModel
    @State private var url = ""
    @State private var shortcut = ""
    @State private var testResult: String?

    var body: some View {
        Form {
            Section {
                Picker("Acción", selection: binding(\.doubleTap)) {
                    ForEach(DoubleTapAction.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Si está sonando una alarma, el doble toque siempre la pospone o la apaga. Pulso solo recibe el toque mientras está conectada a la pulsera (en primer o segundo plano).")
            }
            switch model.settings.doubleTap {
            case .toggleWorkout:
                Section {
                    Picker("Deporte", selection: binding(\.quickSport)) {
                        ForEach(SportCatalog.names, id: \.self) { Text($0).tag($0) }
                    }
                }
            case .webhook:
                Section {
                    TextField("https://…", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { save() }
                    Picker("Método", selection: binding(\.tapMethod)) {
                        ForEach(DoubleTapWebhook.Method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Button("Guardar y probar") {
                        save()
                        model.fireTapWebhook()
                        testResult = "Enviado: la pulsera vibra 1 vez si ha ido bien y 3 si ha fallado."
                    }
                    if let testResult { Text(testResult).font(.caption).foregroundStyle(Theme.secondary) }
                } header: {
                    Text("Dirección web")
                } footer: {
                    Text("Ideas: un webhook de Home Assistant para abrir la puerta o encender una luz, un applet de IFTTT, un aviso a tu móvil o al de alguien con ntfy o un bot de Telegram. Con POST se envía {\"event\":\"double_tap\", \"ts\", \"heart_rate\"}. La dirección se guarda solo en tu iPhone.")
                }
            case .shortcut:
                Section {
                    TextField("Nombre exacto del atajo", text: $shortcut)
                        .textInputAutocapitalization(.never)
                        .onSubmit { save() }
                    Button("Guardar y probar") {
                        save()
                        model.runTapShortcut()
                    }
                } header: {
                    Text("Atajo")
                } footer: {
                    Text("iOS solo deja ejecutar Atajos con la app delante: si Pulso está en segundo plano te llega un aviso y al tocarlo se ejecuta. Con un atajo puedes mandar un mensaje, abrir HomeKit, poner una escena…")
                }
            case .speakStatus:
                Section {
                    Button("Probar") { model.speakStatus() }
                } footer: {
                    Text("Te dice tu recuperación, el esfuerzo del día y tu pulso por los auriculares o el altavoz, sin sacar el móvil.")
                }
            case .scan:
                Section {} footer: {
                    Text("Un minuto quieto: la pulsera vibra al empezar y al terminar, y oyes el resultado. Se guarda en el historial de Escanear.")
                }
            default:
                EmptyView()
            }
            Section {
                LabeledContent("Último doble toque recibido") {
                    Text(model.lastDoubleTapAt.map { Fmt.relative($0) } ?? "ninguno aún")
                }
            } footer: {
                Text("Si tocas dos veces y aquí no cambia, tu pulsera no está mandando el gesto (todavía no está confirmado en la 5.0).")
            }
        }
        .pulsoList()
        .pulsoTitle("Doble toque")
        .onAppear {
            url = model.settings.tapURL
            shortcut = model.settings.tapShortcut
        }
        .onDisappear { save() }
    }

    private func save() {
        var s = model.settings
        s.tapURL = url
        s.tapShortcut = shortcut
        if s != model.settings { model.saveSettings(s) }
    }

    private func binding<T>(_ key: WritableKeyPath<FeatureSettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: key] }, set: { v in
            var s = model.settings
            s[keyPath: key] = v
            model.saveSettings(s)
        })
    }
}
