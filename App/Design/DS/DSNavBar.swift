import SwiftUI

/// Detail navigation bar: a back pill with the parent's name on the left ("‹ Monitor"), the title and a small subtitle
/// centred ("VFC" / "Anoche · 16 nov") and an optional control on the right. Without `back` the pill shows only the
/// chevron; on a tab root (nothing to go back to) it hides itself.
struct DSNavBar<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    let title: String
    var subtitle: String?
    var back: String?
    /// Custom back action (default: dismiss / pop).
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, back: String? = nil, onBack: (() -> Void)? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(title).dsFont(17, .semibold, relativeTo: .headline).foregroundStyle(DS.t1)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).dsFont(12, relativeTo: .caption1).foregroundStyle(DS.t2)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: 210)
            HStack {
                if onBack != nil || isPresented {
                    Button { if let onBack { onBack() } else { dismiss() } } label: { backLabel }
                        .buttonStyle(.plain)
                        .accessibilityLabel(back.map { "Volver a \($0)" } ?? "Atrás")
                }
                Spacer(minLength: 0)
                trailing
            }
        }
        .frame(height: 52)
        .padding(.top, 4)
        .padding(.horizontal, DS.gutter)
    }

    @ViewBuilder
    private var backLabel: some View {
        if let back {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                Text(back).dsFont(16, .semibold, relativeTo: .callout).lineLimit(1)
            }
            .foregroundStyle(DS.t1)
            .padding(.leading, 11)
            .padding(.trailing, 14)
            .frame(height: 36)
            .frame(maxWidth: 120)
            .background(DS.card, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.hair, lineWidth: 0.5))
            .contentShape(Capsule())
        } else {
            DSCircleButton(icon: "chevron.left")
        }
    }
}

extension DSNavBar where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, back: String? = nil, onBack: (() -> Void)? = nil) {
        self.init(title, subtitle: subtitle, back: back, onBack: onBack) { EmptyView() }
    }
}

/// Round 36 pt button on the card surface (nav bar controls: back without a name, "…", "+").
struct DSCircleButton: View {
    let icon: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DS.t1)
            .frame(width: size, height: size)
            .background(DS.card, in: Circle())
            .overlay(Circle().strokeBorder(DS.hair, lineWidth: 0.5))
            .contentShape(Circle())
    }
}

/// A detail screen of the redesign: DS nav bar, then a scrolling column of cards with the DS gutters, on graphite.
/// The system navigation bar is hidden (the DS bar replaces it; the edge swipe still goes back).
struct DSScreen<Content: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var back: String?
    var spacing: CGFloat = DS.stack
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, back: String? = nil, spacing: CGFloat = DS.stack,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.back = back
        self.spacing = spacing
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DSNavBar(title, subtitle: subtitle, back: back) { trailing }
                    .padding(.horizontal, -DS.gutter)
                VStack(alignment: .leading, spacing: spacing) { content }
                    .padding(.top, 6)
            }
            .padding(.horizontal, DS.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .dsBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension DSScreen where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, back: String? = nil, spacing: CGFloat = DS.stack,
         @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, back: back, spacing: spacing, trailing: { EmptyView() }, content: content)
    }
}

/// A tab root of the redesign: large title (or a custom header), scrolling column, graphite, no system bar.
struct DSTabScreen<Header: View, Content: View>: View {
    var spacing: CGFloat = DS.stack
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                header
                content
            }
            .padding(.horizontal, DS.gutter)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .dsBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension DSTabScreen where Header == DSLargeTitle {
    init(_ title: String, spacing: CGFloat = DS.stack, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.header = DSLargeTitle(title)
        self.content = content()
    }
}
