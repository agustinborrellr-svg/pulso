import SwiftUI
import PulsoStore
import PulsoAnalytics

/// The 7 day keys ending on `day`, oldest first.
private func lastWeek(_ day: String) -> [String] { (0..<7).map { DayKey.shift(day, days: $0 - 6) } }

private func initial(_ key: String) -> String {
    guard let d = DayKey.date(key) else { return "" }
    return ["D", "L", "M", "X", "J", "V", "S"][Calendar(identifier: .gregorian).component(.weekday, from: d) - 1]
}

/// Seven small vertical bars (0…1), the last one brighter.
private struct MiniBars: View {
    let values: [Double?]
    let color: Color
    var height: CGFloat = 26
    var line: Double?

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(v == nil ? Hoy.fill : color.opacity(i == values.count - 1 ? 1 : 0.6))
                            .frame(height: max(3, g.size.height * CGFloat(min(max(v ?? 0.04, 0), 1))))
                            .frame(maxWidth: .infinity)
                    }
                }
                if let line {
                    Rectangle().fill(Hoy.t3).frame(height: 1)
                        .mask(HStack(spacing: 2) { ForEach(0..<40, id: \.self) { _ in Rectangle().frame(width: 2) } })
                        .offset(y: -g.size.height * CGFloat(min(max(line, 0), 1)))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Tu semana

struct HoyWeekBlock: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary

    var body: some View {
        let keys = lastWeek(day.day)
        let ds = keys.map { model.day($0) }
        VStack(alignment: .leading, spacing: 10) {
            HoySectionTitle("Tu semana")
            VStack(spacing: 12) {
                row("Recarga", ds.map { $0?.recovery.map { $0 / 100 } }, Hoy.recarga) { v in "\(Int((v * 100).rounded()))" }
                row("Sueño", ds.map { $0?.sleepPerformance }, Hoy.sueno) { v in "\(Int((v * 100).rounded()))" }
                row("Esfuerzo", ds.map { $0?.strain.map { $0 / 21 } }, Hoy.act) { v in Fmt.dec(v * 21) }
                HStack(spacing: 12) {
                    Spacer().frame(width: 74)
                    HStack(spacing: 5) {
                        ForEach(keys, id: \.self) { k in
                            Text(initial(k)).hoyFont(11, k == day.day ? .bold : .medium, relativeTo: .caption2)
                                .foregroundStyle(k == day.day ? Hoy.t1 : Hoy.t3).frame(maxWidth: .infinity)
                        }
                    }
                    Spacer().frame(width: 56)
                }
            }
            .hoyCard(padding: 16)
        }
    }

    private func row(_ title: String, _ v: [Double?], _ color: Color, _ fmt: (Double) -> String) -> some View {
        let known = v.compactMap { $0 }
        let mean = known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
        return HStack(spacing: 12) {
            Text(title).hoyFont(15, .medium).foregroundStyle(Hoy.t1).frame(width: 74, alignment: .leading)
            MiniBars(values: v, color: color)
            VStack(alignment: .trailing, spacing: 0) {
                Text(mean.map(fmt) ?? "–").hoyFont(15, .semibold).foregroundStyle(Hoy.t1)
                Text("media").hoyFont(11, relativeTo: .caption2).foregroundStyle(Hoy.t3)
            }
            .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Carga de la semana

struct HoyLoadBlock: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let p = model.trainingLoad.last, let acwr = p.acwr {
            let status = TrainingLoad.status(model.trainingLoad)
            let lv: HoyLevel = acwr > 1.5 ? .baja : (acwr > 1.3 || acwr < 0.8 ? .justa : .buena)
            VStack(alignment: .leading, spacing: 10) {
                HoySectionTitle("Carga de la semana")
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        HoyValue(value: Fmt.dec(acwr), unit: "×", size: 28)
                        Spacer()
                        HStack(spacing: 5) {
                            HoyDot(color: lv.mark)
                            Text(status.label).hoyFont(15, .semibold).foregroundStyle(lv.ink)
                        }
                    }
                    GeometryReader { g in
                        let lo = 0.4, hi = 1.8
                        let x = { (v: Double) in g.size.width * CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) }
                        ZStack(alignment: .leading) {
                            Capsule().fill(Hoy.fill).frame(height: 6)
                            Rectangle().fill(HoyLevel.buena.mark.opacity(0.35)).frame(width: x(1.3) - x(0.8), height: 6).offset(x: x(0.8))
                            Circle().fill(Hoy.act).overlay(Circle().stroke(Hoy.card, lineWidth: 2)).frame(width: 13, height: 13)
                                .offset(x: x(acwr) - 6.5)
                        }
                        .frame(height: g.size.height)
                    }
                    .frame(height: 14)
                    Text("Tu carga de los últimos 7 días frente a la de tus últimas 4 semanas.")
                        .hoyFont(13, relativeTo: .footnote).foregroundStyle(Hoy.t2)
                }
                .hoyCard(padding: 16)
            }
        }
    }
}

