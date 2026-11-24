import SwiftUI

/// Tab «Actividad» (studio C-actividad 01). For now the existing Live screen and the day's strain behind a segmented
/// control; the Actividad area replaces this body with the redesigned tab root (routes in `Routes+Actividad.swift`).
struct ActivityTab: View {
    @State private var part = 0

    var body: some View {
        Group {
            if part == 0 { LiveView() } else { StrainDetailView() }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DSSegmented(options: [(0, "En vivo"), (1, "Esfuerzo")], selection: $part, height: 32)
                .padding(.horizontal, DS.gutter)
                .padding(.vertical, 8)
                .background(DS.bg)
        }
    }
}
