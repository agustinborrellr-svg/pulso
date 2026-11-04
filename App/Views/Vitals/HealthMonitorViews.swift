import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

// MARK: - Monitor de salud (Inicio)

extension VitalReading {
    /// Skin temperature reads as the change from your usual (the middle of your range), not in degrees.
    var asDeviation: Bool { id == "temp" && range != nil }

    private var centre: Double? { range.map { ($0.lowerBound + $0.upperBound) / 2 } }

    private func signed(_ v: Double) -> String {
        (v >= 0.05 ? "+" : (v <= -0.05 ? "−" : "")) + format(abs(v))
    }

    var monitorTitle: String { asDeviation ? "Temp. cutánea (dif.)" : title }

    var monitorValue: String {
        guard asDeviation, let c = centre else { return value }
        return signed(raw - c)
    }

    /// "dentro de 48 - 53", "elevada > +0,9", "baja < 95%".
    var monitorChip: String {
        guard let r = range else { return "calibrando tu rango" }
        let pct = unit == "%" ? "%" : ""
        if asDeviation, let c = centre {
            let half = format((r.upperBound - r.lowerBound) / 2)
            if r.contains(raw) { return "dentro de ±\(half)" }
            return raw > c ? "elevada > +\(half)" : "baja < −\(half)"
        }
        if r.contains(raw) { return "dentro de \(format(r.lowerBound))\(pct) - \(format(r.upperBound))\(pct)" }
        let high = raw > r.upperBound
        if level == .green { return high ? "por encima de \(format(r.upperBound))\(pct)" : "por debajo de \(format(r.lowerBound))\(pct)" }
        return high ? "elevada > \(format(r.upperBound))\(pct)" : "baja < \(format(r.lowerBound))\(pct)"
    }

    var monitorIcon: String { level == .green || level == .none ? "checkmark" : "exclamationmark" }
}

