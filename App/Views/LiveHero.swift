import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

// MARK: - Hero: live heart rate like a bedside monitor

/// Big number, beating heart, zone, and the last 90 s drawn as a line that scrolls continuously (every frame,
/// not every second) on a monitor grid, ending in a glowing dot.
struct LiveHeroMonitor: View {
    @EnvironmentObject var model: AppModel
    /// Edge to edge with no card: the grid runs the screen's width and fades into the page (health monitor).
    var fullBleed = false
    static let window: TimeInterval = 90

    var body: some View {
        let hr = model.liveToolBlocker == nil ? model.liveHR : nil
        let zone = hr.map { model.heartRateModel.zone(Double($0)) } ?? 0
        let monitor = ZStack(alignment: .topLeading) {
            if fullBleed {
                MonitorGrid(plain: true)
                    .mask(LinearGradient(colors: [.white, .white, .white.opacity(0)], startPoint: .top, endPoint: .bottom))
            } else {
                MonitorGrid()
            }
            TimelineView(.animation(minimumInterval: 1 / 60, paused: hr == nil)) { ctx in
                Canvas { g, size in
                    draw(&g, size: size, now: ctx.date, color: Theme.zoneColor(max(zone, 1)))
                }
            }
            .padding(.leading, fullBleed ? 100 : 120)
            VStack(alignment: .leading, spacing: fullBleed ? 4 : 6) {
                Caps("Frecuencia cardíaca", size: 12, color: .white)
                BeatingHeart(bpm: hr, color: hr == nil ? Theme.secondary : Theme.red)
                    .frame(width: fullBleed ? 22 : 28, height: fullBleed ? 22 : 28)
                Text(hr.map(String.init) ?? "--")
                    .scaledFont(fullBleed ? 44 : 56, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(hr ?? 0)))
                    .animation(.snappy, value: hr)
                Caps("lpm", size: 11, color: Theme.secondary)
                Text(hr == nil ? statusText : (zone == 0 ? "Zona 0 · reposo" : "Zona \(zone)"))
                    .font(.subheadline).foregroundStyle(hr == nil ? Theme.yellow : .white)
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { z in
                        Capsule().fill(z <= zone ? Theme.zoneColor(z) : Color.white.opacity(0.15)).frame(width: 18, height: 4)
                    }
                }
            }
            .padding(16)
        }
        if fullBleed {
            monitor.frame(height: 190).padding(.horizontal, -16)
        } else {
            monitor
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.hairline))
        }
    }

    private var statusText: String {
        if let why = model.liveToolBlocker { return why }
        return model.strapState.isConnected ? "Esperando latidos…" : "Conecta la pulsera"
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, now: Date, color: Color) {
        let from = now.addingTimeInterval(-Self.window)
        let pts = model.livePoints.filter { $0.date >= from.addingTimeInterval(-3) }
        guard pts.count >= 2 else {
            var flat = Path()
            flat.move(to: CGPoint(x: 0, y: size.height * 0.55))
            flat.addLine(to: CGPoint(x: size.width - 16, y: size.height * 0.55))
            g.stroke(flat, with: .color(Color.white.opacity(0.15)), lineWidth: 2)
            return
        }
        let values = pts.map { Double($0.hr) }
        let lo = (values.min() ?? 60) - 8, hi = (values.max() ?? 100) + 8
        let right = size.width - 16
        func p(_ point: LivePoint) -> CGPoint {
            let x = CGFloat(point.date.timeIntervalSince(from) / Self.window) * right
            let y = size.height * (0.15 + 0.7 * CGFloat(1 - (Double(point.hr) - lo) / max(hi - lo, 1)))
            return CGPoint(x: x, y: y)
        }
        // The newest reading slides to the right edge as time passes, so the line never jumps.
        var cg = pts.map(p)
        if let last = cg.last { cg.append(CGPoint(x: min(right, last.x + 2), y: last.y)) }
        var path = Path()
        path.move(to: cg[0])
        for i in 1..<cg.count {
            let mid = CGPoint(x: (cg[i - 1].x + cg[i].x) / 2, y: (cg[i - 1].y + cg[i].y) / 2)
            path.addQuadCurve(to: mid, control: cg[i - 1])
        }
        path.addLine(to: cg.last!)
        var glow = g
        glow.addFilter(.blur(radius: 6))
        glow.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 6)
        g.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0), color]), startPoint: .zero,
                                            endPoint: CGPoint(x: right, y: 0)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let end = cg.last!
        var dash = Path()
        dash.move(to: CGPoint(x: end.x, y: 8))
        dash.addLine(to: CGPoint(x: end.x, y: size.height - 8))
        g.stroke(dash, with: .color(Color.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        g.fill(Path(ellipseIn: CGRect(x: end.x - 9, y: end.y - 9, width: 18, height: 18)), with: .color(color.opacity(0.35)))
        g.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)), with: .color(.white))
    }
}

/// Faint monitor grid behind the live line.
struct MonitorGrid: View {
    /// No card behind the lines.
    var plain = false

    var body: some View {
        Canvas { g, size in
            let step: CGFloat = 22
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            g.stroke(path, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
        }
        .background(LinearGradient(colors: [Theme.card, Theme.card.opacity(0.6)], startPoint: .top, endPoint: .bottom).opacity(plain ? 0 : 1))
    }
}

// MARK: - Heart-rate history

struct LiveHRHistoryCard: View {
    @EnvironmentObject var model: AppModel
    @State private var period: HRPeriod = .hour
    @State private var series: HRHistory.Series?

    var body: some View {
        PCard {
            CardHeader(title: "Historial de pulso")
            Picker("Periodo", selection: $period) {
                ForEach(HRPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if let s = series {
                if s.points.isEmpty {
                    Text("Sin datos en este periodo todavía.").font(.footnote).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    HRHistoryChart(series: s).frame(height: 180)
                    HStack {
                        Text("Media \(s.enoughData ? Fmt.int(s.average) : "–")")
                        Spacer()
                        Text("Mín \(s.enoughData ? s.min.map(String.init) ?? "–" : "–") · Máx \(s.enoughData ? s.max.map(String.init) ?? "–" : "–")")
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                }
            } else {
                PulseLoader(phase: .running(progress: nil), style: .compact).frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .task(id: period) {
            let every: UInt64 = period.seconds <= 7200 ? 15 : 120
            series = nil
            while !Task.isCancelled {
                let s = await model.hrHistory(period)
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.4)) { series = s }
                try? await Task.sleep(nanoseconds: every * 1_000_000_000)
            }
        }
    }
}

// MARK: - Compact actions

/// A small round tool button (icon + one word).
struct ToolChip<Destination: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(color)
                    .frame(width: 52, height: 52)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.hairline))
                Text(title).font(.caption2).foregroundStyle(.white).lineLimit(1)
            }
            .frame(width: 70)
        }
        .buttonStyle(.plain)
    }
}
