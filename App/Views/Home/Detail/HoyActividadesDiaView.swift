import SwiftUI
import PulsoStore
import PulsoAnalytics

/// 14 Actividades del día: totals (asleep, activities, active time, strain) and Hoy's activities card in full.
struct HoyActividadesDiaView: View {
    @EnvironmentObject var model: AppModel
    let day: DaySummary

    var body: some View {
        let items = model.activities(on: day)
        let slept = items.filter { if case .workout = $0.kind { return false } else { return true } }
        let active = items.filter { if case .workout = $0.kind { return true } else { return false } }
        DSScreen("Actividades", subtitle: DSFmt.shortDate(day.day), back: "Hoy") {
            DSStatStrip(stats: [
                DSStat(label: "Dormido", value: slept.isEmpty ? "–" : Fmt.hmm(slept.reduce(0) { $0 + $1.minutes })),
                DSStat(label: "Actividades", value: "\(active.count)"),
                DSStat(label: "Activo", value: active.isEmpty ? "–" : Fmt.hmm(active.reduce(0) { $0 + $1.minutes })),
                DSStat(label: "Esfuerzo", value: Fmt.dec(day.strain)),
            ])
            .dsCard(padding: 14)
            HoyActivitiesBlock(day: day, showHeader: false)
            Text("El sueño y los entrenos aparecen solos. Toca una para ver su detalle.")
                .dsFont(13).foregroundStyle(DS.t3).padding(.horizontal, 4)
        }
    }
}
