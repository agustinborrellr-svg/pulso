import SwiftUI
import PulsoStore
import PulsoIntegrations

/// "+ AGREGAR ACTIVIDAD": something the strap didn't detect (or you want named): pick it, say when, and where you wore
/// the strap. Strain, heart rate and zones are then computed from the strap's own data for that window; a nap or a
/// sleep is saved as sleep.
struct AddActivitySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var activity: String?
    @State private var start = Date().addingTimeInterval(-3600)
    @State private var end = Date()
    @State private var placement = "—"

    static let placements = ["—", "Muñequera", "Banda para el bíceps", "Manga de brazo", "Ropa interior", "Sujetador",
                             "Bermudas", "Top de compresión", "Leggings"]

    private var valid: Bool { activity != nil && end > start && end <= Date().addingTimeInterval(60) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.link)
                        Text("Si llevabas la pulsera, Pulso calcula el esfuerzo, el pulso y las zonas con lo que midió en ese rato.")
                            .font(.footnote).foregroundStyle(Theme.link)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.link.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    NavigationLink { ActivityPickerView(selection: $activity) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: activity.map(ActivityPickerView.symbol) ?? "figure.arms.open")
                                .font(.title3).foregroundStyle(activity == nil ? Theme.secondary : .white).frame(width: 26)
                            Caps(activity ?? "Seleccionar actividad", size: 13)
                            Spacer()
                            Image(systemName: "chevron.right").font(.headline).foregroundStyle(.white)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    section("Tiempo") {
                        timeRow("Hora de inicio", $start)
                        timeRow("Hora de finalización", $end)
                        if end <= start {
                            Label("La hora de finalización tiene que ser después del inicio.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(Theme.yellow)
                        }
                    }

                    section("Ubicación") {
                        Text("¿Dónde llevabas puesta la pulsera?").font(.subheadline).foregroundStyle(.white)
                        Picker("Ubicación", selection: $placement) {
                            ForEach(Self.placements, id: \.self) { Text($0.uppercased()).tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 140)
                    }

                    Button("Guardar", action: save)
                        .buttonStyle(PrimaryCapsuleStyle())
                        .disabled(!valid)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(PulsoBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Caps("Agregar actividad", size: 13) }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.white) }
                        .accessibilityLabel("Cerrar")
                }
            }
            .onChange(of: start) { _, s in
                if end <= s { end = min(s.addingTimeInterval(3600), Date()) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Caps(title, size: 10, color: Theme.secondary, weight: .semibold)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            content()
        }
    }

    private func timeRow(_ title: String, _ date: Binding<Date>) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.white)
            Spacer()
            DatePicker(title, selection: date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
        }
    }

    private func save() {
        guard let activity, valid else { return }
        if ActivityPickerView.sleepKinds.contains(activity) {
            model.addManualSleep(start: start, end: end, nap: activity == "Siesta")
        } else {
            let w = Workout(start: Int(start.timeIntervalSince1970), end: Int(end.timeIntervalSince1970), sport: activity,
                            source: .manual, notes: placement == "—" ? "" : "Pulsera en: \(placement.lowercased())")
            model.saveWorkout(w)
        }
        dismiss()
    }
}

/// "SELECCIONAR ACTIVIDAD": search, Todo / Esfuerzo / Recuperación / Sueño, your recent ones, then A to Z.
struct ActivityPickerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String?
    @State private var query = ""
    @State private var tab = Tab.all

    enum Tab: String, CaseIterable { case all = "Todo", effort = "Esfuerzo", recovery = "Recuperación", sleep = "Sueño" }

    static let sleepKinds = ["Siesta", "Sueño"]

    static func symbol(_ name: String) -> String {
        switch name {
        case "Siesta": return "moon.zzz.fill"
        case "Sueño": return "moon.fill"
        default: return SportCatalog.named(name).symbol
        }
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private var list: [String] {
        let sports = SportCatalog.all.filter { s in
            switch tab {
            case .all: return true
            case .effort: return s.kind == .effort
            case .recovery: return s.kind == .recovery
            case .sleep: return false
            }
        }.map(\.name)
        let sleeps = tab == .all || tab == .sleep ? Self.sleepKinds : []
        return (sports + sleeps).filter(matches).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        let recent = tab == .all && query.isEmpty ? model.recentActivityNames() : []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                    TextField("Buscar actividades", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack(spacing: 18) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Button { tab = t } label: {
                            VStack(spacing: 6) {
                                Caps(t.rawValue, size: 10, color: tab == t ? .white : Theme.secondary, weight: .semibold)
                                Rectangle().fill(tab == t ? Color.white : .clear).frame(height: 2)
                            }
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                if !recent.isEmpty {
                    Caps("Más recientes", size: 9.5, color: Theme.secondary, weight: .semibold).padding(.top, 6)
                    // Own ids: the same name shows again in the A–Z list, and a lazy stack drops repeated ids.
                    ForEach(recent.map { "recent:" + $0 }, id: \.self) { row(String($0.dropFirst(7))) }
                    Caps("Todo de la A a la Z", size: 9.5, color: Theme.secondary, weight: .semibold).padding(.top, 10)
                }
                ForEach(list, id: \.self) { row($0) }
                if list.isEmpty {
                    Text("Ninguna actividad con «\(query)».").font(.subheadline).foregroundStyle(Theme.secondary).padding(.top, 20)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .background(PulsoBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Caps("Seleccionar actividad", size: 13) } }
    }

    private func row(_ name: String) -> some View {
        Button {
            selection = name
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: Self.symbol(name)).font(.body).foregroundStyle(Theme.secondary).frame(width: 24)
                Caps(name, size: 12)
                Spacer()
                if selection == name { Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension AppModel {
    /// Activities you logged lately, the most recent first (for the top of the picker).
    func recentActivityNames(limit: Int = 4) -> [String] {
        let now = Int(Date().timeIntervalSince1970)
        let recent = ((try? db.workouts(from: now - 60 * 86_400, to: now + 60)) ?? []).sorted { $0.start > $1.start }
        var out: [String] = []
        for w in recent where !out.contains(w.sport) {
            out.append(w.sport)
            if out.count == limit { break }
        }
        return out
    }
}