// MARK: - Pasos y movimiento

struct HoyStepsBlock: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary

    var body: some View {
        let keys = lastWeek(day.day)
        let ds = keys.map { model.day($0) }
        let steps = ds.map { $0?.steps.map(Double.init) }
        let known = steps.compactMap { $0 }.filter { $0 > 0 }
        let top = max(known.max() ?? 1, 1)
        let mean = known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
        let active = ds.compactMap { $0 }.map { $0.zoneMinutes.prefix(5).reduce(0, +) }.filter { $0 > 0 }
        VStack(alignment: .leading, spacing: 10) {
            HoySectionTitle("Pasos y movimiento")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Media de pasos").hoyFont(13, relativeTo: .footnote).foregroundStyle(Hoy.t2)
                        HoyValue(value: HoyFmt.thousands(mean), size: 22)
                    }
                    Spacer()
                    if !active.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Minutos activos").hoyFont(13, relativeTo: .footnote).foregroundStyle(Hoy.t2)
                            HoyValue(value: "\(Int((active.reduce(0, +) / Double(active.count)).rounded()))", unit: "min/día", size: 22)
                        }
                    }
                }
                MiniBars(values: steps.map { $0.map { $0 / top } }, color: Hoy.act, height: 52, line: mean.map { $0 / top })
                HStack(spacing: 5) {
                    ForEach(keys, id: \.self) { k in
                        Text(initial(k)).hoyFont(11, k == day.day ? .bold : .medium, relativeTo: .caption2)
                            .foregroundStyle(k == day.day ? Hoy.t1 : Hoy.t3).frame(maxWidth: .infinity)
                    }
                }
            }
            .hoyCard(padding: 16)
        }
    }
}

// MARK: - Racha

struct HoyStreakBlock: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary

    private static let goal = 7.0 * 60

    var body: some View {
        let keys = (0..<14).map { DayKey.shift(day.day, days: $0 - 13) }
        let mins = keys.map { model.day($0)?.sleepMinutes }
        var streak = 0
        for m in mins.reversed() {
            guard let m, m >= Self.goal else { break }
            streak += 1
        }
        let top = max(mins.compactMap { $0 }.max() ?? Self.goal, Self.goal + 60)
        return VStack(alignment: .leading, spacing: 10) {
            HoySectionTitle("Racha")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    HoyValue(value: "\(streak)", unit: streak == 1 ? "noche" : "noches", size: 28)
                    Spacer()
                    Text("seguidas de más de 7 h").hoyFont(13, relativeTo: .footnote).foregroundStyle(Hoy.t2)
                }
                GeometryReader { g in
                    ZStack(alignment: .bottomLeading) {
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(mins.enumerated()), id: \.offset) { _, m in
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(m == nil ? Hoy.fill : ((m ?? 0) >= Self.goal ? Hoy.sueno : Hoy.fill2))
                                    .frame(height: max(3, g.size.height * CGFloat((m ?? 20) / top)))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        Rectangle().fill(Hoy.t3).frame(height: 1)
                            .mask(HStack(spacing: 2) { ForEach(0..<60, id: \.self) { _ in Rectangle().frame(width: 2) } })
                            .offset(y: -g.size.height * CGFloat(Self.goal / top))
                    }
                }
                .frame(height: 48)
                .accessibilityHidden(true)
            }
            .hoyCard(padding: 16)
        }
    }
}

