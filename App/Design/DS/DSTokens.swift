import SwiftUI
import UIKit
import PulsoStore

/// Pulso design system (DS): the FINAL graphite palette, approved for the whole app (studio `FINAL/tokens.py`, dark
/// theme). `Hoy` and `HoyLevel` are the names Hoy was built with; they stay as aliases. Old screens still use `Theme`,
/// whose surfaces now point here too.
typealias Hoy = DS
typealias HoyLevel = DSLevel
typealias HoyFmt = DSFmt

enum DS {
    // Surfaces and text.
    static let bg = Color(hex: 0x111113)
    static let card = Color(hex: 0x1E1E21)
    static let sheet = Color(hex: 0x232326)
    static let fill = Color(hex: 0x2C2C30)
    static let fill2 = Color(hex: 0x3A3A40)
    static let segOn = Color(hex: 0x4A4A50)
    static let sep = Color.white.opacity(0.08)
    static let t1 = Color(hex: 0xF3F2EF)
    static let t2 = Color(hex: 0xA3A19C)
    static let t3 = Color(hex: 0x82807B)

    // Identity colours (in dark mode the ink equals the mark).
    static let recarga = Color(hex: 0x6E95F0)
    static let sueno = Color(hex: 0x9A8BF3)
    static let act = Color(hex: 0xF18D4D)
    static let cor = Color(hex: 0xF06A8F)
    static let cons = Color(hex: 0x5AB6E4)
    static let bien = Color(hex: 0x90A3B8)

    // Sleep stages: Profundo / REM / Ligero / Despierto.
    static let stDeep = Color(hex: 0x5A49D8)
    static let stREM = Color(hex: 0x8F82F0)
    static let stLight = Color(hex: 0xC3BBF7)
    static let stAwake = Color(hex: 0x55535A)

    static func stage(_ s: SleepStage) -> Color {
        switch s {
        case .deep: return stDeep
        case .rem: return stREM
        case .light: return stLight
        case .awake: return stAwake
        }
    }

    /// Band label / tint opacity of the "tu normal" motif.
    static let bandOpacity = 0.13
    static let edgeOpacity = 0.45
    /// Area under a chart line.
    static let areaOpacity = 0.14
    /// Identity-tinted capsule buttons and chips (`color-mix(... 22%)`).
    static let tintOpacity = 0.22

    // Chrome.
    static let hair = Color.white.opacity(0.055)
    static let glass = Color(hex: 0x242428, opacity: 0.72)
    static let glassLine = Color.white.opacity(0.08)
    static let tabSelected = Color.white.opacity(0.10)

    // Heart-rate zones Z1…Z5 (light to dark orange).
    static let zones = [Color(hex: 0xF6CFB2), Color(hex: 0xF3AE7E), Color(hex: 0xF18D4D), Color(hex: 0xE06A2A), Color(hex: 0xC24E17)]
    static func zone(_ z: Int) -> Color { zones[min(max(z, 1), 5) - 1] }

    // Geometry.
    static let radius: CGFloat = 18
    static let sheetRadius: CGFloat = 34
    /// Side margin of cards / of section titles.
    static let gutter: CGFloat = 16
    static let titleInset: CGFloat = 20
    /// Space between cards in a column.
    static let stack: CGFloat = 10
}

/// The four-step status scale (Baja < 40 · Justa 40–59 · Buena 60–79 · Excelente ≥ 80): a dot/mark colour and a
/// lighter word colour for text, so the word passes contrast on the card.
enum DSLevel: Int, Comparable, CaseIterable {
    case baja = 1, justa, buena, excelente

    static func < (a: DSLevel, b: DSLevel) -> Bool { a.rawValue < b.rawValue }

    init(score: Double) {
        switch score {
        case ..<40: self = .baja
        case ..<60: self = .justa
        case ..<80: self = .buena
        default: self = .excelente
        }
    }

    var word: String {
        switch self {
        case .baja: return "Baja"
        case .justa: return "Justa"
        case .buena: return "Buena"
        case .excelente: return "Excelente"
        }
    }

    var mark: Color {
        switch self {
        case .baja: return Color(hex: 0xC9583F)
        case .justa: return Color(hex: 0xF4D47E)
        case .buena: return Color(hex: 0x5DA055)
        case .excelente: return Color(hex: 0x256773)
        }
    }

