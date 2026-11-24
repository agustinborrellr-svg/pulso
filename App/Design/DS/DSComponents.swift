import SwiftUI

// Shared building blocks of the design system. Every screen of the redesign is made of these; keep them generic
// (no AppModel inside) so any area can use them with its own data.

// MARK: - Section header

/// Section title above a card: 20 pt semibold, a chevron when the title opens a detail and an optional note on the
/// right ("tus 90 noches", "sync 17:04"). Use `DSSectionHeader(...) { trailing }` for a custom right side.
struct DSSectionHeader<Trailing: View>: View {
    let title: String
    var chevron = false
    var note: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, chevron: Bool = false, note: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.chevron = chevron
        self.note = note
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).dsFont(20, .semibold, relativeTo: .title3).foregroundStyle(DS.t1)
                .accessibilityAddTraits(.isHeader)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DS.t3)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            if let note {
                Text(note).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t3).lineLimit(1)
            }
            trailing
        }
        .padding(.horizontal, DS.titleInset - DS.gutter)
        .padding(.top, 16)
        .padding(.bottom, -1)
    }
}

extension DSSectionHeader where Trailing == EmptyView {
    init(_ title: String, chevron: Bool = false, note: String? = nil) {
        self.init(title, chevron: chevron, note: note) { EmptyView() }
    }
}

/// Small grey label above a grouped list ("Funciones", "Tus datos"), 13 pt semibold.
struct DSGroupLabel: View {
    let text: String
    var note: String?

    init(_ text: String, note: String? = nil) {
        self.text = text
        self.note = note
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).dsFont(13, .semibold, relativeTo: .footnote).foregroundStyle(DS.t2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let note { Text(note).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t3) }
        }
        .padding(.horizontal, DS.titleInset - DS.gutter)
        .padding(.top, 22)
        .padding(.bottom, -3)
    }
}

/// Large screen title of a tab root ("Tú", "Salud"): 34 pt bold.
struct DSLargeTitle: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).dsFont(34, .bold, relativeTo: .largeTitle, maxScale: 1.2).foregroundStyle(DS.t1)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, DS.titleInset - DS.gutter)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Level: word + dot + 4-step meter

/// Four short dashes, the first `filled` in the level colour: how far up the Baja…Excelente scale a score is.
struct DSMeter: View {
    var filled: Int
    var color: Color
    var width: CGFloat = 13
    var height: CGFloat = 4

    init(_ level: DSLevel, width: CGFloat = 13) {
        self.filled = level.rawValue
        self.color = level.mark
        self.width = width
    }

    init(filled: Int, color: Color, width: CGFloat = 13) {
        self.filled = filled
        self.color = color
        self.width = width
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Capsule().fill(i < filled ? color : DS.fill2).frame(width: width, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Status word with its dot and, for scores, the 4-step meter: "● Buena ▬▬▬▭". `text` overrides the word
/// ("En tu rango") while keeping the level's colours.
struct DSLevelWord: View {
    let level: DSLevel
    var text: String?
    var meter = false
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 6) {
            HoyDot(color: level.mark, size: size >= 15 ? 8 : 7)
            Text(text ?? level.word).dsFont(size, .semibold, relativeTo: .subheadline).foregroundStyle(level.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            if meter { DSMeter(level).padding(.leading, 4) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text ?? level.word)
    }
}

/// "▲ 4 ms sobre tu media": a small delta line under a hero value.
struct DSDelta: View {
    let text: String
    var up: Bool?
    var color: Color = DS.t2

    var body: some View {
        HStack(spacing: 5) {
            if let up {
                Image(systemName: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size: 8))
            }
            Text(text).dsFont(13, .semibold, relativeTo: .footnote)
        }
        .foregroundStyle(color)
        .lineLimit(1)
    }
}

// MARK: - Segmented control

/// The DS segmented control (`7 d · 30 d · 6 m`): grey track, lighter selected segment.
struct DSSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var height: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let on = value == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = value }
                } label: {
                    Text(label).dsFont(13, on ? .semibold : .medium, relativeTo: .footnote)
                        .foregroundStyle(on ? DS.t1 : DS.t2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(DS.segOn)
                                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: height)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Side table, stat strip, range bar

/// Short label/value table with hairlines between rows ("Tu normal 49–72 · Ayer 65"), used beside a hero value.
struct DSSideTable: View {
    let rows: [(String, String)]
    var width: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                if i > 0 { Rectangle().fill(DS.sep).frame(height: 0.5) }
                HStack(alignment: .firstTextBaseline) {
                    Text(rows[i].0).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(rows[i].1).dsFont(15, .semibold, relativeTo: .subheadline).foregroundStyle(DS.t1).lineLimit(1)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.leading, 14)
        .frame(width: width)
        .overlay(alignment: .leading) { Rectangle().fill(DS.sep).frame(width: 0.5) }
    }
}

