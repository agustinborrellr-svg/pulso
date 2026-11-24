import SwiftUI

/// Tab «Actividad» (studio C-actividad 01/02): the redesigned root. When a workout starts (from «Iniciar actividad»,
/// Sauna or Baño de hielo) the live screen opens full screen; ⌄ brings you back here with a banner to return to it.
struct ActivityTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router

    var body: some View {
        ActivityRootView()
            .onChange(of: model.liveWorkout != nil) { _, running in
                guard running, router.cover == nil else { return }
                // Let a closing sheet («Iniciar actividad») finish before presenting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if model.liveWorkout != nil, router.cover == nil { router.open(.actividad(.entrenoVivo)) }
                }
            }
    }
}