    var ink: Color {
        switch self {
        case .baja: return Color(hex: 0xE07A62)
        case .justa: return Color(hex: 0xF0CA6A)
        case .buena: return Color(hex: 0x8ECB82)
        case .excelente: return Color(hex: 0x74BFC6)
        }
    }

    /// A vital against its range: in range = buena, a bit out = justa, well out = baja.
    init?(_ l: VitalReading.Level) {
        switch l {
        case .green: self = .buena
        case .orange: self = .justa
        case .red: self = .baja
        case .none: return nil
        }
    }

    /// Stress: low reads as good.
    init(stress v: Double) {
        self = v < 1 ? .buena : (v < 2 ? .justa : .baja)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: - Type

extension View {
    /// SF Pro at a design size with tabular digits (Dynamic Type capped like the rest of the app).
    func dsFont(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo: UIFont.TextStyle = .body,
                maxScale: CGFloat = 1.35) -> some View {
        scaledFont(size, weight: weight, relativeTo: relativeTo, maxScale: maxScale).monospacedDigit()
    }

    /// Same as `dsFont` (the name Hoy was written with).
    func hoyFont(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo: UIFont.TextStyle = .body,
                 maxScale: CGFloat = 1.35) -> some View {
        dsFont(size, weight, relativeTo: relativeTo, maxScale: maxScale)
    }

    /// DS card: graphite surface, radius 18, a 0.5 pt hairline, no shadow.
    func dsCard(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(DS.hair, lineWidth: 0.5))
    }

    /// Same as `dsCard` (the name Hoy was written with).
    func hoyCard(padding: CGFloat = 14) -> some View { dsCard(padding: padding) }

    /// Screen background of every DS screen.
    func dsBackground() -> some View { background(DS.bg.ignoresSafeArea()) }
}

/// Section title: 20 pt semibold, with a chevron when it opens a detail, and an optional trailing note.
struct HoySectionTitle<Trailing: View>: View {
    let title: String
    var chevron = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title).hoyFont(20, .semibold, relativeTo: .title3).foregroundStyle(Hoy.t1)
                .accessibilityAddTraits(.isHeader)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Hoy.t3)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 2)
        .padding(.top, 10)
    }
}

extension HoySectionTitle where Trailing == EmptyView {
    init(_ title: String, chevron: Bool = false) {
        self.title = title
        self.chevron = chevron
        self.trailing = EmptyView()
    }
}

typealias DSValue = HoyValue
typealias DSDot = HoyDot

/// Value with its unit on the same baseline: "1 h 31", "27,5 años".
struct HoyValue: View {
    let value: String
    var unit: String = ""
    var size: CGFloat = 17
    var color: Color = Hoy.t1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).hoyFont(size, .semibold).foregroundStyle(color)
            if !unit.isEmpty {
                Text(unit).hoyFont(max(11, size * 0.58), .medium).foregroundStyle(Hoy.t2)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Coloured dot of a legend or status (7 pt).
struct HoyDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

// MARK: - Formatting

enum DSFmt {
    /// "8 900": thousands with a narrow no-break space, also for four digits (as in the design).
    static func thousands(_ v: Double?) -> String {
        guard let v, v.isFinite else { return "–" }
        let n = Int(v.rounded())
        let s = String(abs(n))
        var out = ""
        for (i, c) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 { out.append("\u{202F}") }
            out.append(c)
        }
        return (n < 0 ? "−" : "") + out
    }

    /// "1 h 31", "24 min", "11 h 20".
    static func duration(_ minutes: Double?) -> String {
        guard let minutes, minutes.isFinite else { return "–" }
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : String(format: "%d h %02d", m / 60, m % 60)
    }

    /// Value and unit of a duration apart, for `HoyValue`: ("1 h 31", "") or ("24", "min").
    static func durationParts(_ minutes: Double?) -> (String, String) {
        guard let minutes, minutes.isFinite else { return ("–", "") }
        let m = Int(minutes.rounded())
        return m < 60 ? ("\(m)", "min") : (duration(minutes), "")
    }

    /// "Lun 16 nov".
    static func shortDate(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "EEE d MMM"
        let s = f.string(from: d).replacingOccurrences(of: ".", with: "")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// "8 nov".
    static func dayMonth(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    /// "jun".
    static func month(_ key: String) -> String {
        guard let d = DayKey.date(key) else { return key }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    /// "00", "06": hour of a timestamp.
    static func hour(_ ts: Int) -> String {
        String(format: "%02d", Calendar.current.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(ts))))
    }
}