/// Inicio's half-width health monitor: a check or a warning for each vital of last night. Opens the monitor page.
struct HomeHealthMonitorTile: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let all = model.vitalReadings()
        let readings = HealthMonitorView.order.compactMap { id in all.first { $0.id == id } }
        let off = readings.filter { $0.level == .orange || $0.level == .red }
        NavigationLink { HealthMonitorView() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Caps("Monitor de salud", size: 10.5, weight: .semibold)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(Theme.tertiary)
                }
                HStack(spacing: 0) {
                    ForEach(readings) { r in
                        VStack(spacing: 6) {
                            Image(systemName: r.icon).font(.caption).foregroundStyle(Theme.secondary)
                            Image(systemName: r.monitorIcon).font(.system(size: 9, weight: .heavy)).foregroundStyle(r.color)
                                .frame(width: 18, height: 18)
                                .background(r.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text(readings.isEmpty ? "Tras tu primera noche con la pulsera"
                     : (off.isEmpty ? "Todo en tu rango" : off.map { "\($0.short) \($0.raw > ($0.range?.upperBound ?? .infinity) ? "alta" : "baja")" }.joined(separator: " · ")))
                    .scaledFont(11, weight: .medium, relativeTo: .caption1)
                    .foregroundStyle(off.isEmpty ? Theme.secondary : (off.map(\.level).max() == .red ? Theme.red : Theme.worse))
                    .lineLimit(2)
            }
            .padding(14)
            // Fills the row's height: side by side on Inicio, both tiles are always the size of the taller one.
            .frame(maxWidth: .infinity, minHeight: 104, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// "MONITOR DE SALUD": your pulse live, a tile per vital of last night and the printable report. A tile opens its
/// panel, and the panel its trends.
struct HealthMonitorView: View {
    @EnvironmentObject var model: AppModel
    @State private var open: VitalReading?
    @State private var pendingTrend: TrendMetric?
    @State private var trend: TrendMetric?

    static let order = ["resp", "spo2", "rhr", "hrv", "temp"]

    var body: some View {
        let all = model.vitalReadings()
        let readings = Self.order.compactMap { id in all.first { $0.id == id } }
        DetailScreen(title: "Monitor de salud") {
            LiveHeroMonitor(fullBleed: true)
                .padding(.top, -8)
            if readings.isEmpty {
                EmptyState(icon: "waveform.path.ecg", title: "Sin datos", message: "Aparecen tras tu primera noche con la pulsera.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    ForEach(readings) { r in
                        Button { show(r) } label: { VitalMonitorTile(reading: r) }.buttonStyle(.plain)
                    }
                }
                if let when = readings.first?.when {
                    Text("\(when) · comparado con tus 30 noches anteriores").font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            HealthReportButton()
        }
        .fullScreenCover(item: $open, onDismiss: {
            if let m = pendingTrend {
                pendingTrend = nil
                trend = m
            }
        }) { r in
            VitalPanel(reading: r, close: { show(nil) }, trends: {
                pendingTrend = r.metric
                show(nil)
            })
            .presentationBackground(.clear)
        }
        .navigationDestination(item: $trend) { m in TrendDetailView(metric: m) }
    }

    /// The panel fades in over the page instead of sliding up as a full screen.
    private func show(_ r: VitalReading?) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { open = r }
    }
}

struct VitalMonitorTile: View {
    let reading: VitalReading

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: reading.icon).font(.footnote).foregroundStyle(Theme.secondary).frame(width: 18)
                Caps(reading.monitorTitle, size: 9.5, color: Theme.secondary, weight: .semibold)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(reading.monitorValue).scaledFont(28, weight: .bold, relativeTo: .title1).monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(reading.unit).font(.footnote).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            VitalMonitorChip(reading: reading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct VitalMonitorChip: View {
    let reading: VitalReading

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: reading.monitorIcon).font(.caption2.bold())
            Text(reading.monitorChip).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .foregroundStyle(reading.color)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(reading.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// One vital explained: what it is, where tonight sits, your green/orange/red limits and the way to its trends.
struct VitalPanel: View {
    let reading: VitalReading
    let close: () -> Void
    let trends: () -> Void
    @State private var shown = false
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.6 : 0).ignoresSafeArea().onTapGesture(perform: close)
            // As tall as its text, scrolling only when that is more than the screen.
            ScrollView {
                card.background(GeometryReader { g in Color.clear.preference(key: PanelHeight.self, value: g.size.height) })
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: cardHeight > 0 ? cardHeight : .infinity)
            .onPreferenceChange(PanelHeight.self) { cardHeight = $0 }
            .background(LinearGradient(colors: [Theme.cardHighlight, Theme.card], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 22)
            .padding(.vertical, 60)
            .scaleEffect(shown ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { shown = true } }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: reading.icon).font(.system(size: 30)).foregroundStyle(Theme.secondary)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.title3.weight(.semibold)).foregroundStyle(.white)
                }
                .accessibilityLabel("Cerrar")
            }
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: reading.monitorIcon).font(.footnote.bold()).foregroundStyle(reading.color)
                    .frame(width: 34, height: 34)
                    .background(reading.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Caps(reading.title, size: 14)
                    Caps(reading.monitorChip, size: 14, color: reading.color)
                }
            }
            Text(reading.explanation).font(.body).foregroundStyle(.white.opacity(0.9))
            if !reading.detail.isEmpty {
                Text(reading.detail).font(.body).foregroundStyle(.white.opacity(0.9))
            }
            if !reading.limits.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reading.personal ? "Los rangos se calculan con los datos de los últimos 30 días:" : "Rangos de referencia:")
                        .font(.body).foregroundStyle(.white.opacity(0.9))
                    ForEach(Array(reading.limits.enumerated()), id: \.offset) { _, l in
                        HStack(spacing: 8) {
                            Circle().fill(VitalReading.color(l.0)).frame(width: 8, height: 8)
                            Text(l.1).font(.body).foregroundStyle(.white.opacity(0.9))
                        }
                    }
                }
            }
            Text("El monitor de \(["hrv", "spo2"].contains(reading.id) ? reading.short : reading.short.lowercased()) de Pulso no es un dispositivo médico. Consulta a un profesional de la salud antes de tomar decisiones de tipo médico.")
                .font(.caption).foregroundStyle(Theme.secondary)
            Button(action: trends) {
                Caps("Abrir vista de tendencias", size: 13)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }
}

private struct PanelHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Informe de salud

