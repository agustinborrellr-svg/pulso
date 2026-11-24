import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoFeatures

// Pieces shared by the Actividad screens (studio C-actividad): heart-rate zones, the live pulse chart, big figures,
// history lists, and the demo setup the screenshot run needs for live screens.

// MARK: - Zones

enum ActZones {
    static let names = ["Muy ligera", "Ligera", "Moderada", "Alta", "Máxima"]

    static func name(_ z: Int) -> String { names[min(max(z, 1), 5) - 1] }

    /// Floor and ceiling of a zone in bpm, from the app's heart-rate-reserve model.
    static func range(_ z: Int, _ m: HeartRateModel) -> ClosedRange<Double> {
        let lo = m.zoneFloor(z)
        let hi = z >= 5 ? m.maxHR : m.zoneFloor(z + 1)
        return lo...max(lo, hi)
    }

    static func text(_ z: Int, _ m: HeartRateModel) -> String {
        let r = range(z, m)
        return "\(Int(r.lowerBound.rounded()))–\(Int(r.upperBound.rounded()))"
    }

    /// Range of a zone span (4…5 → floor of 4 to max).
    static func span(_ lo: Int, _ hi: Int, _ m: HeartRateModel) -> ClosedRange<Double> {
        range(lo, m).lowerBound...range(hi, m).upperBound
    }
}

/// Z1…Z5 as five orange capsules (light to dark), the current zone thicker with a knob where the pulse sits in it.
struct ActZoneRamp: View {
    let zone: Int
    /// 0…1 inside the current zone.
    var fraction: Double = 0.5

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { z in
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DS.zone(z)).frame(height: z == zone ? 10 : 5)
                            if z == zone {
                                Circle().fill(DS.t1)
                                    .overlay(Circle().stroke(DS.card, lineWidth: 2))
                                    .frame(width: 16, height: 16)
                                    .offset(x: g.size.width * CGFloat(min(max(fraction, 0), 1)) - 8)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 16)
                }
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { z in
                    Text("Z\(z)").dsFont(12, z == zone ? .bold : .medium, relativeTo: .caption1)
                        .foregroundStyle(z == zone ? DS.t1 : DS.t3)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(zone > 0 ? "Zona \(zone)" : "Por debajo de la zona 1")
    }
}

// MARK: - Live pulse chart

/// The session's pulse as a pink line over a soft fill, a target band in orange with its name, a ring on the last
/// point, the axis on the right and "Hace N min · Ahora" underneath.
struct ActHRChart: View {
    struct P: Identifiable {
        let t: Date
        let v: Double
        var id: Date { t }
    }

    let points: [P]
    var band: ClosedRange<Double>?
    var bandLabel: String?
    var color: Color = DS.cor
    var height: CGFloat = 130

