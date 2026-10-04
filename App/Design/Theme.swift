import SwiftUI
import PulsoStore
import PulsoAnalytics

enum Theme {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.055)
    static let card = Color(red: 0.086, green: 0.098, blue: 0.118)
    static let cardHighlight = Color(red: 0.118, green: 0.133, blue: 0.157)
    static let secondary = Color(white: 0.62)
    static let tertiary = Color(white: 0.40)

    static let green = Color(red: 0.16, green: 0.84, blue: 0.45)
    static let yellow = Color(red: 1.00, green: 0.78, blue: 0.18)
    static let red = Color(red: 1.00, green: 0.30, blue: 0.30)
    static let strain = Color(red: 0.24, green: 0.56, blue: 1.00)
    static let sleep = Color(red: 0.58, green: 0.50, blue: 1.00)
    static let stress = Color(red: 1.00, green: 0.55, blue: 0.20)
    static let hrv = Color(red: 0.25, green: 0.85, blue: 0.85)

    static func recoveryColor(_ score: Double?) -> Color {
        guard let score else { return secondary }
        switch Recovery.band(score) {
        case .green: return green
        case .yellow: return yellow
        case .red: return red
        }
    }

    static func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return Color(red: 0.55, green: 0.75, blue: 1.0)
        case 2: return Color(red: 0.25, green: 0.85, blue: 0.55)
        case 3: return Color(red: 1.0, green: 0.80, blue: 0.20)
        case 4: return Color(red: 1.0, green: 0.50, blue: 0.20)
        case 5: return Color(red: 1.0, green: 0.25, blue: 0.30)
        default: return Color(white: 0.5)
        }
    }

    static func stageColor(_ s: SleepStage) -> Color {
        switch s {
        case .awake: return Color(red: 1.0, green: 0.62, blue: 0.40)
        case .light: return Color(red: 0.55, green: 0.62, blue: 1.0)
        case .deep: return Color(red: 0.36, green: 0.28, blue: 0.95)
        case .rem: return Color(red: 0.30, green: 0.80, blue: 1.0)
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
        return v < 1 ? green : (v < 2 ? yellow : stress)
    }
}

enum Fmt {
    static func int(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "–" }
        return String(Int(v.rounded()))
    }

    static func one(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "–" }
        return String(format: "%.1f", v)
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

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondary)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(Theme.tertiary)
            }
        }
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
                        .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    if !unit.isEmpty {
                        Text(unit).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .frame(width: size, height: size)
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(color)
        }
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
                Text(detail).font(.caption2.weight(.medium)).foregroundStyle(detailColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Header with the selected day and arrows to move between days.
struct DayHeader: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack {
            Button { model.shiftSelectedDay(-1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 36, height: 36)
            }
            Spacer()
            VStack(spacing: 2) {
                Text(Fmt.dayTitle(model.selectedDay)).font(.headline).foregroundStyle(.white)
                StrapStatusLine()
            }
            Spacer()
            Button { model.shiftSelectedDay(1) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 36, height: 36)
            }
            .disabled(model.selectedDay >= DayKey.string(Date()))
        }
        .tint(.white)
    }
}

struct StrapStatusLine: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2).foregroundStyle(Theme.secondary)
            if let b = model.battery {
                Image(systemName: batteryIcon(b)).font(.caption2).foregroundStyle(b < 20 ? Theme.red : Theme.secondary)
                Text("\(Int(b))%").font(.caption2).monospacedDigit().foregroundStyle(Theme.secondary)
            }
        }
    }

    private func batteryIcon(_ b: Double) -> String {
        if model.charging == true { return "battery.100.bolt" }
        switch b {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<65: return "battery.50"
        case ..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    private var color: Color {
        switch model.strapState {
        case .ready: return Theme.green
        case .syncing: return Theme.strain
        case .connecting, .scanning, .pairing: return Theme.yellow
        default: return Theme.red
        }
    }

    private var text: String {
        if model.analyzing { return "Analizando \(Int(model.analysisProgress * 100))%" }
        switch model.strapState {
        case .ready: return "Sincronizado \(Fmt.relative(model.lastSync))"
        case .syncing(let n): return "Descargando… \(n) s"
        case .connecting: return "Buscando tu pulsera"
        case .scanning: return "Escaneando"
        case .pairing: return "Emparejando"
        case .pairingRefused: return "Emparejamiento rechazado"
        case .bluetoothOff: return "Bluetooth apagado"
        case .unauthorized: return "Sin permiso Bluetooth"
        case .noStrap: return "Sin pulsera"
        case .unsupported: return "Pulsera no compatible"
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
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(Theme.secondary)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(message).font(.subheadline).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
