import SwiftUI
import Charts

/// Drag a finger over a chart: the x under it is published while touching and cleared on release, with a light tick
/// each time it moves to a new value.
struct ChartScrub<X: Plottable & Equatable>: ViewModifier {
    @Binding var selection: X?

    func body(content: Content) -> some View {
        content
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { g in
                                    guard let frame = proxy.plotFrame else { return }
                                    let x = g.location.x - geo[frame].origin.x
                                    if let v: X = proxy.value(atX: x), v != selection { selection = v }
                                }
                                .onEnded { _ in withAnimation(.easeOut(duration: 0.25)) { selection = nil } }
                        )
                }
            }
            .sensoryFeedback(.selection, trigger: selection)
    }
}

extension View {
    func chartScrub<X: Plottable & Equatable>(_ selection: Binding<X?>) -> some View {
        modifier(ChartScrub(selection: selection))
    }
}