    var body: some View {
        let vals = points.map(\.v)
        let lo = (min(vals.min() ?? 60, band?.lowerBound ?? .infinity) - 6).rounded(.down)
        let hi = (max(vals.max() ?? 120, band?.upperBound ?? 0) + 6).rounded(.up)
        VStack(spacing: 6) {
            if points.count >= 2, let a = points.first?.t, let b = points.last?.t {
                Chart {
                    if let band {
                        RectangleMark(xStart: .value("a", a), xEnd: .value("b", b),
                                      yStart: .value("lo", band.lowerBound), yEnd: .value("hi", band.upperBound))
                            .foregroundStyle(DS.act.opacity(0.18))
                            .annotation(position: .overlay, alignment: .topLeading) {
                                if let bandLabel {
                                    Text(bandLabel).dsFont(12, .semibold, relativeTo: .caption1).foregroundStyle(DS.act)
                                        .padding(.leading, 6).padding(.top, 3)
                                }
                            }
                    }
                    ForEach(points) { p in
                        AreaMark(x: .value("t", p.t), yStart: .value("base", lo), yEnd: .value("v", p.v))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("t", p.t), y: .value("v", p.v))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    if let last = points.last {
                        PointMark(x: .value("t", last.t), y: .value("v", last.v))
                            .symbol { ZStack { Circle().fill(color.opacity(0.3)).frame(width: 18, height: 18); Circle().fill(color).frame(width: 8, height: 8) } }
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                        AxisGridLine().foregroundStyle(DS.sep)
                        AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").dsFont(12, relativeTo: .caption1).foregroundStyle(DS.t3) }
                    }
                }
                .frame(height: height)
                HStack {
                    Text("Hace \(max(1, Int((b.timeIntervalSince(a) / 60).rounded()))) min")
                        .foregroundStyle(DS.t3)
                    Spacer()
                    Text("Ahora").fontWeight(.semibold).foregroundStyle(DS.t1).padding(.trailing, 34)
                }
                .dsFont(13, relativeTo: .footnote)
            } else {
                Text("Esperando latidos…").dsFont(14).foregroundStyle(DS.t3)
                    .frame(maxWidth: .infinity, minHeight: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pulso de la sesión")
    }
}

// MARK: - Figures and lists

/// A big figure with its unit on the baseline ("158 lpm", "−24 lpm").
struct ActBigValue: View {
    let value: String
    var unit: String = ""
    var size: CGFloat = 64
    var color: Color = DS.t1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).dsFont(size, .semibold, relativeTo: .largeTitle, maxScale: 1.15).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !unit.isEmpty {
                Text(unit).dsFont(max(15, size * 0.32), .medium).foregroundStyle(DS.t2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Level dot + word ("● Buena").
struct ActLevelLine: View {
    let text: String
    let color: Color
    var ink: Color?

    var body: some View {
        HStack(spacing: 6) {
            DSDot(color: color, size: 8)
            Text(text).dsFont(16, .semibold).foregroundStyle(ink ?? color)
        }
    }
}

/// «Historial»: date on the left, the result on the right, in one card (latest first, at most 12).
struct ActHistory: View {
    let rows: [(Date, String)]

    var body: some View {
        if !rows.isEmpty {
            DSSectionHeader("Historial")
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    if i > 0 { DSDivider() }
                    HStack {
                        Text(Self.date(rows[i].0)).dsFont(15).foregroundStyle(DS.t2)
                        Spacer(minLength: 8)
                        Text(rows[i].1).dsFont(16, .medium).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(minHeight: 50)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 14)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        }
    }

    /// "15 nov · 08:10".
    static func date(_ d: Date) -> String {
        "\(DSFmt.dayMonth(d)) · \(DSFmt.clock(d))"
    }

    static func rows(_ records: [LiveTestRecord], _ format: (LiveTestRecord) -> String) -> [(Date, String)] {
        records.suffix(12).reversed().map { ($0.date, format($0)) }
    }
}

/// A row of a «Tus zonas» list: swatch, zone and its name, the range.
struct ActZoneRow: View {
    let zone: Int
    let range: String
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(DS.zone(zone)).frame(width: 12, height: 12)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("Zona \(zone)").dsFont(17, .semibold).foregroundStyle(DS.t1)
                Text(ActZones.name(zone)).dsFont(14).foregroundStyle(DS.t2)
            }
            Spacer(minLength: 8)
            Text(range).dsFont(15).foregroundStyle(trailing == nil ? DS.t1 : DS.t3)
            if let trailing {
                Text(trailing).dsFont(17, .semibold).foregroundStyle(DS.t1).frame(minWidth: 52, alignment: .trailing)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

/// "1:04" from minutes (h:mm).
enum ActFmt {
    static func hmm(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// "1 h 59" / "10 min" split for a big figure.
    static func hourParts(_ minutes: Double) -> [(String, String)] {
        let m = Int(minutes.rounded())
        if m < 60 { return [("\(m)", "min")] }
        return m % 60 == 0 ? [("\(m / 60)", "h")] : [("\(m / 60)", "h"), ("\(m % 60)", "min")]
    }

    static func signedInt(_ v: Double) -> String {
        (v >= 0 ? "+" : "−") + "\(Int(abs(v).rounded()))"
    }
}

/// "1 h 59 min" in mixed sizes (figures big, units small).
struct ActDurationValue: View {
    let minutes: Double
    var size: CGFloat = 52

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            ForEach(Array(ActFmt.hourParts(minutes).enumerated()), id: \.offset) { _, p in
                Text(p.0).dsFont(size, .semibold, relativeTo: .largeTitle, maxScale: 1.15).foregroundStyle(DS.t1)
                Text(p.1).dsFont(size * 0.42, .medium).foregroundStyle(DS.t2).padding(.trailing, 4)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DSFmt.duration(minutes))
    }
}

// MARK: - Screenshot run

/// Demo setup for the live screens in the CI screenshot run only (a feed of plausible beats, a running workout or test).
@MainActor
enum ActShots {
    private static var fed = false

    static func prepare(_ route: ActividadRoute, model: AppModel) {
        guard AppMode.screenshots else { return }
        switch route {
        case .entrenoVivo, .entrenoVivoMenu:
            model.startWorkout(sport: "Carrera")
            model.setTargetZone(3)
            feed(model, resting: false)
        case .entrenoIntervalos:
            model.startWorkout(sport: "Carrera", plan: IntervalPlan.presets.first)
            model.setTargetZone(4)
            feed(model, resting: false)
        case .ortostaticoEnCurso:
            feed(model, resting: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { model.startLiveTest(.orthostatic) }
        case .chequeo60s, .poincare, .respiraPreparacion, .respiraSesion, .ortostatico, .recuperacionFC, .fcMaxima:
            feed(model, resting: true)
        default:
            break
        }
    }

    private static func feed(_ model: AppModel, resting: Bool) {
        guard !fed else { return }
        fed = true
        model.startDemoLiveFeed(resting: resting)
    }

    /// The tab root draws as connected in the screenshot run (no strap in the simulator), except its own
    /// "sin pulsera" capture.
    static var assumeConnected: Bool { AppMode.screenshots && AppMode.screen != "r.actividad.sinPulsera" }
}
