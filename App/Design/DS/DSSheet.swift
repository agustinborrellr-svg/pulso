import SwiftUI

// Sheet chrome and empty state of the design system.

/// Sheet header: optional left button, centred title, round close button on the right (studio `.shd`).
struct DSSheetHeader<Leading: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var subtitle: String?
    var close = true
    @ViewBuilder var leading: Leading

    init(_ title: String, subtitle: String? = nil, close: Bool = true, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.subtitle = subtitle
        self.close = close
        self.leading = leading()
    }

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(title).dsFont(17, .semibold, relativeTo: .headline).foregroundStyle(DS.t1).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).dsFont(12, relativeTo: .caption1).foregroundStyle(DS.t2).lineLimit(1)
                }
            }
            .padding(.horizontal, 60)
            HStack {
                leading
                Spacer()
                if close {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DS.t2)
                            .frame(width: 32, height: 32)
                            .background(DS.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cerrar")
                }
            }
        }
        .frame(height: 50)
        .padding(.top, 10)
        .padding(.horizontal, DS.gutter)
    }
}

extension DSSheetHeader where Leading == EmptyView {
    init(_ title: String, subtitle: String? = nil, close: Bool = true) {
        self.init(title, subtitle: subtitle, close: close) { EmptyView() }
    }
}

/// A sheet of the redesign: header, scrolling content on the sheet surface. Present it with `.dsSheet()` applied.
struct DSSheet<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            DSSheetHeader(title, subtitle: subtitle)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.stack) { content }
                    .padding(.horizontal, DS.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.card.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    /// Sheet presentation of the redesign: card surface, 34 pt corners, grabber, dark.
    func dsSheet(detents: Set<PresentationDetent> = [.large]) -> some View {
        self.presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(DS.sheetRadius)
            .presentationBackground(DS.card)
            .preferredColorScheme(.dark)
    }
}

/// Empty state of the redesign: a quiet icon, a title, one or two lines and an optional capsule action. Shown in a
/// card unless `bare`.
struct DSEmptyState: View {
    let icon: String
    let title: String
    var message: String?
    var tint: Color = DS.t3
    var actionTitle: String?
    var action: (() -> Void)?
    var bare = false

    var body: some View {
        let content = VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(DS.fill, in: Circle())
                .accessibilityHidden(true)
            Text(title).dsFont(17, .semibold, relativeTo: .headline).foregroundStyle(DS.t1).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message).dsFont(15).foregroundStyle(DS.t2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DSButtonStyle(tint: DS.recarga, size: .small))
                    .padding(.top, 6)
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity)

        if bare {
            content
        } else {
            content.background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        }
    }
}