/// One cell of a stat strip.
struct DSStat: Identifiable {
    let label: String
    let value: String
    var unit: String = ""
    var id: String { label }
}

/// Two to four figures side by side with hairlines between them ("Más alta 64 ms | Más baja 44 ms | En tu normal 25
/// de 30 noches"; "Te dura · Sincronizada · Datos guardados").
struct DSStatStrip: View {
    let stats: [DSStat]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(stats.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 3) {
                    Text(stats[i].label).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2).lineLimit(1)
                    HoyValue(value: stats[i].value, unit: stats[i].unit, size: 20)
                        .minimumScaleFactor(0.7)
                }
                .padding(.leading, i == 0 ? 0 : 12)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    if i > 0 { Rectangle().fill(DS.sep).frame(width: 0.5) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A horizontal scale made of coloured stretches with a dot where the value sits, and labels under the joins
/// ("Tus límites, con tus 30 noches anteriores"). Fractions are positions on 0…1.
struct DSRangeBar: View {
    struct Stretch {
        let to: Double
        let color: Color
    }

    let stretches: [Stretch]
    var marker: Double?
    var markerColor: Color = DS.t1
    var labels: [(Double, String)] = []

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    ForEach(stretches.indices, id: \.self) { i in
                        let from = i == 0 ? 0 : stretches[i - 1].to
                        let to = stretches[i].to
                        Capsule().fill(stretches[i].color)
                            .frame(width: max(2, w * CGFloat(to - from) - 4), height: 6)
                            .offset(x: w * CGFloat(from) + 2)
                    }
                    if let marker {
                        Circle().fill(markerColor)
                            .overlay(Circle().stroke(DS.card, lineWidth: 2.5))
                            .frame(width: 15, height: 15)
                            .offset(x: w * CGFloat(min(max(marker, 0), 1)) - 7.5)
                    }
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            if !labels.isEmpty {
                GeometryReader { g in
                    ForEach(labels.indices, id: \.self) { i in
                        Text(labels[i].1).dsFont(11, .medium, relativeTo: .caption2).foregroundStyle(DS.t3)
                            .fixedSize()
                            .position(x: g.size.width * CGFloat(labels[i].0), y: 7)
                    }
                }
                .frame(height: 14)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Identity-tinted capsule button (the only button family of the redesign): tint at 22 % with the ink as text.
/// `gray` uses the neutral fill (secondary or destructive actions; the word carries the colour).
struct DSButtonStyle: ButtonStyle {
    var tint: Color = DS.recarga
    var size: Size = .large
    var gray = false
    var fullWidth = false

    enum Size { case small, large, xl }

    func makeBody(configuration: Configuration) -> some View {
        let h: CGFloat = size == .small ? 34 : (size == .large ? 50 : 56)
        configuration.label
            .dsFont(size == .small ? 15 : 17, .semibold)
            .foregroundStyle(gray ? DS.t1 : tint)
            .lineLimit(1)
            .padding(.horizontal, size == .small ? 16 : 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: h)
            .background(gray ? DS.fill : tint.opacity(DS.tintOpacity), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Card wrapper: `DSCard { ... }` = a VStack on the DS surface.
struct DSCard<Content: View>: View {
    var padding: CGFloat = 14
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .dsCard(padding: padding)
    }
}

/// Hairline divider inside cards.
struct DSDivider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle().fill(DS.sep).frame(height: 0.5).padding(.leading, inset)
    }
}

/// The app's switches: green when on, as in the mocks (the app tint is white, which hid the knob). Set app-wide on
/// the tabs and on presented screens.
struct DSSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(DSLevel.buena.mark)
    }
}

/// Chevron used at the end of tappable rows.
struct DSChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(DS.t3.opacity(0.9))
            .accessibilityHidden(true)
    }
}
