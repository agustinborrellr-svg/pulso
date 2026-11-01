import SwiftUI
import Charts

/// Drag a finger sideways over a chart: the x under it is published while touching and cleared on release, with a
/// light tick each time it moves to a new value. Vertical drags are left to the scroll view, so a chart never stops
/// the page from scrolling.
struct ChartScrub<X: Plottable & Equatable>: ViewModifier {
    @Binding var selection: X?
    @State private var horizontal: Bool?

    func body(content: Content) -> some View {
        content
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { g in
                                    // Decide once per touch whether this is a scrub (sideways) or a scroll (up/down).
                                    if horizontal == nil {
                                        horizontal = abs(g.translation.width) > abs(g.translation.height)
                                    }
                                    guard horizontal == true, let frame = proxy.plotFrame else { return }
                                    let x = g.location.x - geo[frame].origin.x
                                    if let v: X = proxy.value(atX: x), v != selection { selection = v }
                                }
                                .onEnded { _ in
                                    horizontal = nil
                                    withAnimation(.easeOut(duration: 0.25)) { selection = nil }
                                }
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
