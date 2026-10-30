import SwiftUI
import UIKit

/// Shared metrics so every surface agrees on shape.
enum Metrics {
    static let cardRadius: CGFloat = 14
    static let rowRadius: CGFloat = 10
    static let cardPadding: CGFloat = 16
    /// Smallest text size allowed at the default Dynamic Type setting.
    static let minLabel: CGFloat = 11
}

/// System font at a design size that follows Dynamic Type (scaled like `style`), capped at `maxScale`
/// so big numbers and caps labels don't break their layouts at accessibility sizes.
struct ScaledFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicType
    let size: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .default
    var relativeTo: UIFont.TextStyle = .body
    var maxScale: CGFloat = 1.6
    var tracking: CGFloat = 0

    func body(content: Content) -> some View {
        let s = ScaledFont.scaled(size, relativeTo: relativeTo, dynamicType: dynamicType, maxScale: maxScale)
        content
            .font(.system(size: s, weight: weight, design: design))
            .tracking(tracking * s / max(size, 1))
    }

    static func scaled(_ size: CGFloat, relativeTo style: UIFont.TextStyle, dynamicType: DynamicTypeSize, maxScale: CGFloat) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicType))
        let s = UIFontMetrics(forTextStyle: style).scaledValue(for: size, compatibleWith: traits)
        return min(s, size * maxScale)
    }
}

extension View {
    /// `.font(.system(size:))` that scales with Dynamic Type. Use for every fixed-size design font.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                    relativeTo: UIFont.TextStyle = .body, maxScale: CGFloat = 1.6, tracking: CGFloat = 0) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, relativeTo: relativeTo, maxScale: maxScale, tracking: tracking))
    }

    /// Card surface: slate fill, hairline border, continuous corners.
    func cardSurface(radius: CGFloat = Metrics.cardRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
        )
    }
}
