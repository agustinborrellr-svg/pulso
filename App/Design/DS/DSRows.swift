import SwiftUI

// Grouped settings-style lists of the design system (Tú, ajustes, alarmas…): a card holding rows separated by
// hairlines that start after the icon. Rows: icon, label (+ subtitle), value, chevron or toggle.
//
//   DSGroupLabel("Funciones")
//   DSGroup {
//       RouteLink(.sueno(.alarmas)) { DSRow(icon: "alarm", label: "Despertador", value: "06:45", chevron: true) }
//       DSToggleRow(icon: "bell", label: "Avisos", isOn: $on)
//   }

/// Card that stacks rows with hairlines between them (inset after the icon column).
struct DSGroup<Content: View>: View {
    var footer: String?
    @ViewBuilder var content: Content

    init(footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            _VariadicView.Tree(DSGroupLayout()) { content }
                .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DS.radius, style: .continuous).strokeBorder(DS.hair, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
            if let footer {
                Text(footer).dsFont(12.5, relativeTo: .caption1).foregroundStyle(DS.t3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.titleInset - DS.gutter)
            }
        }
    }
}

/// Puts a hairline between the group's children.
private struct DSGroupLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last {
                    DSDivider(inset: child[DSRowInsetKey.self])
                }
            }
        }
    }
}

/// Where the hairline under a row starts (48 after an icon, 14 without; 48 when a wrapper hides the row's own value).
struct DSRowInsetKey: _ViewTraitKey {
    static var defaultValue: CGFloat = 48
}

extension View {
    /// Inset of the hairline drawn under this row inside a `DSGroup`.
    func dsRowInset(_ inset: CGFloat) -> some View { _trait(DSRowInsetKey.self, inset) }
}

/// A settings-style row: optional icon, label with optional subtitle, optional value and chevron.
struct DSRow<Accessory: View>: View {
    var icon: String?
    var iconColor: Color = DS.t2
    let label: String
    var subtitle: String?
    var value: String?
    var chevron = false
    /// Label in the secondary colour (key/value rows: «Firmware   41.17.1.0»).
    var keyValue = false
    var destructive = false
    @ViewBuilder var accessory: Accessory

    init(icon: String? = nil, iconColor: Color = DS.t2, label: String, subtitle: String? = nil, value: String? = nil,
         chevron: Bool = false, keyValue: Bool = false, destructive: Bool = false, @ViewBuilder accessory: () -> Accessory) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.subtitle = subtitle
        self.value = value
        self.chevron = chevron
        self.keyValue = keyValue
        self.destructive = destructive
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(iconColor).frame(width: 22)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).dsFont(keyValue ? 15 : 16, relativeTo: .body)
                    .foregroundStyle(destructive ? DSLevel.baja.ink : (keyValue ? DS.t2 : DS.t1))
                    .lineLimit(1).minimumScaleFactor(0.85)
                if let subtitle {
                    Text(subtitle).dsFont(13, relativeTo: .footnote).foregroundStyle(DS.t2).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value).dsFont(15, keyValue ? .medium : .regular).foregroundStyle(keyValue ? DS.t1 : DS.t2)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            accessory
            if chevron { DSChevron() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: subtitle == nil ? 50 : 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .dsRowInset(icon == nil ? 14 : 48)
    }
}

extension DSRow where Accessory == EmptyView {
    init(icon: String? = nil, iconColor: Color = DS.t2, label: String, subtitle: String? = nil, value: String? = nil,
         chevron: Bool = false, keyValue: Bool = false, destructive: Bool = false) {
        self.init(icon: icon, iconColor: iconColor, label: label, subtitle: subtitle, value: value, chevron: chevron,
                  keyValue: keyValue, destructive: destructive) { EmptyView() }
    }
}

/// Row with a switch (green when on, as in the mocks).
struct DSToggleRow: View {
    var icon: String?
    var iconColor: Color = DS.t2
    let label: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        DSRow(icon: icon, iconColor: iconColor, label: label, subtitle: subtitle) {
            Toggle(label, isOn: $isOn).labelsHidden().tint(DSLevel.buena.mark)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A row that runs an action (export, recalculate…): a `DSRow` inside a plain button.
struct DSButtonRow: View {
    var icon: String?
    let label: String
    var value: String?
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DSRow(icon: icon, label: label, value: value, destructive: destructive)
        }
        .buttonStyle(.plain)
        .dsRowInset(icon == nil ? 14 : 48)
    }
}