/// "Comparte tu informe de salud": builds the PDF on tap, then offers it to share.
struct HealthReportButton: View {
    @EnvironmentObject var model: AppModel
    @State private var url: URL?
    @State private var making = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url {
                ShareLink(item: url) { row("Comparte tu informe de salud", icon: "square.and.arrow.up") }
                    .buttonStyle(.plain)
            } else {
                Button {
                    making = true
                    url = HealthReportPDF.render(model.healthReport(), profile: model.profile)
                    making = false
                } label: {
                    row(making ? "Creando informe…" : "Crear informe de salud", icon: "doc.text")
                }
                .buttonStyle(.plain)
                .disabled(making)
            }
            Text("Informe imprimible para compartirlo con tu médico, especialista, entrenador o con quien quieras.")
                .font(.caption).foregroundStyle(Theme.secondary)
        }
        .padding(.top, 4)
    }

    private func row(_ title: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.secondary)
            Caps(title, size: 13)
            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension AppModel {
    /// The last 180 days of nights and workouts for the printable report.
    func healthReport() -> HealthReport.Report {
        let end = currentDayKey
        let from = DayKey.date(DayKey.shift(end, days: -181)).map { Int($0.timeIntervalSince1970) } ?? 0
        let workouts = (try? db.workouts(from: from, to: Int(Date().timeIntervalSince1970) + 86_400)) ?? []
        return HealthReport.build(days: days, workouts: workouts, end: end)
    }
}

enum HealthReportPDF {
    static let page = CGSize(width: 595, height: 842)

    @MainActor
    static func render(_ r: HealthReport.Report, profile: Profile) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Pulso-informe-de-salud-\(r.days.last ?? "").pdf")
        var box = CGRect(origin: .zero, size: page)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for p in HealthReportPage.Kind.allCases {
            let renderer = ImageRenderer(content: HealthReportPage(report: r, profile: profile, kind: p)
                .frame(width: page.width, height: page.height)
                .environment(\.colorScheme, .light))
            renderer.proposedSize = ProposedViewSize(page)
            renderer.render { size, draw in
                ctx.beginPDFPage(nil)
                ctx.saveGState()
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(box)
                ctx.translateBy(x: 0, y: box.height - size.height)
                draw(ctx)
                ctx.restoreGState()
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return url
    }
}

/// One A4 page of the report, black on white.
struct HealthReportPage: View {
    enum Kind: CaseIterable { case summary, recent, months, monthsMore }

    let report: HealthReport.Report
    let profile: Profile
    let kind: Kind

