import SwiftUI
import PulsoStore
import PulsoAnalytics

/// 01 Recarga: the score with its level, your normal / month mean / yesterday, the coach's sentence and the effort it
/// recommends, the chart, «Qué ha influido» in points (the waterfall from a normal day for you), habits and «Qué es».
struct HoyRecargaView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let day = model.selected
        let spec = makeSpec()
        DSScreen("Recarga", subtitle: subtitle(day), back: "Hoy") {
            if let d = day, let r = d.recovery {
                hero(d, r, spec: spec)
            } else {
                DSEmptyState(icon: "bolt.heart", title: day?.calibrating == true ? "Calibrando" : "Sin Recarga",
                             message: "Aparece por la mañana, tras dormir con la pulsera unas cuantas noches.")
            }
            if spec.series.values.contains(where: { !$0.isEmpty }) {
                DSMetricChartCard(spec: spec)
            }
            if let d = day { influido(d) }
            RouteLink(.salud(.comportamientos)) {
                HoyLinkCard(icon: "clock.arrow.circlepath", title: "Hábitos que te afectan", subtitle: "Comportamientos y diario")
            }
            DSSectionHeader("Qué es")
            DSWhatIs(text: "Lo preparado que está tu cuerpo para el esfuerzo. Sale de tu VFC, tu FC en reposo y tu sueño de anoche, comparados con tu último mes.",
                     footnote: "No es un diagnóstico médico.")
        }
    }

    private func makeSpec() -> DSMetricSpec {
        var spec = DSTrendMetricSpec.make(model: model, metric: .recovery, title: "Recarga", back: "Hoy", color: DS.recarga,
                                          score: true, night: false, yDomain: 0...100, whatIs: nil, factors: [])
        spec.outWord = "Baja"
        return spec
    }

    private func subtitle(_ d: DaySummary?) -> String {
        guard let d else { return DSFmt.shortDate(model.selectedDay) }
        let time = d.cycleStart.map { " · " + Fmt.time($0) } ?? ""
        return DSFmt.shortDate(d.day) + time
    }

    private func hero(_ d: DaySummary, _ r: Double, spec: DSMetricSpec) -> some View {
        let lv = DSLevel(score: r)
        let prev = model.days.last { $0.day < d.day && $0.recovery != nil }
        var side: [(String, String)] = []
        if let n = spec.normal { side.append(("Tu normal", "\(Int(n.lowerBound.rounded()))–\(Int(n.upperBound.rounded()))")) }
        if let m = spec.mean { side.append(("Media del mes", "\(Int(m.rounded()))")) }
        if let p = prev, let pr = p.recovery {
            side.append((p.day == DayKey.shift(d.day, days: -1) ? "Ayer" : DSFmt.dayMonth(p.day), "\(Int(pr.rounded()))"))
        }
        let justified = !d.calibrating
        let advice = model.coachAdvice(for: d)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(r.rounded()))").dsFont(52, .semibold, relativeTo: .largeTitle, maxScale: 1.15).foregroundStyle(DS.t1)
                        Text("/100").dsFont(18, .medium).foregroundStyle(DS.t2)
                    }
                    DSLevelWord(level: lv, meter: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if !side.isEmpty { DSSideTable(rows: side).padding(.top, 8) }
            }
            if justified {
                DSDivider().padding(.top, 14)
                Text(advice.headline).dsFont(16).foregroundStyle(DS.t1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
                DSDivider().padding(.horizontal, -14)
                RouteLink(.metric(.esfuerzo)) {
                    HStack(spacing: 10) {
                        Image(systemName: "gauge.with.needle").font(.system(size: 14)).foregroundStyle(DS.act)
                        Text("Esfuerzo recomendado").dsFont(16, .semibold).foregroundStyle(DS.t1)
                        Spacer(minLength: 6)
                        Text("\(Int(advice.strainTarget.lowerBound))–\(Int(advice.strainTarget.upperBound))")
                            .dsFont(17, .semibold).foregroundStyle(DS.t1)
                        DSChevron()
                    }
                    .frame(minHeight: 44)
                    .padding(.top, 4)
                    .contentShape(Rectangle())
                }
            }
        }
        .dsCard(padding: 14)
    }

    /// «Qué ha influido» (puntos): each input of the score in points, from «un día normal para ti».
    @ViewBuilder
    private func influido(_ d: DaySummary) -> some View {
        let steps = RecoveryWaterfall.steps(d.contributors)
        if !steps.isEmpty, d.recovery != nil {
            let maxAbs = max(steps.map { abs($0.points) }.max() ?? 1, 1)
            let neutral = RecoveryWaterfall.neutral
            let total = (steps.last?.total ?? neutral)
            let rows = steps.map { s -> HoyPointRow in
                let c = d.contributors.first { $0.key == s.key }
                let pts = Int(s.points.rounded())
                return HoyPointRow(id: s.key, icon: icon(s.key), iconColor: color(s.key), title: title(s.key, s.label),
                                   subtitle: c.flatMap(subtitle), effect: s.points / maxAbs, good: s.points >= 0,
                                   word: (pts > 0 ? "+" : (pts < 0 ? "−" : "")) + "\(abs(pts))", route: route(s.key, d))
            }
            let diff = Int(total.rounded()) - Int(neutral.rounded())
            DSSectionHeader("Qué ha influido", note: "en puntos")
            HoyPointsList(rows: rows, axis: ("Resta", "Suma")) {
                DSDivider().padding(.horizontal, -14)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Total").dsFont(17, .semibold).foregroundStyle(DS.t1)
                        Text("un día normal para ti da \(Int(neutral.rounded()))").dsFont(14).foregroundStyle(DS.t2)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text((diff > 0 ? "+" : (diff < 0 ? "−" : "")) + "\(abs(diff))").dsFont(17, .semibold)
                            .foregroundStyle(diff >= 0 ? DSLevel.buena.ink : DSLevel.baja.ink)
                    }
                    Text("Respiración y temperatura no entran en el cálculo.").dsFont(13).foregroundStyle(DS.t3)
                }
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func icon(_ key: String) -> String {
        switch key {
        case "hrv": return "waveform.path.ecg"
        case "rhr": return "heart.fill"
        default: return "moon.fill"
        }
    }

    private func color(_ key: String) -> Color { key == "sleep" ? DS.sueno : DS.cor }

    private func title(_ key: String, _ label: String) -> String {
        switch key {
        case "hrv": return "VFC"
        case "rhr": return "FC en reposo"
        case "sleep": return "Sueño"
        default: return label
        }
    }

    private func subtitle(_ c: Contributor) -> String? {
        guard let v = c.value else { return nil }
        if c.key == "sleep" { return "\(Int(v.rounded())) % de tu necesidad" }
        let base = c.baseline.map { " · media \(Int($0.rounded()))" } ?? ""
        return "\(Int(v.rounded())) \(c.unit)\(base)"
    }

    private func route(_ key: String, _ d: DaySummary) -> Route? {
        switch key {
        case "hrv": return .metric(.hrv)
        case "rhr": return .metric(.rhr)
        case "sleep": return .sueno(.noche(day: d.day))
        default: return nil
        }
    }
}
