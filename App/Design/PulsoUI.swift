import SwiftUI
import PulsoStore

// MARK: - Surfaces

/// Screen background: slate gradient, lighter at the top.
struct PulsoBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.backgroundTop, Theme.background, Theme.background],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

/// Rounded slate card.
struct PCard<Content: View>: View {
    var padding: CGFloat = 16
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Type

/// "VARIABILIDAD DE LA FRECUENCIA CARDÍACA": the uppercase, tracked label used for every title.
struct Caps: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = .white
    var weight: Font.Weight = .bold

    init(_ text: String, size: CGFloat = 13, color: Color = .white, weight: Font.Weight = .bold) {
        self.text = text
        self.size = size
        self.color = color
        self.weight = weight
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: weight))
            .tracking(size * 0.11)
            .foregroundStyle(color)
    }
}

/// Card header: caps title, optional subtitle, chevron when it navigates.
struct CardHeader: View {
    let title: String
    var subtitle: String?
    var chevron = false
    var info: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Caps(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 8)
            if let info {
                Button(action: info) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// Big number with a small unit: "6:23", "45 %", "12,2".
struct BigValue: View {
    let value: String
    var unit: String = ""
    var size: CGFloat = 40
    var color: Color = .white

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            if !unit.isEmpty {
                Text(unit).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(color.opacity(0.85))
            }
        }
    }
}

// MARK: - Comparison

enum Trend {
    case up, down, flat
}

/// Whether a value is above or below its usual, and whether that is good.
struct Delta {
    let trend: Trend
    let good: Bool?

    /// `higherIsBetter` nil = neutral metric (arrow without judgement).
    init(_ value: Double?, _ baseline: Double?, higherIsBetter: Bool?, tolerance: Double = 0.02) {
        guard let value, let baseline, baseline != 0 else {
            trend = .flat
            good = nil
            return
        }
        let rel = (value - baseline) / abs(baseline)
        if abs(rel) < tolerance {
            trend = .flat
            good = nil
        } else {
            trend = rel > 0 ? .up : .down
            good = higherIsBetter.map { $0 == (rel > 0) }
        }
    }

    var color: Color {
        guard let good else { return Theme.secondary }
        return good ? Theme.better : Theme.worse
    }
}

/// ▲ / ▼ / • next to a value.
struct DeltaMark: View {
    let delta: Delta
    var size: CGFloat = 9

    var body: some View {
        Group {
            switch delta.trend {
            case .up: Image(systemName: "arrowtriangle.up.fill")
            case .down: Image(systemName: "arrowtriangle.down.fill")
            case .flat: Image(systemName: "circle.fill").scaleEffect(0.6)
            }
        }
        .font(.system(size: size))
        .foregroundStyle(delta.color)
    }
}

/// "▲ 3,9 vs. la semana anterior" chip.
struct DeltaChip: View {
    let text: String
    let delta: Delta

    var body: some View {
        HStack(spacing: 5) {
            DeltaMark(delta: delta, size: 8)
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(delta.good == nil ? Theme.secondary : delta.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background((delta.good == nil ? Color.white : delta.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Rows

/// Dashboard row: icon, caps title, value with the usual underneath and an arrow.
struct MetricRow: View {
    let icon: String
    let title: String
    let value: String
    var baseline: String?
    var delta: Delta?
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.secondary)
                .frame(width: 24)
            Caps(title, size: 12.5, weight: .semibold)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 5) {
                    Text(value).font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                    if let delta { DeltaMark(delta: delta) }
                }
                if let baseline {
                    Text(baseline).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondary)
                        .padding(.trailing, delta == nil ? 0 : 14)
                }
            }
            if chevron {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Wide action row ("+ AGREGAR ACTIVIDAD").
struct ActionRow: View {
    let icon: String
    let title: String
    var detail: String?
    var destructive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 24)
                Caps(title, size: 13, color: destructive ? Theme.red : .white, weight: .semibold)
                Spacer()
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
            .foregroundStyle(destructive ? Theme.red : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let detail {
                Text(detail).font(.caption).foregroundStyle(Theme.secondary).padding(.horizontal, 14)
            }
        }
    }
}

/// Behaviour / insight chip ("▲ 72%+ Calificación del sueño").
struct InsightChip: View {
    let text: String
    let color: Color
    var up: Bool?

    var body: some View {
        HStack(spacing: 5) {
            if let up {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
            }
            Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Buttons

/// White capsule, black caps label.
struct PrimaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

/// Outlined capsule.
struct SecondaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Capsule().stroke(Color.white.opacity(configuration.isPressed ? 0.6 : 0.3), lineWidth: 1.5))
    }
}

// MARK: - Navigation chrome

/// Centered caps title with back and optional trailing control, like every detail screen.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var back: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            VStack(spacing: 3) {
                Caps(title, size: 14)
                if let subtitle {
                    Caps(subtitle, size: 10, color: Theme.secondary, weight: .semibold)
                }
            }
            HStack {
                if let back {
                    Button(action: back) {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                trailing
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 50)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, back: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.trailing = EmptyView()
    }
}

/// Detail screen scaffold: gradient, caps header with back, scrolling content.
struct DetailScreen<Content: View, Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: title, subtitle: subtitle, back: { dismiss() }) { trailing }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(PulsoBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension DetailScreen where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
        self.content = content()
    }
}

/// Section title in sentence case ("Tendencias semanales").
struct SectionHeading: View {
    let text: String
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            if let trailing, let action {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Caps(trailing, size: 11, color: Theme.secondary, weight: .semibold)
                        Image(systemName: "pencil").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }
}

/// "¿Qué es la recuperación?" explanation card.
struct ExplainerCard: View {
    let title: String
    let text: String

    var body: some View {
        PCard {
            Text(title).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            Text(text).font(.subheadline).foregroundStyle(Color(white: 0.82)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Dials

/// Score dial: track + arc + value, the hero of each pillar.
struct Dial: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 8)
                .animation(.easeOut(duration: 0.7), value: progress)
        }
    }
}

/// Small arc + caps label used as a pillar tab ("◔ RECUPERACIÓN").
struct PillarTab: View {
    let label: String
    let progress: Double
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Dial(progress: progress, color: color, lineWidth: 3).frame(width: 22, height: 22)
            Caps(label, size: 12)
        }
    }
}

// MARK: - Formatting

extension Fmt {
    /// Minutes as "6:23".
    static func hmm(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite else { return "–" }
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// Spanish decimal comma: "12,2".
    static func dec(_ v: Double?, _ digits: Int = 1) -> String {
        guard let v, v.isFinite else { return "–" }
        return String(format: "%.\(digits)f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// Thousands with a dot: "9.067".
    static func thousands(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "–" }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: v.rounded())) ?? String(Int(v))
    }

    /// "OCT. 26" / "OCT. 26 A HOY".
    static func shortDay(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "MMM d"
        return f.string(from: d).replacingOccurrences(of: " ", with: ". ").uppercased()
    }

    static func cycleTitle(_ key: String) -> String {
        key == DayKey.string(Date()) ? "\(shortDay(key)) A HOY" : shortDay(key)
    }

    /// ("mar", "20") for chart axes.
    static func weekdayAndDay(_ key: String) -> (String, String) {
        guard let d = DayKey.date(key) else { return ("", key) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE"
        let wd = f.string(from: d).replacingOccurrences(of: ".", with: "").lowercased()
        f.dateFormat = "d"
        return (wd, f.string(from: d))
    }
}