    static let ink = Color(white: 0.1)
    static let sub = Color(white: 0.45)
    static let line = Color(white: 0.55)
    static let band = Color(white: 0.9)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            switch kind {
            case .summary:
                summary
                section("Frecuencia respiratoria", "Respiraciones por minuto durante el sueño.") {
                    ReportDaysLine(report: report, series: report.long["resp"], digits: 1)
                }
                section("Frecuencia cardíaca en reposo", "Latidos por minuto durante el sueño.") {
                    ReportDaysLine(report: report, series: report.long["rhr"], digits: 0)
                }
            case .recent:
                section("Variabilidad de la frecuencia cardíaca", "RMSSD en milisegundos durante el sueño.") {
                    ReportDaysLine(report: report, series: report.long["hrv"], digits: 0)
                }
                section("Duración del sueño", "Horas dormidas. Para esta edad se recomiendan al menos 7 horas cada noche.",
                        legend: [("Sueño", Self.band.opacity(0.9)), ("Siesta", Self.line)]) {
                    ReportDaysBars(report: report, a: report.sleep, b: report.naps, digits: 2, guide: 7)
                }
                section("Actividad aeróbica diaria",
                        "Minutos en zonas de pulso altas en las actividades registradas. Se recomiendan 150 minutos de actividad moderada o 75 de intensa a la semana.",
                        legend: [("Moderada", Self.band.opacity(0.9)), ("Intensa", Self.line)]) {
                    ReportDaysBars(report: report, a: report.moderate, b: report.vigorous, digits: 0, guide: nil,
                                   average: report.aerobicAverage)
                }
            case .months:
                section("Frecuencia respiratoria", "Media de cada mes con datos suficientes.") {
                    ReportMonths(report: report, series: report.long["resp"], digits: 1)
                }
                section("Frecuencia cardíaca en reposo", "Media de cada mes con datos suficientes.") {
                    ReportMonths(report: report, series: report.long["rhr"], digits: 0)
                }
                section("Variabilidad de la frecuencia cardíaca", "Media de cada mes con datos suficientes.") {
                    ReportMonths(report: report, series: report.long["hrv"], digits: 0)
                }
            case .monthsMore:
                section("Duración del sueño", "Horas dormidas, con la media de cada mes con datos suficientes.") {
                    ReportMonths(report: report, series: report.sleep, digits: 2, bars: true)
                }
                section("Actividad aeróbica diaria", "Minutos en zonas altas, con la media de cada mes con datos suficientes.") {
                    ReportMonths(report: report, series: report.aerobicLong, digits: 0, bars: true)
                }
                if !report.topSports.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Actividades más registradas").font(.system(size: 10)).foregroundStyle(Self.sub)
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(report.topSports, id: \.name) { s in
                                VStack(alignment: .leading, spacing: 2) {
                                    Image(systemName: "figure.mixed.cardio").font(.system(size: 22)).foregroundStyle(Self.ink)
                                    Text("\(s.count)×").font(.system(size: 11, weight: .bold)).foregroundStyle(Self.ink)
                                    Text(s.name.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Self.sub)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 32)
        .background(Color.white)
    }

    private var long: Bool { kind == .months || kind == .monthsMore }

    private var header: some View {
        let range = long ? (report.longDays.first, report.longDays.last) : (report.days.first, report.days.last)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text((profile.name.isEmpty ? "Pulso" : profile.name).uppercased()).font(.system(size: 17, weight: .bold)).tracking(1).foregroundStyle(Self.ink)
                Text("NACIMIENTO \(String(profile.birthYear))  |  EDAD \(profile.age)").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Self.sub)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(long ? "INFORME DE SALUD · 180 DÍAS" : "INFORME DE SALUD · 30 DÍAS").font(.system(size: 17, weight: .bold)).tracking(1).foregroundStyle(Self.ink)
                Text("\(Self.date(range.0)) – \(Self.date(range.1))").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Self.sub)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PULSO").font(.system(size: 14, weight: .heavy)).tracking(3).foregroundStyle(Self.ink)
            Text("Pulso no es un dispositivo médico: no sirve para diagnosticar ninguna enfermedad y no sustituye el consejo, el diagnóstico ni el tratamiento de un profesional. Todo lo que muestra es orientativo y sale de tus propios datos.")
                .font(.system(size: 7.5)).foregroundStyle(Self.sub)
        }
    }

    /// Metric, mean of the 30 days, your usual band and the six-month mean.
    private var summary: some View {
        let rows: [(name: String, series: HealthReport.Series?, fmt: (Double) -> String)] = [
            ("Frecuencia respiratoria", report.long["resp"], { "\(Fmt.dec($0)) rpm" }),
            ("FC en reposo", report.long["rhr"], { "\(Fmt.int($0)) lpm" }),
            ("VFC", report.long["hrv"], { "\(Fmt.int($0)) ms" }),
            ("Oxígeno en sangre", report.long["spo2"], { "\(Fmt.int($0)) %" }),
            ("Temp. cutánea (dif.)", report.long["temp"], { ($0 >= 0 ? "+" : "−") + "\(Fmt.dec(abs($0))) °C" }),
            ("Sueño", report.sleep, { "\(Fmt.dec($0, 2)) h" }),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            Text("RESUMEN").font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(Self.ink).padding(.bottom, 6)
            HStack {
                Text("Métrica").frame(maxWidth: .infinity, alignment: .leading)
                Text("Media 30 días").frame(width: 100, alignment: .trailing)
                Text("Rango habitual (6 meses)").frame(width: 150, alignment: .trailing)
                Text("Media 6 meses").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Self.sub).padding(.vertical, 5)
            ForEach(rows, id: \.name) { row in
                let s = row.series
                HStack {
                    Text(row.name).frame(maxWidth: .infinity, alignment: .leading)
                    Text(s.flatMap { report.recent($0).average }.map(row.fmt) ?? "–").frame(width: 100, alignment: .trailing)
                    Text(s?.range.map { "\(row.fmt($0.lowerBound)) – \(row.fmt($0.upperBound))" } ?? "–").frame(width: 150, alignment: .trailing)
                    Text(s?.average.map(row.fmt) ?? "–").frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 10)).monospacedDigit().foregroundStyle(Self.ink)
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) { Rectangle().fill(Self.band).frame(height: 0.5) }
            }
            HStack {
                Text("Actividad aeróbica").frame(maxWidth: .infinity, alignment: .leading)
                Text(report.aerobicAverage.map { "\(Fmt.int($0)) min/día" } ?? "–").frame(width: 100, alignment: .trailing)
                Text("–").frame(width: 150, alignment: .trailing)
                Text(Stats.mean(report.aerobicLong.values.compactMap { $0 }).map { "\(Fmt.int($0)) min/día" } ?? "–").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(Self.ink)
            .padding(.vertical, 5)
        }
    }

    private func section<C: View>(_ title: String, _ note: String, legend: [(name: String, color: Color)] = [], @ViewBuilder chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(Self.ink)
                Spacer()
                if legend.isEmpty, !long {
                    legendItem("Rango personal de 6 meses", Self.band)
                }
                ForEach(legend, id: \.name) { l in legendItem(l.name, l.color) }
            }
            Text(note).font(.system(size: 8.5)).foregroundStyle(Self.sub).fixedSize(horizontal: false, vertical: true)
            chart().frame(height: kind == .summary ? 150 : 165)
        }
    }

    private func legendItem(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(c).frame(width: 8, height: 8)
            Text(t).font(.system(size: 8.5)).foregroundStyle(Self.ink)
        }
        .padding(.leading, 8)
    }

    static func date(_ key: String?) -> String {
        guard let key, let d = DayKey.date(key) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "dd/MM/yyyy"
        return f.string(from: d)
    }
}

