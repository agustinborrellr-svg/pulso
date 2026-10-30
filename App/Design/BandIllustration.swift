import SwiftUI

/// The Pulse Band drawn in code, top-down: a narrow rounded sensor pod on a knit band.
/// `metallic` gives the MG its brushed-metal top; `showSensors` shows the underside sensor window;
/// `ledBlue` pulses the pairing LED; `tapHint` adds tap ripples on the pod.
struct StrapIllustration: View {
    var ledBlue = false
    var showSensors = false
    var tapHint = false
    var metallic = false
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width / 0.9, geo.size.height / 1.25)
            let bandW = u * 0.30, podW = u * 0.40, podH = u * 0.62
            ZStack {
                KnitBand(width: bandW)
                    .frame(width: bandW, height: geo.size.height * 1.15)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.22),
                                                 .init(color: .white, location: 0.78), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                // Contact shadow of the pod on the band.
                RoundedRectangle(cornerRadius: podW * 0.36, style: .continuous)
                    .fill(Color.black.opacity(0.7))
                    .frame(width: podW * 1.02, height: podH * 1.02)
                    .blur(radius: u * 0.035)
                    .offset(x: u * 0.012, y: u * 0.03)
                SensorPod(width: podW, height: podH, metallic: metallic, underside: showSensors,
                          led: ledBlue ? (pulse ? 1 : 0.3) : 0)
                if tapHint {
                    ForEach(0..<2, id: \.self) { i in
                        Circle()
                            .stroke(Theme.link.opacity(pulse ? 0 : 0.8), lineWidth: 1.5)
                            .frame(width: podW * 0.5, height: podW * 0.5)
                            .scaleEffect(pulse ? 1.8 + Double(i) * 0.5 : 0.6)
                    }
                    Circle().fill(Color.white.opacity(0.9)).frame(width: u * 0.045, height: u * 0.045)
                }
            }
            .rotationEffect(.degrees(-14))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            guard !reduceMotion, ledBlue || tapHint else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: !tapHint)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// Knit band: dark strap with woven rows, soft side shading and stitched edges.
private struct KnitBand: View {
    let width: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.12, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.07), Color(white: 0.15), Color(white: 0.16), Color(white: 0.08)],
                                     startPoint: .leading, endPoint: .trailing))
            Canvas { ctx, size in
                // Chevron rows of the knit.
                let row: CGFloat = max(2.6, width * 0.05)
                let cols = 7
                let cw = size.width / CGFloat(cols)
                var y: CGFloat = 0
                var odd = false
                while y < size.height {
                    var p = Path()
                    for c in 0..<cols {
                        let x0 = CGFloat(c) * cw + (odd ? cw / 2 : 0)
                        p.move(to: CGPoint(x: x0, y: y))
                        p.addLine(to: CGPoint(x: x0 + cw / 2, y: y + row * 0.7))
                        p.addLine(to: CGPoint(x: x0 + cw, y: y))
                    }
                    ctx.stroke(p, with: .color(.white.opacity(0.07)), lineWidth: 0.8)
                    y += row
                    odd.toggle()
                }
                // Stitched edges.
                let inset = size.width * 0.07
                for x in [inset, size.width - inset] {
                    var e = Path()
                    e.move(to: CGPoint(x: x, y: 0))
                    e.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(e, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 0.8, dash: [2.5, 2]))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: width * 0.12, style: .continuous))
        }
    }
}

/// The sensor pod: rim, top face (matte or brushed metal), glint and status LED; or its sensor window underneath.
private struct SensorPod: View {
    let width: CGFloat
    let height: CGFloat
    let metallic: Bool
    let underside: Bool
    /// LED glow 0…1.
    let led: Double

    var body: some View {
        let r = width * 0.36
        let shape = RoundedRectangle(cornerRadius: r, style: .continuous)
        let inset = width * 0.07
        ZStack {
            // Body and rim.
            shape.fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.10), Color(white: 0.04)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.05), Color.white.opacity(0.18)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            // Top face.
            RoundedRectangle(cornerRadius: r - inset, style: .continuous)
                .fill(face)
                .padding(inset)
            if underside {
                sensorWindow
            } else {
                // Glint along the long edge.
                RoundedRectangle(cornerRadius: r - inset, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(metallic ? 0.55 : 0.28), .clear],
                                           startPoint: .topLeading, endPoint: .center), lineWidth: 1.2)
                    .padding(inset)
                Capsule()
                    .fill(Color(red: 0.35, green: 0.62, blue: 1.0).opacity(0.25 + 0.75 * led))
                    .frame(width: width * 0.16, height: width * 0.035)
                    .shadow(color: Theme.link.opacity(led), radius: 8 * led)
                    .offset(y: -height * 0.36)
            }
        }
        .frame(width: width, height: height)
    }

    private var face: some ShapeStyle {
        if metallic {
            return AnyShapeStyle(AngularGradient(colors: [Color(white: 0.62), Color(white: 0.34), Color(white: 0.55), Color(white: 0.28), Color(white: 0.62)],
                                                 center: .center))
        }
        return AnyShapeStyle(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
    }

    /// Underside: optical window with green LEDs and photodiodes.
    private var sensorWindow: some View {
        ZStack {
            Capsule()
                .fill(Color(white: 0.03))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8))
                .frame(width: width * 0.42, height: height * 0.58)
            VStack(spacing: height * 0.05) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == 1 || i == 2 ? Color(red: 0.2, green: 0.9, blue: 0.45).opacity(0.85) : Color(white: 0.32))
                        .frame(width: width * 0.09, height: width * 0.09)
                        .shadow(color: i == 1 || i == 2 ? Color.green.opacity(0.6) : .clear, radius: 4)
                }
            }
        }
    }
}

#Preview {
    HStack {
        StrapIllustration()
        StrapIllustration(metallic: true)
        StrapIllustration(ledBlue: true, tapHint: true)
        StrapIllustration(showSensors: true)
    }
    .frame(height: 260)
    .background(PulsoBackground())
}
