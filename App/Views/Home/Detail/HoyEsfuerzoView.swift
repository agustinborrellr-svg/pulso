import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoIntegrations

/// 02 Esfuerzo: the day's strain against the coach's target, energy and heart rate, zones, the day's activities, the
/// week in bars (light / moderate / strenuous days) and «Qué es».
struct HoyEsfuerzoView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @State private var period: DSPeriod = .week

    var body: some View {
        let day = model.selected
        DSScreen("Esfuerzo", subtitle: subtitle(day), back: "Hoy") {
            if let d = day {
                hero(d)
                stats(d)
                if d.zoneMinutes.reduce(0, +) > 0 {
                    DSSectionHeader("Zonas de pulso")
                    HoyZonesCard(minutes: d.zoneMinutes)
                }
                DSSectionHeader("Actividades")
                activities(d)
                week(d)
            } else {
                DSEmptyState(icon: "flame", title: "Sin esfuerzo", message: "Todavía no hay datos de este día.")
            }
            DSSectionHeader("Qué es")
            DSWhatIs(text: "La carga del día sobre tu cuerpo, en una escala que llega a 21. Suma el tiempo con el pulso alto, entrenando o no; cada punto cuesta más que el anterior.",
                     footnote: nil)
        }
    }

    private func subtitle(_ d: DaySummary?) -> String {
        let date = DSFmt.shortDate(d?.day ?? model.selectedDay)
        if let d, model.isOpenCycle(d) { return date + " · en curso" }
        return date
    }

    private func target(_ d: DaySummary) -> ClosedRange<Double>? {
        d.recovery == nil || d.calibrating ? nil : model.coachAdvice(for: d).strainTarget
    }

    private func hero(_ d: DaySummary) -> some View {
        let s = d.strain ?? 0
        let t = target(d)
        let prev = model.day(DayKey.shift(d.day, days: -1))?.strain
        var side: [(String, String)] = []
        if let t, s < t.lowerBound, model.isOpenCycle(d) { side.append(("Te quedan", Fmt.dec(t.lowerBound - s))) }
        if let prev { side.append(("Ayer", Fmt.dec(prev))) }
        return HoyHero(value: Fmt.dec(d.strain), side: side) {
            if let t {
                Text("Objetivo \(Int(t.lowerBound))–\(Int(t.upperBound))").dsFont(16, .semibold).foregroundStyle(DS.t2)
                Text("según tu Recarga").dsFont(14).foregroundStyle(DS.t3)
            }
        } footer: {
            HoyStrainTrack(value: s, target: t, yesterday: prev).padding(.top, 16)
        }
    }

    private func stats(_ d: DaySummary) -> some View {
        DSGroup {
            if let kcal = d.kcal {
                RouteLink(.metric(.calorias)) {
                    DSRow(icon: "flame.fill", iconColor: DS.act, label: "Calorías",
                          subtitle: d.activeKcal.map { "\(DSFmt.thousands($0)) activas" }, value: "\(DSFmt.thousands(kcal)) kcal", chevron: true)
                }
            }
            if let steps = d.steps, steps > 0 {
                RouteLink(.metric(.pasos)) {
                    DSRow(icon: "shoeprints.fill", iconColor: DS.act, label: "Pasos", value: DSFmt.thousands(Double(steps)), chevron: true)
                }
            }
            if let hr = d.avgHR, hr > 0 {
                DSRow(icon: "heart.fill", iconColor: DS.cor, label: "FC media", value: "\(Int(hr.rounded())) lpm")
            }
            if let hr = d.maxHR, hr > 0 {
                DSRow(icon: "heart.fill", iconColor: DS.cor, label: "FC máxima", value: "\(Int(hr.rounded())) lpm")
            }
        }
    }

    private func activities(_ d: DaySummary) -> some View {
        let list = model.activities(on: d).filter { if case .workout = $0.kind { return true } else { return false } }
        return VStack(spacing: 0) {
            ForEach(list) { a in
                RouteLink(a.route) {
                    HStack(spacing: 12) {
                        DSActivityChip(icon: a.isBreathing ? "wind" : a.icon, color: a.hoyColor, text: Fmt.hmm(Double(a.end - a.start) / 60))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.isBreathing ? "Recuperación" : a.title).dsFont(17, .semibold).foregroundStyle(DS.t1).lineLimit(1)
                            Text("\(Fmt.time(a.start)) – \(Fmt.time(a.end))").dsFont(13).foregroundStyle(DS.t2)
                        }
                        Spacer(minLength: 6)
                        if case .workout(let w) = a.kind, w.strain > 0 {
                            Text(Fmt.dec(w.strain)).dsFont(18, .semibold).foregroundStyle(DS.t1)
                        }
                        DSChevron()
                    }
                    .frame(minHeight: 62)
                    .contentShape(Rectangle())
                }
                DSDivider()
            }
            Button { router.open(.hoy(.anadirActividad)) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus").font(.system(size: 17, weight: .medium)).foregroundStyle(DS.t2).frame(width: 76)
                    Text("Agregar actividad").dsFont(17, .semibold).foregroundStyle(DS.t1)
                    Spacer()
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .dsCard(padding: 14)
    }

    @ViewBuilder
    private func week(_ d: DaySummary) -> some View {
        let bars = HoyBarSeries.bars(model.days, end: d.day, period: period) { $0.strain }
        let values = bars.compactMap(\.value)
        if !values.isEmpty {
            let days = model.days.filter { $0.day <= d.day && $0.day > DayKey.shift(d.day, days: -period.days) }.compactMap(\.strain)
            DSSectionHeader("Tu semana")
            VStack(alignment: .leading, spacing: 14) {
                DSSegmented(options: DSPeriod.standard.map { ($0, $0.label) }, selection: $period).frame(width: 168)
                HoyBars(bars: bars, color: DS.act, maxValue: 14, band: target(d), bandLabel: target(d) == nil ? nil : "objetivo de hoy",
                        height: 110)
                DSDivider()
                DSStatStrip(stats: [
                    DSStat(label: "Ligero", value: "\(days.filter { $0 <= 10 }.count)", unit: "días"),
                    DSStat(label: "Moderado", value: "\(days.filter { $0 > 10 && $0 <= 14 }.count)", unit: "días"),
                    DSStat(label: "Extenuante", value: "\(days.filter { $0 > 14 }.count)", unit: "días"),
                ])
            }
            .dsCard(padding: 14)
        }
    }
}

