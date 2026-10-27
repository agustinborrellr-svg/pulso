import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics

/// Edad Pulso week by week for the last six months, against your calendar age.
struct AgeTrendCard: View {
    @EnvironmentObject var model: AppModel

    private var points: [(day: String, age: Double)] {
        let today = model.currentDayKey
        return (0..<26).reversed().compactMap { w -> (String, Double)? in
            let end = DayKey.shift(today, days: -7 * w)
            let r = PulsoAge.compute(days: model.days.filter { $0.day <= end }, profile: model.profile, today: end)
            return r.pulsoAge.map { (end, $0) }
        }
    }

    var body: some View {
        let pts = points
        if pts.count >= 2 {
            PCard {
                CardHeader(title: "Tendencia de tu Edad Pulso")
                HStack(spacing: 14) {
                    HStack(spacing: 6) { Rectangle().fill(Theme.link).frame(width: 12, height: 3); Caps("Edad Pulso", size: 10, color: Theme.secondary) }
                    HStack(spacing: 6) { Rectangle().fill(.white).frame(width: 12, height: 3); Caps("Edad real", size: 10, color: Theme.secondary) }
                }
                Chart {
                    ForEach(pts, id: \.day) { p in
                        LineMark(x: .value("Semana", p.day), y: .value("Edad Pulso", p.age), series: .value("s", "pulso"))
                            .foregroundStyle(Theme.link)
                            .interpolationMethod(.stepEnd)
                    }
                    RuleMark(y: .value("Edad real", Double(model.profile.age)))
                        .foregroundStyle(.white.opacity(0.8))
                    if let last = pts.last {
                        PointMark(x: .value("Semana", last.day), y: .value("Edad Pulso", last.age))
                            .foregroundStyle(Theme.link)
                            .annotation(position: .top) { Text(Fmt.dec(last.age)).font(.caption.bold()).foregroundStyle(Theme.link) }
                    }
                }
                .chartXScale(domain: pts.map(\.day))
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: pts.enumerated().filter { $0.offset % 6 == 0 }.map(\.element.day)) { v in
                        AxisValueLabel { Text(Fmt.shortDay(v.as(String.self) ?? "")).font(.system(size: 9)).foregroundStyle(Theme.secondary) }
                    }
                }
                .frame(height: 180)
            }
        }
    }
}
