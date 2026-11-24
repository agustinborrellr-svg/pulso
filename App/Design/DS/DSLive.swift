import SwiftUI

// Live pieces of the design system: the «Ahora» card, the small pulse curve and the breathing dot.

/// «Ahora» card: pulsing dot, the pulse now (live or the last downloaded minutes), a small curve and what you are
/// doing ("Reposo desde 16:27"), when known. Wrap it with a `DSSectionHeader("Ahora", note: "sync 17:04")`.
struct DSNowCard: View {
    let hr: Int
    var live = false
    var points: [Double] = []
    var state: String?
    var since: String?
    var color: Color = DS.cor

    var body: some View {
        HStack(spacing: 12) {
            PulsingDot(active: live)
            HoyValue(value: "\(hr)", unit: "lpm", size: 26)
            if points.count >= 3 {
                Sparkline(points: points, color: color)
                    .frame(width: state == nil ? nil : 84, height: 24)
                    .frame(maxWidth: state == nil ? .infinity : nil)
            }
            if let state {
                Rectangle().fill(DS.sep).frame(width: 1, height: 26)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(state).dsFont(17, .semibold).foregroundStyle(DS.t1)
                    if let since { Text("desde \(since)").dsFont(15).foregroundStyle(DS.t2) }
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(DS.card, in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(live ? "Pulso en directo \(hr) latidos por minuto" : "Pulso \(hr) latidos por minuto")
    }
}

/// Small pink line of the last minutes, ending in a dot.
struct Sparkline: View {
    let points: [Double]
    var color: Color = Hoy.cor

    var body: some View {
        GeometryReader { g in
            let lo = (points.min() ?? 0) - 1, hi = (points.max() ?? 1) + 1
            let pts = points.enumerated().map { i, v in
                CGPoint(x: 3 + (g.size.width - 8) * CGFloat(i) / CGFloat(max(points.count - 1, 1)),
                        y: g.size.height - 2 - (g.size.height - 4) * CGFloat((v - lo) / max(hi - lo, 0.001)))
            }
            ZStack {
                SmoothPath(points: pts)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(color.opacity(0.22)).frame(width: 10, height: 10).position(last)
                    Circle().fill(color).frame(width: 5, height: 5).position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Catmull-Rom curve through points (smooth, passes through every point).
struct SmoothPath: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        guard points.count > 1 else { return p }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }
}

/// Pink dot that breathes while the pulse is live.
struct PulsingDot: View {
    let active: Bool
    @State private var on = false

    var body: some View {
        ZStack {
            if active {
                Circle().fill(Hoy.cor.opacity(0.28)).frame(width: 16, height: 16)
                    .scaleEffect(on ? 1.15 : 0.6).opacity(on ? 0 : 1)
            }
            Circle().fill(active ? Hoy.cor : Hoy.cor.opacity(0.55)).frame(width: 8, height: 8)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            guard active else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true }
        }
        .accessibilityHidden(true)
    }
}