/// The 0–21 track of the strain hero: filled up to the value, the target band with its label and yesterday's mark.
struct HoyStrainTrack: View {
    let value: Double
    let target: ClosedRange<Double>?
    let yesterday: Double?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                let x = { (v: Double) in w * CGFloat(min(max(v / 21, 0), 1)) }
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill).frame(height: 6)
                    if let t = target {
                        Rectangle().fill(DS.act.opacity(0.22))
                            .overlay(Rectangle().strokeBorder(DS.act.opacity(0.35), lineWidth: 0.5))
                            .frame(width: max(x(t.upperBound) - x(t.lowerBound), 2), height: 18)
                            .offset(x: x(t.lowerBound))
                    }
                    Capsule().fill(DS.act).frame(width: max(x(value), 6), height: 6)
                    if let y = yesterday {
                        Circle().strokeBorder(DS.t2, lineWidth: 1.5).frame(width: 9, height: 9).offset(x: x(y) - 4.5)
                    }
                    Circle().fill(DS.act).overlay(Circle().stroke(DS.card, lineWidth: 2)).frame(width: 12, height: 12)
                        .offset(x: x(value) - 6)
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            if let t = target {
                GeometryReader { g in
                    Text("objetivo").dsFont(12, .semibold, relativeTo: .caption1).foregroundStyle(DS.act)
                        .position(x: g.size.width * CGFloat((t.lowerBound + t.upperBound) / 2 / 21), y: 7)
                }
                .frame(height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Esfuerzo \(Fmt.dec(value)) de 21")
    }
}
