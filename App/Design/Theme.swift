import SwiftUI
import PulsoStore
import PulsoAnalytics

enum Theme {
    // Values live in `PulsoPalette` (shared with the widgets); these names are the app's vocabulary.
    static let background = PulsoPalette.background
    static let backgroundTop = PulsoPalette.backgroundTop
    static let card = PulsoPalette.card
    static let cardHighlight = PulsoPalette.cardHighlight
    static let hairline = Color.white.opacity(0.06)
    static let secondary = PulsoPalette.secondary
    static let tertiary = PulsoPalette.tertiary

    static let green = PulsoPalette.recoveryHigh
    static let yellow = PulsoPalette.recoveryMid
    static let red = PulsoPalette.recoveryLow
    static let strain = PulsoPalette.strain
    static let sleep = PulsoPalette.sleep
    static let stress = PulsoPalette.stress
    static let hrv = PulsoPalette.hrv
    /// Better / worse than your usual (arrows next to each metric).
    static let better = PulsoPalette.better
    static let worse = PulsoPalette.worse
    static let stressLow = PulsoPalette.stressLow
    static let stressMid = PulsoPalette.stressMid
    static let stressHigh = PulsoPalette.stressHigh
    static let link = PulsoPalette.link

    static func recoveryColor(_ score: Double?) -> Color {
        guard let score else { return secondary }
        switch Recovery.band(score) {
        case .green: return green
        case .yellow: return yellow
        case .red: return red
        }
    }

    static func zoneColor(_ zone: Int) -> Color { PulsoPalette.zone(zone) }

    static func stageColor(_ s: SleepStage) -> Color {
        switch s {
        case .awake: return PulsoPalette.stageAwake
        case .light: return PulsoPalette.stageLight
        case .deep: return PulsoPalette.stageDeep
        case .rem: return PulsoPalette.stageREM
        }
    }

    static func stageName(_ s: SleepStage) -> String {
        switch s {
        case .awake: return "Despierto"
        case .light: return "Ligero"
        case .deep: return "Profundo"
        case .rem: return "REM"
        }
    }

    static func stressColor(_ v: Double?) -> Color {
        guard let v else { return secondary }
        return v < 1 ? stressLow : (v < 2 ? stressMid : stressHigh)
    }

    static func stressLevel(_ v: Double?) -> String {
        guard let v else { return "–" }
        return v < 1 ? "BAJO" : (v < 2 ? "MEDIO" : "ALTO")
    }
}

enum Fmt {
    static func int(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "–" }
        return String(Int(v.rounded()))
    }

    static func one(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "–" }
        return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }

    static func pct(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "–" }
        return "\(Int((v * 100).rounded()))%"
    }

    static func hm(_ minutes: Double?) -> String {
        guard let m = minutes, m.isFinite else { return "–" }
        let total = Int(m.rounded())
        return "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }

    static func signed(_ v: Double?, digits: Int = 1) -> String {
        guard let v, v.isFinite else { return "–" }
        return String(format: "%+.\(digits)f", v)
    }

    static func time(_ ts: Int?) -> String {
        guard let ts else { return "–" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    static func clock(_ date: Date?) -> String {
        guard let date else { return "–" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func dayTitle(_ key: String) -> String {
        let today = DayKey.string(Date())
        if key == today { return "Hoy" }
        if key == DayKey.shift(today, days: -1) { return "Ayer" }
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEEE d MMM"
        return f.string(from: d).capitalized
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "nunca" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}


// MARK: - Components

/// Legacy name for `PCard`: same surface, kept so older screens compile unchanged.
struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.cardPadding
    @ViewBuilder var content: Content

    var body: some View {
        PCard(padding: padding) { content }
    }
}

/// Legacy name for `CardHeader`'s title style.
struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        CardHeader(title: title, subtitle: subtitle)
    }
}

/// A circular score ring.
struct ScoreRing: View {
    let progress: Double // 0…1
    let color: Color
    let value: String
    let label: String
    var unit: String = ""
    var size: CGFloat = 104
    var lineWidth: CGFloat = 10

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: progress)
                VStack(spacing: 0) {
                    Text(value)
                        .scaledFont(size * 0.27, weight: .bold, design: .rounded, relativeTo: .title1, maxScale: 1.15)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    if !unit.isEmpty {
                        Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(lineWidth)
            }
            .frame(width: size, height: size)
            Caps(label, size: 11, color: color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(unit.isEmpty ? value : "\(value) \(unit)")
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var detail: String?
    var detailColor: Color = Theme.secondary
    var icon: String?
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.caption).foregroundStyle(tint)
                }
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit().foregroundStyle(.white)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(Theme.secondary) }
            }
            if let detail {
                Text(detail).font(.caption.weight(.medium)).foregroundStyle(detailColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

/// Header with the selected day and arrows to move between days.
struct DayHeader: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            Button { model.shiftSelectedDay(-1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Día anterior")
            Spacer()
            VStack(spacing: 2) {
                Text(Fmt.dayTitle(model.selectedDay)).font(.headline).foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                StrapStatusLine()
            }
            Spacer()
            Button { model.shiftSelectedDay(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Día siguiente")
            .disabled(model.selectedDay >= model.currentDayKey)
        }
        .tint(.white)
    }
}

/// One-line strap status: link + data freshness + battery. Same wording as `ConnectionBadge`.
struct StrapStatusLine: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let status = ConnectionStatus(model)
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 7, height: 7)
            Text(status.line).font(.caption).foregroundStyle(Theme.secondary)
            if let b = model.battery {
                Image(systemName: BatteryGlyph.symbol(b, charging: model.charging == true)).font(.caption)
                    .foregroundStyle(b < 20 ? Theme.red : Theme.secondary)
                Text("\(Int(b))%").font(.caption).monospacedDigit().foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityText(battery: model.battery))
    }
}

enum BatteryGlyph {
    static func symbol(_ b: Double, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch b {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<65: return "battery.50"
        case ..<90: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// Horizontal stacked bar of minutes per zone / stage.
struct StackedBar: View {
    let parts: [(value: Double, color: Color)]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let total = max(parts.reduce(0) { $0 + $1.value }, 0.0001)
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    if p.value > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(p.color)
                            .frame(width: max(2, (geo.size.width - CGFloat(parts.count) * 2) * p.value / total))
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