// MARK: - Me voy a dormir (ampliado)

struct HoyBedtimeBlock: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary
    @State private var open = false

    var body: some View {
        let keys = lastWeek(day.day)
        let nights = keys.compactMap { k -> (String, Int, Int)? in
            guard let d = model.day(k), let a = d.sleepStart, let b = d.sleepEnd else { return nil }
            return (k, a, b)
        }
        VStack(alignment: .leading, spacing: 10) {
            HoySectionTitle("Me voy a dormir")
            Button { open = true } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 18)).foregroundStyle(Hoy.sueno)
                        Text("Prepara la noche").hoyFont(17, .semibold).foregroundStyle(Hoy.t1)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Hoy.t3)
                    }
                    if !nights.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(nights, id: \.0) { n in
                                HStack(spacing: 10) {
                                    Text(initial(n.0)).hoyFont(11, .medium, relativeTo: .caption2).foregroundStyle(Hoy.t3).frame(width: 12)
                                    GeometryReader { g in
                                        // 20:00 → 12:00 next day.
                                        let x = { (ts: Int) -> CGFloat in
                                            let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
                                            var h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
                                            if h < 12 { h += 24 }
                                            return g.size.width * CGFloat(min(max((h - 20) / 16, 0), 1))
                                        }
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Hoy.fill).frame(height: 3)
                                            Capsule().fill(Hoy.sueno.opacity(0.8)).frame(width: max(4, x(n.2) - x(n.1)), height: 6).offset(x: x(n.1))
                                        }
                                        .frame(height: g.size.height)
                                    }
                                    .frame(height: 8)
                                }
                            }
                            HStack {
                                Text("20")
                                Spacer()
                                Text("00")
                                Spacer()
                                Text("04")
                                Spacer()
                                Text("08")
                                Spacer()
                                Text("12")
                            }
                            .hoyFont(11, .medium, relativeTo: .caption2).foregroundStyle(Hoy.t3)
                            .padding(.leading, 22)
                        }
                        .accessibilityHidden(true)
                    }
                }
                .hoyCard(padding: 16)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $open) { BedtimeView().environmentObject(model) }
        }
    }
}

// MARK: - Constantes vitales

struct HoyVitalsBlock: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let all = model.vitalReadings()
        let rows = HoyMonitor.order.compactMap { id in all.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 10) {
            RouteLink(.hoy(.monitor)) { HoySectionTitle("Constantes vitales", chevron: true) }
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(Hoy.sep).frame(height: 1) }
                    let lv = HoyLevel(r.level)
                    HStack(spacing: 10) {
                        Image(systemName: HoyMonitor.icons[r.id] ?? r.icon).font(.system(size: 14))
                            .foregroundStyle(["hrv", "rhr"].contains(r.id) ? Hoy.cor : Hoy.cons).frame(width: 20)
                        Text(r.short).hoyFont(15, .medium).foregroundStyle(Hoy.t1)
                        Spacer(minLength: 6)
                        HoyValue(value: r.value, unit: r.unit, size: 17)
                        HStack(spacing: 4) {
                            HoyDot(color: lv?.mark ?? Hoy.fill2)
                            Text(r.level == .none ? "calibrando" : (r.level == .green ? "en rango" : "fuera")).hoyFont(13, relativeTo: .footnote)
                                .foregroundStyle(lv?.ink ?? Hoy.t3)
                        }
                        .frame(width: 84, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Hoy.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