extension HealthReport.Report {
    /// Moderate plus vigorous minutes of each of the 180 days.
    var aerobicLong: HealthReport.Series {
        var s = moderate
        s.values = zip(moderate.values, vigorous.values).map { ($0 ?? 0) + ($1 ?? 0) }
        return s
    }
}

/// The 30 nights as a line of dots over your six-month band, with the 30-day mean dashed.
struct ReportDaysLine: View {
    let report: HealthReport.Report
    let series: HealthReport.Series?
    let digits: Int

    var body: some View {
        let s = series.map { report.recent($0) }
        let pts: [(date: Date, v: Double)] = zip(report.days, s?.values ?? []).compactMap { k, v in v.flatMap { v in DayKey.date(k).map { (date: $0, v: v) } } }
        let band = series?.range
        let lo = min(pts.map(\.v).min() ?? 0, band?.lowerBound ?? .infinity)
        let hi = max(pts.map(\.v).max() ?? 1, band?.upperBound ?? -.infinity)
        let pad = max((hi - lo) * 0.15, digits == 0 ? 2 : 0.3)
        Chart {
            if let band, let first = DayKey.date(report.days.first ?? ""), let last = DayKey.date(report.days.last ?? "") {
                RectangleMark(xStart: .value("a", first), xEnd: .value("b", last),
                              yStart: .value("lo", band.lowerBound), yEnd: .value("hi", band.upperBound))
                    .foregroundStyle(HealthReportPage.band)
            }
            if let avg = s?.average {
                RuleMark(y: .value("Media", avg))
                    .foregroundStyle(HealthReportPage.line)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .trailing, alignment: .leading) { ReportAverage(text: Fmt.dec(avg, digits)) }
            }
            ForEach(pts, id: \.date) { p in
                LineMark(x: .value("Día", p.date), y: .value("v", p.v))
                    .foregroundStyle(HealthReportPage.line)
                PointMark(x: .value("Día", p.date), y: .value("v", p.v))
                    .symbol { Circle().strokeBorder(HealthReportPage.line, lineWidth: 1.5).background(Circle().fill(.white)).frame(width: 7, height: 7) }
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .reportDayAxis()
        .padding(.trailing, 34)
    }
}

/// Stacked bars per day (sleep and naps, or moderate and vigorous minutes) with the mean dashed.
struct ReportDaysBars: View {
    let report: HealthReport.Report
    let a: HealthReport.Series
    let b: HealthReport.Series
    let digits: Int
    let guide: Double?
    var average: Double?

