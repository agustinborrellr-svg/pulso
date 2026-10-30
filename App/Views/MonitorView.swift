import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// Everything the band gives right now or gave last night, each value with when and how it was measured.
struct MonitorView: View {
    @EnvironmentObject var model: AppModel
    @State private var period: HRPeriod = .hour
    @State private var series: HRHistory.Series?
    @State private var activity: ActivityReading?
    @State private var spotStress: Double?
    @State private var spotStressAt: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                LiveRunBanner()
                currentHR
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(tiles) { MonitorTileView(tile: $0) }
                }
                chartCard
                Text("Noche = calculado por Pulso con los datos por segundo de tu sueño. Puntual = medido con el pulso en directo (escaneo de 60 s). Lo que no se mide en tiempo real no se muestra como si lo fuera.")
                    .font(.caption2).foregroundStyle(Theme.tertiary)
            }
            .padding(16)
        }
        .background(PulsoBackground())
        .pulsoTitle("Monitor")
        .onAppear { model.setLive(true, client: "monitor") }
        .onDisappear { model.setLive(false, client: "monitor") }
        .task(id: period) {
            // Short periods move with the live stream; long ones barely change.
            let every: UInt64 = period.seconds <= 7200 ? 15 : 120
            series = nil
            while !Task.isCancelled {
                let s = await model.hrHistory(period)
                guard !Task.isCancelled else { break }
                series = s
                try? await Task.sleep(nanoseconds: every * 1_000_000_000)
            }
        }
        .task {
            while !Task.isCancelled {
                activity = await model.latestActivity()
                refreshSpotStress()
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func refreshSpotStress() {
        guard model.liveToolBlocker == nil,
              let s = LiveMetrics.scan(model.beats(since: Date().addingTimeInterval(-90)), baseline: model.liveBaseline)?.stress else { return }
        spotStress = s
        spotStressAt = Date()
    }

    // MARK: Current HR

    private var currentHR: some View {
        PCard {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let age = model.lastLiveAt.map { ctx.date.timeIntervalSince($0) }
                let fresh = model.liveToolBlocker == nil
                HStack(spacing: 14) {
                    BeatingHeart(bpm: fresh ? model.liveHR : nil, color: fresh ? Theme.red : Theme.secondary)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Caps("Frecuencia cardiaca", size: 11, color: Theme.secondary, weight: .semibold)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(fresh ? model.liveHR.map(String.init) ?? "--" : "--")
                                .scaledFont(48, weight: .bold, design: .rounded, relativeTo: .largeTitle, maxScale: 1.3).monospacedDigit()
                                .foregroundStyle(fresh ? .white : Theme.secondary)
                            Text("lpm").foregroundStyle(Theme.secondary)
                        }
                        if fresh {
                            Text("Ahora · pulsera en directo").font(.caption).foregroundStyle(Theme.secondary)
                        } else if let age, let last = model.lastLiveAt {
                            Text("Sin señal: última lectura a las \(Fmt.clock(last)) (hace \(Self.ago(age)))")
                                .font(.caption).foregroundStyle(Theme.yellow)
                        } else if let why = model.liveToolBlocker {
                            Text(why).font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    static func ago(_ s: TimeInterval) -> String {
        if s < 90 { return "\(Int(s)) s" }
        if s < 5400 { return "\(Int(s / 60)) min" }
        return "\(Int(s / 3600)) h"
    }

    // MARK: Tiles

    private var tiles: [MonitorTile] {
        var out: [MonitorTile] = []
        let fresh = model.liveToolBlocker == nil
        let scan = model.latestScan

        out.append(nightTile("rhr", "FC en reposo", \.rhr, unit: "lpm", color: Theme.red, format: Fmt.int))

        var hrv = nightTile("hrv", "VFC", \.hrv, unit: "ms", color: Theme.hrv, format: Fmt.int)
        if fresh, let r = model.liveRMSSD {
            hrv.addSpot(Fmt.int(r), when: "Ahora (último minuto)")
        } else if let s = scan, let r = s.rmssd {
            hrv.addSpot(Fmt.int(r), when: "Escaneo \(when(s.date))")
        }
        out.append(hrv)

        var resp = nightTile("resp", "Respiración", \.respRate, unit: "rpm", color: Theme.link, format: { Fmt.dec($0) })
        if let s = scan, let r = s.resp {
            resp.addSpot(Fmt.dec(r), when: "Escaneo \(when(s.date))")
        }
        resp.extra.append("No se mide en tiempo real: usa Escanear para un valor puntual.")
        out.append(resp)

        var spo2 = nightTile("spo2", "SpO₂", \.spo2, unit: "%", color: Theme.sleep, format: Fmt.int)
        spo2.badge = "Experimental"
        spo2.extra.append("Lectura de la pulsera sin validar: orientativa.")
        out.append(spo2)

        var temp = nightTile("temp", "Temp. piel", \.skinTemp, unit: "°C", color: Theme.stress, format: { Fmt.dec($0) })
        if let d = model.latestDay(with: \.skinTempDeviation), d.day.day == model.latestDay(with: \.skinTemp)?.day.day {
            temp.extra.insert("\(d.value >= 0 ? "+" : "−")\(Fmt.dec(abs(d.value))) °C frente a tu normal", at: 0)
        }
        out.append(temp)

        out.append(stressTile())
        out.append(activityTile())

        var rec = nightTile("rec", "Recuperación", \.recovery, unit: "%", color: Theme.recoveryColor(model.today?.recovery), format: Fmt.int)
        if let d = model.latestDay(with: \.recovery)?.day, d.calibrating { rec.badge = "Calibrando" }
        rec.color = Theme.recoveryColor(model.latestDay(with: \.recovery)?.value)
        out.append(rec)
        return out
    }

    private func when(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "a las \(Fmt.clock(d))" : d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// A value computed from last night's sleep (or the newest night that has it, flagged as old).
    private func nightTile(_ id: String, _ title: String, _ key: KeyPath<DaySummary, Double?>, unit: String, color: Color,
                           format: (Double?) -> String) -> MonitorTile {
        var t = MonitorTile(id: id, title: title, unit: unit, color: color)
        guard let (v, d) = model.latestDay(with: key) else {
            t.state = .absent(model.days.isEmpty ? "Aún no hay noches analizadas: sincroniza la pulsera tras dormir." : "Sin dato en tus noches recientes.")
            return t
        }
        t.value = format(v)
        let isCurrent = d.day == model.currentDayKey
        let end = d.sleepEnd.map { " · despertar \(Fmt.time($0))" } ?? ""
        t.when = isCurrent ? "Anoche\(end)" : "Noche del \(Fmt.dayTitle(d.day).lowercased())\(end)"
        t.source = d.source == "strap" ? "Noche · calculado por Pulso" : "Importado"
        t.state = isCurrent ? .fresh : .stale("No es de la última noche: aún no está descargada o analizada.")
        return t
    }

    private func stressTile() -> MonitorTile {
        var t = MonitorTile(id: "stress", title: "Estrés", unit: "/ 3", color: Theme.stress)
        if let s = spotStress, let at = spotStressAt, Date().timeIntervalSince(at) < 120 {
            t.value = Fmt.dec(s)
            t.color = Theme.stressColor(s)
            t.when = "Ahora · último minuto y medio"
            t.source = "Pulso en directo frente a tu calma"
            t.state = .fresh
        }
        if let d = model.today, d.stressHourly.count == 24 {
            let order = (0..<24).map { (d.cycleStartHour + $0) % 24 }
            if let h = order.last(where: { d.stressHourly[$0] != nil }), let v = d.stressHourly[h] {
                let line = "Media de \(String(format: "%02d", h)):00–\(String(format: "%02d", (h + 1) % 24)):00: \(Fmt.dec(v)) (\(Theme.stressLevel(v).lowercased()))"
                if t.value == nil {
                    t.value = Fmt.dec(v)
                    t.color = Theme.stressColor(v)
                    t.when = "Ciclo actual, \(String(format: "%02d", h)):00–\(String(format: "%02d", (h + 1) % 24)):00"
                    t.source = "Datos de la pulsera · calculado por Pulso"
                    t.state = .fresh
                } else {
                    t.extra.append(line)
                }
            }
        }
        if t.value == nil {
            let calibrated = model.days.filter { $0.source == "strap" && $0.calmHR != nil }.count
            t.state = .absent(calibrated < Stress.minBaselineDays + 1
                ? "Calibrando: hacen falta \(Stress.minBaselineDays + 1) días con la pulsera para saber cómo es tu calma (llevas \(calibrated))."
                : "Sin datos de hoy todavía. Con pulso en directo se calcula al momento.")
        }
        return t
    }

    private func activityTile() -> MonitorTile {
        var t = MonitorTile(id: "act", title: "Actividad", unit: "", color: Theme.strain)
        guard let a = activity else {
            t.state = .absent("Sin datos de las últimas 12 h. Llegan al sincronizar; el pulso en directo no lo trae.")
            return t
        }
        if a.off {
            t.value = "Quitada"
        } else if a.sleepState == 2 {
            t.value = "Dormido"
        } else {
            switch a.activity {
            case 0?: t.value = "Quieto"
            case 1?: t.value = "Andando"
            case 2?: t.value = "Activo"
            case let n?: t.value = "Clase \(n)"
            case nil: t.value = "Despierto"
            }
        }
        let at = Date(timeIntervalSince1970: TimeInterval(a.ts))
        t.when = "Medido \(when(at))"
        t.source = "Clasificación de la pulsera (códigos sin confirmar)"
        t.state = Date().timeIntervalSince(at) < 1800 ? .fresh : .stale("Hace \(Self.ago(Date().timeIntervalSince(at))): sincroniza para actualizar.")
        return t
    }

    // MARK: Chart

    private var chartCard: some View {
        PCard {
            CardHeader(title: "Frecuencia cardiaca")
            Picker("Periodo", selection: $period) {
                ForEach(HRPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if let s = series {
                HStack(spacing: 0) {
                    stat("Media", s.enoughData ? Fmt.int(s.average) : "–")
                    stat("Mín", s.enoughData ? s.min.map(String.init) ?? "–" : "–")
                    stat("Máx", s.enoughData ? s.max.map(String.init) ?? "–" : "–")
                    stat("Con datos", "\(Int((s.coverage * 100).rounded())) %")
                }
                if s.points.isEmpty {
                    Text("Sin datos en este periodo. El historial llega al sincronizar la pulsera; el pulso en directo se guarda mientras está abierto.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    HRHistoryChart(series: s)
                        .frame(height: 190)
                    if !s.enoughData {
                        Text("Menos de 5 minutos con datos: sin media, mínimo ni máximo.").font(.caption).foregroundStyle(Theme.secondary)
                    }
                    Text(legend(s)).font(.caption2).foregroundStyle(Theme.tertiary)
                }
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 190)
            }
        }
    }

    private func legend(_ s: HRHistory.Series) -> String {
        let w = s.width >= 3600 ? "\(s.width / 3600) h" : "\(s.width / 60) min"
        return "Media cada \(w); la banda es el mínimo y el máximo. Zonas grises: sin datos (no se unen)."
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline.monospacedDigit()).foregroundStyle(.white)
            Text(k).font(.caption2).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Binned heart rate with a min–max band; gaps are shaded and never bridged.
struct HRHistoryChart: View {
    let series: HRHistory.Series

    var body: some View {
        let lo = Double((series.min ?? 50) - 5), hi = Double((series.max ?? 120) + 5)
        let from = Date(timeIntervalSince1970: TimeInterval(series.from))
        let to = Date(timeIntervalSince1970: TimeInterval(series.to))
        let bigGap = max(series.width * 3, (series.to - series.from) / 12)
        Chart {
            ForEach(Array(series.gaps.enumerated()), id: \.offset) { _, g in
                RectangleMark(xStart: .value("de", Date(timeIntervalSince1970: TimeInterval(g.from))),
                              xEnd: .value("a", Date(timeIntervalSince1970: TimeInterval(g.to))),
                              yStart: .value("lo", lo), yEnd: .value("hi", hi))
                    .foregroundStyle(Color.white.opacity(0.05))
                    .annotation(position: .overlay) {
                        if g.duration >= bigGap {
                            Text("sin datos").scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.tertiary)
                        }
                    }
            }
            ForEach(Array(series.points.enumerated()), id: \.offset) { _, p in
                let mid = Date(timeIntervalSince1970: TimeInterval(p.start) + Double(series.width) / 2)
                AreaMark(x: .value("t", mid), yStart: .value("mín", p.min), yEnd: .value("máx", p.max),
                         series: .value("tramo", "b\(p.segment)"))
                    .foregroundStyle(Theme.red.opacity(0.18))
                LineMark(x: .value("t", mid), y: .value("FC", p.mean), series: .value("tramo", "l\(p.segment)"))
                    .foregroundStyle(Theme.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                if isolated(p) {
                    PointMark(x: .value("t", mid), y: .value("FC", p.mean)).symbolSize(10).foregroundStyle(Theme.red)
                }
            }
        }
        .chartXScale(domain: from...to)
        .chartYScale(domain: lo...hi)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.tertiary) }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { v in
                AxisValueLabel {
                    if let d = v.as(Date.self) {
                        Text(axisLabel(d)).scaledFont(11, relativeTo: .caption1).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
    }

    /// A lone bin has no neighbour to draw a line to: show it as a dot.
    private func isolated(_ p: HRHistory.Point) -> Bool {
        series.points.filter { $0.segment == p.segment }.count == 1
    }

    private func axisLabel(_ d: Date) -> String {
        let span = series.to - series.from
        if span <= 86_400 { return d.formatted(.dateTime.hour().minute()) }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}

struct MonitorTile: Identifiable {
    enum State {
        case fresh
        case stale(String)
        case absent(String)
    }

    let id: String
    var title: String
    var value: String?
    var unit: String
    var color: Color
    var when: String?
    var source: String?
    var badge: String?
    var extra: [String] = []
    var state: State = .fresh

    init(id: String, title: String, unit: String, color: Color) {
        self.id = id
        self.title = title
        self.unit = unit
        self.color = color
    }

    /// A spot reading from the live stream: the tile's value when there is no night value, an extra line otherwise.
    mutating func addSpot(_ v: String, when w: String) {
        if case .absent = state {
            value = v
            when = w
            source = "Puntual · pulso en directo"
            state = .fresh
        } else {
            extra.append("Puntual: \(v) \(unit) · \(w.prefix(1).lowercased() + w.dropFirst())")
        }
    }
}

struct MonitorTileView: View {
    let tile: MonitorTile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Caps(tile.title, size: 10, color: Theme.secondary, weight: .semibold)
                Spacer(minLength: 4)
                if let b = tile.badge {
                    Text(b).scaledFont(11, weight: .semibold, relativeTo: .caption1).foregroundStyle(Theme.yellow)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tile.value ?? "–").scaledFont(28, weight: .bold, design: .rounded, relativeTo: .title1).monospacedDigit()
                    .foregroundStyle(isFresh ? tile.color : Theme.secondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if tile.value != nil && !tile.unit.isEmpty {
                    Text(tile.unit).font(.caption).foregroundStyle(Theme.tertiary)
                }
            }
            if let w = tile.when { Text(w).font(.caption2).foregroundStyle(.white.opacity(0.85)) }
            if let s = tile.source { Text(s).font(.caption2).foregroundStyle(Theme.tertiary) }
            ForEach(tile.extra, id: \.self) { Text($0).font(.caption2).foregroundStyle(Theme.secondary) }
            switch tile.state {
            case .fresh: EmptyView()
            case .stale(let why): Label(why, systemImage: "clock.badge.exclamationmark").font(.caption2).foregroundStyle(Theme.yellow)
            case .absent(let why): Text(why).font(.caption2).foregroundStyle(Theme.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    private var isFresh: Bool {
        if case .fresh = tile.state { return true }
        return false
    }
}
