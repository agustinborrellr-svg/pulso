import SwiftUI

/// Tab «Salud» (studio D-salud 01). For now the existing Salud screen and Análisis (Inteligencia · Tendencias) behind
/// a segmented control; the Salud area replaces this body with the redesigned tab root (routes in `Routes+Salud.swift`).
struct HealthTab: View {
    @State private var part: Int

    init(part: Int = 0) {
        _part = State(initialValue: part)
    }

    var body: some View {
        Group {
            if part == 0 { HealthView() } else { TrendsView() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DSSegmented(options: [(0, "Salud"), (1, "Análisis")], selection: $part, height: 32)
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, 8)
                .background(DS.bg)
        }
    }
}