    var body: some View {
        let ra = report.recent(a), rb = report.recent(b)
        let rows: [(date: Date, a: Double, b: Double)] = report.days.enumerated().compactMap { i, k in DayKey.date(k).map { (date: $0, a: ra.values[i] ?? 0, b: rb.values[i] ?? 0) } }
        let avg = average ?? ra.average
        Chart {
            ForEach(rows, id: \.date) { r in
                BarMark(x: .value("Día", r.date, unit: .day), y: .value("v", r.a), width: .ratio(0.6))
                    .foregroundStyle(HealthReportPage.band.opacity(0.9))
                BarMark(x: .value("Día", r.date, unit: .day), yStart: .value("a", r.a), yEnd: .value("b", r.a + r.b), width: .ratio(0.6))
                    .foregroundStyle(HealthReportPage.line)
            }
            if let avg {
                RuleMark(y: .value("Media", avg))
                    .foregroundStyle(HealthReportPage.line)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .trailing, alignment: .leading) { ReportAverage(text: Fmt.dec(avg, digits)) }
            }
        }
        .reportDayAxis()
        .padding(.trailing, 34)
    }
}

/// 180 days as a thin line (or thin bars) with a flat segment and label for each month's mean.
struct ReportMonths: View {
    let report: HealthReport.Report
    let series: HealthReport.Series?
    let digits: Int
    var bars = false

    var body: some View {
        let pts: [(date: Date, v: Double)] = zip(report.longDays, series?.values ?? []).compactMap { k, v in v.flatMap { v in DayKey.date(k).map { (date: $0, v: v) } } }
        let months: [(start: Date, end: Date, v: Double)] = report.months.compactMap { m in
            guard let v = series?.monthly[m], let start = DayKey.date(m + "-01") else { return nil }
            let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
            return (start, end.addingTimeInterval(-86_400), v)
        }
        Chart {
            ForEach(pts, id: \.date) { p in
                if bars {
                    BarMark(x: .value("Día", p.date, unit: .day), y: .value("v", p.v)).foregroundStyle(HealthReportPage.band.opacity(0.9))
                } else {
                    LineMark(x: .value("Día", p.date), y: .value("v", p.v))
                        .foregroundStyle(HealthReportPage.line)
                        .lineStyle(StrokeStyle(lineWidth: 0.8))
                }
            }
            ForEach(months, id: \.start) { m in
                RuleMark(xStart: .value("a", m.start), xEnd: .value("b", m.end), y: .value("Media", m.v))
                    .foregroundStyle(HealthReportPage.ink)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(Fmt.dec(m.v, digits)) MEDIA").font(.system(size: 8, weight: .bold)).foregroundStyle(HealthReportPage.ink)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: bars))
        .chartXScale(domain: (DayKey.date(report.longDays.first ?? "") ?? Date())...(DayKey.date(report.longDays.last ?? "") ?? Date()))
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine().foregroundStyle(HealthReportPage.band)
                AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.system(size: 8, weight: .semibold)).foregroundStyle(HealthReportPage.ink)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(HealthReportPage.band)
                AxisValueLabel().font(.system(size: 8)).foregroundStyle(HealthReportPage.ink)
            }
        }
    }
}

struct ReportAverage: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text).font(.system(size: 9, weight: .bold)).foregroundStyle(HealthReportPage.ink)
            Text("MEDIA").font(.system(size: 7, weight: .semibold)).foregroundStyle(HealthReportPage.sub)
        }
        .fixedSize()
    }
}

private extension View {
    /// One tick per day labelled with the day of the month, light grid, values on the left.
    func reportDayAxis() -> some View {
        chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine().foregroundStyle(HealthReportPage.band)
                AxisValueLabel(format: .dateTime.day(), centered: true).font(.system(size: 7.5)).foregroundStyle(HealthReportPage.ink)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(HealthReportPage.band)
                AxisValueLabel().font(.system(size: 8)).foregroundStyle(HealthReportPage.ink)
            }
        }
    }
}
