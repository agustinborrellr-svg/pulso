import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// 11 Tendencias de tu cuerpo: the five vitals over 7 d / 30 d / 6 m, each a small line over your normal band with
/// last night's value (each opens its detail), and this month against the previous one.
struct HoyTendenciasView: View {
    @EnvironmentObject var model: AppModel
    @State private var period: DSPeriod = .month

    var body: some View {
        let all = model.vitalReadings()
        let readings = HoyMonitor.order.compactMap { id in all.first { $0.id == id } }
        DSScreen("Tendencias de tu cuerpo", subtitle: "Tus \(readings.count) constantes", back: "Hoy") {
            if readings.isEmpty {
                DSEmptyState(icon: "chart.xyaxis.line", title: "Sin constantes", message: "Aparecen tras tu primera noche con la pulsera.")
            } else {
                DSSegmented(options: DSPeriod.standard.map { ($0, $0.label) }, selection: $period)
                    .frame(width: 220).frame(maxWidth: .infinity)
                VStack(spacing: 0) {
                    ForEach(readings.indices, id: \.self) { i in
                        if i > 0 { DSDivider(inset: 46) }
                        RouteLink(.metric(HoyVital.kind(readings[i].id))) { row(readings[i]) }
                    }
                    DSDivider()
                    HStack(spacing: 18) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(DS.fill2).frame(width: 14, height: 9)
                            Text("Tu normal")
                        }
                        HStack(spacing: 6) {
                            Circle().fill(DS.t1).frame(width: 7, height: 7)
                            Text("Anoche")
                        }
                        Spacer()
                    }
                    .dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                }
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                let changes = readings.compactMap(change)
                if !changes.isEmpty {
                    DSSectionHeader("Este mes frente al anterior")
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(changes.indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(changes[i].0).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2).lineLimit(1).minimumScaleFactor(0.7)
                                Text(changes[i].1).dsFont(17, .semibold).foregroundStyle(changes[i].2).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .padding(.leading, i == 0 ? 0 : 8)
                            .padding(.trailing, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(DS.sep).frame(width: 0.5) } }
                        }
                    }
                    .dsCard(padding: 14)
                }
                DSSectionHeader("Qué es")
                DSWhatIs(text: "Cada constante se mide durante el sueño y se compara con tus propias noches: la banda es tu normal del último mes. Toca una para ver su detalle.",
                         footnote: nil)
            }
        }
    }

    private func row(_ r: VitalReading) -> some View {
        let color = HoyVital.color(r.id)
        return HStack(spacing: 12) {
            Image(systemName: HoyMonitor.icons[r.id] ?? r.icon).font(.system(size: 16)).foregroundStyle(color).frame(width: 22)
            Text(HoyVital.shortTitle(r.id)).dsFont(17, .medium).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.75)
                .frame(width: 104, alignment: .leading)
            spark(r, color: color).frame(maxWidth: .infinity).frame(height: 36)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(r.asDeviation ? r.monitorValue : r.value).dsFont(19, .semibold).foregroundStyle(DS.t1)
                Text(r.unit == "%" ? " %" : r.unit).dsFont(13).foregroundStyle(DS.t2)
            }
            .fixedSize()
            DSChevron()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func spark(_ r: VitalReading, color: Color) -> some View {
        let pts = points(r)
        let band = r.range
        let vals = pts.map(\.value) + (band.map { [$0.lowerBound, $0.upperBound] } ?? [])
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let pad = max((hi - lo) * 0.15, 0.01)
        return Chart {
            if let band, let a = pts.first?.date, let b = pts.last?.date {
                RectangleMark(xStart: .value("a", a), xEnd: .value("b", b), yStart: .value("lo", band.lowerBound), yEnd: .value("hi", band.upperBound))
                    .foregroundStyle(color.opacity(0.16))
            }
            ForEach(pts) { p in
                LineMark(x: .value("d", p.date), y: .value("v", p.value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .foregroundStyle(color)
            }
            if let last = pts.last {
                PointMark(x: .value("d", last.date), y: .value("v", last.value))
                    .symbol { Circle().fill(color).frame(width: 7, height: 7) }
            }
        }
        .chartYScale(domain: (lo - pad)...(hi + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }

    private func points(_ r: VitalReading) -> [DSPoint] {
        guard let end = r.history.last?.day else { return [] }
        let start = DayKey.shift(end, days: -(period.days - 1))
        let raw = model.days.filter { $0.day >= start && $0.day <= end }
            .compactMap { d in HoyVitalSpec.value(r.id, d).flatMap { v in DayKey.date(d.day).map { DSPoint(date: $0, value: v) } } }
        guard period.days > 31, let first = raw.first?.date else { return raw }
        var weeks: [Int: [Double]] = [:]
        for p in raw { weeks[Int(p.date.timeIntervalSince(first) / (7 * 86_400)), default: []].append(p.value) }
        return weeks.keys.sorted().map { w in
            let v = weeks[w] ?? []
            return DSPoint(date: first.addingTimeInterval(Double(w * 7 + 3) * 86_400), value: v.reduce(0, +) / Double(max(v.count, 1)))
        }
    }

    /// Mean of the last 30 nights against the 30 before: "+3 %" (green when it is the good direction), "igual",
    /// "−0,1 °C" for skin temperature.
    private func change(_ r: VitalReading) -> (String, String, Color)? {
        guard let end = r.history.last?.day else { return nil }
        func mean(_ from: Int, _ to: Int) -> Double? {
            let a = DayKey.shift(end, days: -to), b = DayKey.shift(end, days: -from)
            let v = model.days.filter { $0.day > a && $0.day <= b }.compactMap { HoyVitalSpec.value(r.id, $0) }
            return v.count >= 7 ? v.reduce(0, +) / Double(v.count) : nil
        }
        guard let now = mean(0, 30), let before = mean(30, 60) else { return nil }
        let short = ["hrv": "VFC", "rhr": "FC rep.", "resp": "Resp.", "spo2": "SpO₂", "temp": "Temp."][r.id] ?? r.short
        if r.id == "temp" {
            let d = now - before
            return (short, abs(d) < 0.05 ? "igual" : HoyVital.signed(d, { Fmt.dec($0) }) + " °C", DS.t1)
        }
        let pct = (now - before) / max(before, 0.0001) * 100
        let rounded = Int(pct.rounded())
        if rounded == 0 { return (short, "igual", DS.t1) }
        let good: Bool? = ["hrv", "rhr"].contains(r.id) ? ((r.bad < 0) == (rounded > 0)) : nil
        let color = good == true ? DSLevel.buena.ink : (good == false ? DSLevel.justa.ink : DS.t1)
        return (short, (rounded > 0 ? "+" : "−") + "\(abs(rounded)) %", color)
    }
}
