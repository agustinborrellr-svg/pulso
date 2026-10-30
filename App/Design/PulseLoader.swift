import SwiftUI

/// Pulso's loader: a white line travelling along the pulse trace of the logo.
/// Indeterminate (comet loops), determinate (trace fills up to `progress`), done (full trace + check) or failed.
struct PulseLoader: View {
    enum Phase: Equatable {
        case running(progress: Double?)
        case done
        case failed
    }

    enum Style { case regular, compact }

    var phase: Phase
    var style: Style = .regular
    var tint: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineWidth: CGFloat { style == .compact ? 1.6 : 3 }

    var body: some View {
        ZStack {
            switch phase {
            case .running(nil):
                if reduceMotion {
                    WaveTrace(head: 1, tail: 0, color: tint.opacity(0.7), lineWidth: lineWidth, fade: false)
                } else {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        let head = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6 * 1.3
                        WaveTrace(head: min(1, head), tail: max(0, head - 0.32), color: tint, lineWidth: lineWidth, fade: true)
                    }
                }
            case .running(let p?):
                WaveTrace(head: max(0.02, min(1, p)), tail: 0, color: tint, lineWidth: lineWidth, fade: false)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: p)
            case .done:
                WaveTrace(head: 1, tail: 0, color: tint, lineWidth: lineWidth, fade: false)
                    .overlay(alignment: .trailing) { if style == .regular { badge("checkmark", Theme.green) } }
            case .failed:
                WaveTrace(head: 1, tail: 0, color: Theme.red.opacity(0.75), lineWidth: lineWidth, fade: false)
                    .overlay(alignment: .trailing) { if style == .regular { badge("exclamationmark", Theme.red) } }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: phase)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(.black)
            .frame(width: 26, height: 26)
            .background(color, in: Circle())
            .shadow(color: color.opacity(0.6), radius: 8)
            .offset(x: 13)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
    }

    private var accessibilityText: String {
        switch phase {
        case .running(nil): return "En curso"
        case .running(let p?): return "En curso, \(Int((p * 100).rounded())) %"
        case .done: return "Completado"
        case .failed: return "Error"
        }
    }
}

/// Inline "〰 Sincronizando…" for rows and headers.
struct PulseLoaderLabel: View {
    let text: String
    var tint: Color = Theme.secondary

    var body: some View {
        HStack(spacing: 8) {
            PulseLoader(phase: .running(progress: nil), style: .compact, tint: tint)
                .frame(width: 28, height: 14)
                .accessibilityHidden(true)
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The trace from `tail` to `head` (fractions of its length) over a faint full track, with a glowing head.
private struct WaveTrace: View, Animatable {
    var head: Double
    var tail: Double
    let color: Color
    let lineWidth: CGFloat
    let fade: Bool

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(head, tail) }
        set { head = newValue.first; tail = newValue.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let wave = PulseWave.path(in: CGRect(origin: .zero, size: size).insetBy(dx: lineWidth, dy: lineWidth))
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            ctx.stroke(wave, with: .color(Color.white.opacity(0.12)), style: stroke)
            guard head > tail else { return }
            if fade {
                // Comet tail: segments fading towards the back.
                let n = 8
                for i in 0..<n {
                    let a = tail + (head - tail) * Double(i) / Double(n)
                    let b = tail + (head - tail) * Double(i + 1) / Double(n)
                    ctx.stroke(wave.trimmedPath(from: a, to: b), with: .color(color.opacity(Double(i + 1) / Double(n))), style: stroke)
                }
            } else {
                ctx.stroke(wave.trimmedPath(from: tail, to: head), with: .color(color), style: stroke)
            }
            if head < 1, let p = wave.trimmedPath(from: max(0, head - 0.001), to: head).currentPoint {
                let r = lineWidth * 1.4
                var glow = ctx
                glow.addFilter(.blur(radius: lineWidth * 2))
                glow.fill(Path(ellipseIn: CGRect(x: p.x - r * 2, y: p.y - r * 2, width: r * 4, height: r * 4)), with: .color(color.opacity(0.6)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
            }
        }
    }
}

/// The logo's pulse: flat, P bump, dip, tall R spike, deep S, T bump, flat.
enum PulseWave {
    private static let points: [CGPoint] = [
        CGPoint(x: 0.00, y: 0.56), CGPoint(x: 0.22, y: 0.56), CGPoint(x: 0.27, y: 0.43), CGPoint(x: 0.31, y: 0.56),
        CGPoint(x: 0.36, y: 0.56), CGPoint(x: 0.40, y: 0.68), CGPoint(x: 0.46, y: 0.02), CGPoint(x: 0.53, y: 0.98),
        CGPoint(x: 0.58, y: 0.56), CGPoint(x: 0.64, y: 0.56), CGPoint(x: 0.69, y: 0.40), CGPoint(x: 0.74, y: 0.56),
        CGPoint(x: 1.00, y: 0.56),
    ]

    static func path(in rect: CGRect) -> Path {
        Path { p in
            for (i, pt) in points.enumerated() {
                let q = CGPoint(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        PulseLoader(phase: .running(progress: nil)).frame(width: 180, height: 60)
        PulseLoader(phase: .running(progress: 0.6)).frame(width: 180, height: 60)
        PulseLoader(phase: .done).frame(width: 180, height: 60)
        PulseLoader(phase: .failed).frame(width: 180, height: 60)
        PulseLoaderLabel(text: "Sincronizando…")
    }
    .padding()
    .background(PulsoBackground())
}
