import SwiftUI

/// The five tabs of the redesign.
enum AppTab: String, CaseIterable, Identifiable {
    case hoy, sueno, actividad, salud, tu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hoy: return "Hoy"
        case .sueno: return "Sueño"
        case .actividad: return "Actividad"
        case .salud: return "Salud"
        case .tu: return "Tú"
        }
    }

    var icon: String {
        switch self {
        case .hoy: return "square.grid.2x2.fill"
        case .sueno: return "moon.fill"
        case .actividad: return "flame.fill"
        case .salud: return "heart.fill"
        case .tu: return "person.fill"
        }
    }
}

/// Floating tab bar (studio `.tabbar`): a 62 pt glass capsule 16 pt from the sides, the selected tab on a lighter
/// pill, with a fade of the background behind it so content scrolls away under it.
struct DSTabBar: View {
    @Binding var selection: AppTab
    var onSelect: (AppTab) -> Void = { _ in }

    static let height: CGFloat = 62
    /// Space the content leaves at the bottom of the screen so its last card clears the bar (studio `.screen` 118 px).
    static let contentInset: CGFloat = 118

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { t in
                let on = t == selection
                Button {
                    onSelect(t)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.icon).font(.system(size: 19, weight: .semibold)).frame(height: 24)
                        Text(t.title).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(on ? DS.t1 : DS.t2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background { if on { Capsule().fill(DS.tabSelected) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: Self.height)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(DS.glass)
            }
            .environment(\.colorScheme, .dark)
        }
        .overlay(Capsule().strokeBorder(DS.glassLine, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 8)
        .padding(.horizontal, 16)
    }
}
