import SwiftUI
import PulsoStore
import PulsoFeatures
import PulsoIntegrations
import PulsoAnalytics

/// 17 Iniciar actividad: the sport (your recent ones first), the real interval plans of the app, «Empezar» and
/// «¿Ya la hiciste?» (opens «Agregar actividad»).
struct HoyStartActivitySheet: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var sport: String?
    @State private var planID = ""
    @State private var picking = false

    private var tiles: [String] {
        var out: [String] = []
        if let sport { out.append(sport) }
        for s in model.recentActivityNames(limit: 6) + ["Carrera", "Ciclismo", "Fuerza", "Caminata"]
        where !out.contains(s) && !ActivityPickerView.sleepKinds.contains(s) && !Breathwork.activityNames.contains(s) {
            out.append(s)
            if out.count == 4 { break }
        }
        return out
    }

    private var chosen: String { sport ?? tiles.first ?? "Carrera" }
    private var plan: IntervalPlan? { IntervalPlan.presets.first { $0.id == planID } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DSSheetHeader("Iniciar actividad")
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HoySheetLabel("Deporte")
                        HStack(spacing: 8) {
                            ForEach(tiles, id: \.self) { tile($0) }
                        }
                        NavigationLink {
                            ActivityPickerView(selection: $sport, sportsOnly: true)
                        } label: {
                            HStack(spacing: 4) {
                                Text("Más deportes").dsFont(16, .semibold)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(DS.t2)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .frame(minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        HoySheetLabel("Plan")
                        HoySheetGroup {
                            planRow(id: "", name: "Libre", detail: nil)
                            ForEach(IntervalPlan.presets) { p in
                                DSDivider(inset: 14)
                                planRow(id: p.id, name: p.name, detail: p.detail)
                            }
                        }
                        if let plan {
                            Text("\(plan.totalSeconds / 60) min en total. La pulsera vibra en cada cambio\(model.settings.voiceCues ? " y una voz te guía" : "").")
                                .dsFont(13).foregroundStyle(DS.t3).padding(.horizontal, 4)
                        }
                        Button {
                            model.startWorkout(sport: chosen, plan: plan)
                        } label: {
                            Label("Empezar", systemImage: "play.fill")
                        }
                        .buttonStyle(DSButtonStyle(tint: DS.act, size: .xl, fullWidth: true))
                        .disabled(!model.strapState.isConnected)
                        .opacity(model.strapState.isConnected ? 1 : 0.5)
                        .padding(.top, 18)
                        if !model.strapState.isConnected {
                            Text("Conecta la pulsera para registrarla en directo.").dsFont(13).foregroundStyle(DSLevel.justa.ink)
                                .frame(maxWidth: .infinity)
                        }
                        Button {
                            router.sheet = .hoy(.anadirActividad)
                        } label: {
                            Label("¿Ya la hiciste? Añádela a mano", systemImage: "clock")
                                .dsFont(16, .semibold).foregroundStyle(DS.t2)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .background(DS.card.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: model.liveWorkout != nil) { _, started in if started { dismiss() } }
        }
        .dsSheet()
    }

    private func tile(_ name: String) -> some View {
        let on = name == chosen
        return Button { sport = name } label: {
            VStack(spacing: 8) {
                Image(systemName: ActivityPickerView.symbol(name)).font(.system(size: 20))
                    .foregroundStyle(on ? DS.act : DS.t2)
                Text(name).dsFont(15, .semibold).foregroundStyle(on ? DS.t1 : DS.t2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(.horizontal, 4)
            .background(on ? DS.act.opacity(DS.tintOpacity) : DS.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? DS.act : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func planRow(id: String, name: String, detail: String?) -> some View {
        let on = planID == id
        return Button { planID = id } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).dsFont(17, .medium).foregroundStyle(DS.t1)
                    if on, let detail {
                        Text(detail).dsFont(14).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(DS.act) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
