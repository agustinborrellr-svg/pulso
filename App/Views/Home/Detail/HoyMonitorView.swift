import SwiftUI
import PulsoStore
import PulsoAnalytics

/// 03 / 04 Monitor de salud: your pulse now, last night's five vitals as segments (out of range: amber with the value and
/// one line saying why) and one row per vital with its range, a small bar and the value; stress, the health report.
struct HoyMonitorView: View {
    @EnvironmentObject var model: AppModel
    @State private var recent: [(ts: Int, hr: Int)] = []

    var body: some View {
        let all = model.vitalReadings()
        let readings = HoyMonitor.order.compactMap { id in all.first { $0.id == id } }
        let stress = model.selected?.stressPoints.last?.v
        DSScreen("Monitor de salud", subtitle: DSFmt.shortDate(model.selectedDay), back: "Hoy") {
            HoyAhora(recent: recent)
            if readings.isEmpty {
                DSEmptyState(icon: "heart.text.square", title: "Sin constantes", message: "Aparecen tras tu primera noche con la pulsera.")
            } else {
                DSSectionHeader("Anoche")
                VStack(spacing: 0) {
                    HoyMonitor(day: model.selected, title: "Constantes", chevron: false, showStress: true)
                    DSDivider().padding(.horizontal, 2)
                    ForEach(readings.indices, id: \.self) { i in
                        if i > 0 { DSDivider(inset: 54) }
                        RouteLink(.metric(HoyVital.kind(readings[i].id))) { HoyVitalRow(reading: readings[i]) }
                    }
                }
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            }
            if let v = stress {
                RouteLink(.metric(.estres)) {
                    HStack(spacing: 14) {
                        Image(systemName: "wind").font(.system(size: 17)).foregroundStyle(DS.bien).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Estrés").dsFont(17, .semibold).foregroundStyle(DS.t1)
                            Text("\(HoyStress.word(v))\(model.selectedDay >= model.currentDayKey ? " · ahora" : "")")
                                .dsFont(14, .semibold).foregroundStyle(HoyStress.color(v))
                        }
                        Spacer(minLength: 6)
                        Text(Fmt.dec(v)).dsFont(20, .semibold).foregroundStyle(DS.t1)
                        DSChevron()
                    }
                    .padding(.vertical, 8)
                    .dsCard(padding: 14)
                    .contentShape(Rectangle())
                }
            }
            if !readings.isEmpty {
                Text("Cada constante, frente a tus 30 noches anteriores.").dsFont(13).foregroundStyle(DS.t3).padding(.horizontal, 4)
            }
            RouteLink(.salud(.informeSalud)) {
                HoyLinkCard(icon: "doc.text", title: "Informe de salud", subtitle: "PDF para tu médico")
            }
            Text("No es un dispositivo médico.").dsFont(13).foregroundStyle(DS.t3).padding(.horizontal, 4)
        }
        .task {
            while !Task.isCancelled {
                recent = model.recentPulse()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}

/// One vital of the monitor: icon, name with your range (or «Alta para ti» out of it), a small bar and the value.
struct HoyVitalRow: View {
    let reading: VitalReading

    var body: some View {
        let r = reading
        let off = r.level == .orange || r.level == .red
        let ink = DSLevel(r.level)?.ink ?? DS.t2
        HStack(spacing: 12) {
            Image(systemName: HoyMonitor.icons[r.id] ?? r.icon).font(.system(size: 16))
                .foregroundStyle(HoyVital.color(r.id)).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(HoyVital.shortTitle(r.id)).dsFont(17, .medium).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                Text(off ? HoyVital.capitalized(r.chip) : HoyVital.rangeText(r)).dsFont(14, off ? .semibold : .regular)
                    .foregroundStyle(off ? ink : DS.t2).lineLimit(1)
            }
            .frame(width: 118, alignment: .leading)
            HoyMiniRange(reading: r).frame(maxWidth: .infinity).frame(height: 16)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(r.asDeviation ? r.monitorValue : r.value).dsFont(19, .semibold).foregroundStyle(off ? ink : DS.t1)
                Text(r.unit == "%" ? " %" : r.unit).dsFont(13).foregroundStyle(DS.t2)
            }
            .lineLimit(1)
            .fixedSize()
            DSChevron()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Track with your range as a faint band and the night as a dot (green inside, the level's colour outside).
struct HoyMiniRange: View {
    let reading: VitalReading

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            if let r = reading.range, let o = reading.outer {
                let span = max(o.upperBound - o.lowerBound, 0.0001)
                let lo = min(o.lowerBound - span * 0.15, reading.raw), hi = max(o.upperBound + span * 0.15, reading.raw)
                let x = { (v: Double) in w * CGFloat((v - lo) / max(hi - lo, 0.0001)) }
                let lv = DSLevel(reading.level) ?? .buena
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.fill).frame(height: 4)
                    Rectangle().fill(DS.buena.opacity(0.22))
                        .overlay(Rectangle().strokeBorder(DS.buena.opacity(0.35), lineWidth: 0.5))
                        .frame(width: max(x(r.upperBound) - x(r.lowerBound), 3), height: 16)
                        .offset(x: x(r.lowerBound))
                    Circle().fill(lv.mark).overlay(Circle().stroke(DS.card, lineWidth: 2))
                        .frame(width: 11, height: 11)
                        .offset(x: min(max(x(reading.raw) - 5.5, 0), w - 11))
                }
                .frame(height: 16)
            } else {
                Capsule().fill(DS.fill).frame(height: 4).frame(maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Names, colours and routes of the five vitals.
enum HoyVital {
    static func kind(_ id: String) -> MetricKind {
        switch id {
        case "hrv": return .hrv
        case "rhr": return .rhr
        case "resp": return .resp
        case "spo2": return .spo2
        default: return .temp
        }
    }

    static func id(_ kind: MetricKind) -> String {
        switch kind {
        case .hrv: return "hrv"
        case .rhr: return "rhr"
        case .resp: return "resp"
        case .spo2: return "spo2"
        default: return "temp"
        }
    }

    static func color(_ id: String) -> Color { ["hrv", "rhr"].contains(id) ? DS.cor : DS.cons }

    static func shortTitle(_ id: String) -> String {
        switch id {
        case "hrv": return "VFC"
        case "rhr": return "FC en reposo"
        case "resp": return "Respiración"
        case "spo2": return "SpO₂"
        default: return "Temp. piel"
        }
    }

    static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// "52–64", "±0,4" (skin temperature), "calibrando".
    static func rangeText(_ r: VitalReading) -> String {
        guard let range = r.range else { return "calibrando" }
        if r.asDeviation { return "±" + r.format((range.upperBound - range.lowerBound) / 2) }
        return "\(r.format(range.lowerBound))–\(r.format(range.upperBound))"
    }

    static func signed(_ v: Double, _ fmt: (Double) -> String) -> String {
        (v >= 0.05 ? "+" : (v <= -0.05 ? "−" : "")) + fmt(abs(v))
    }
}

/// Stress words and colours of the redesign (Calma / Medio / Alto).
enum HoyStress {
    static func word(_ v: Double) -> String { v < 1 ? "Calma" : (v < 2 ? "Medio" : "Alto") }
    static func color(_ v: Double) -> Color { v < 1 ? DSLevel.buena.ink : (v < 2 ? DS.bien : DSLevel.justa.ink) }
    static func mark(_ v: Double) -> Color { v < 1 ? DS.buena : (v < 2 ? DS.bien : DS.justa) }
}
