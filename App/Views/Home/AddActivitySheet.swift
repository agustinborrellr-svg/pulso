import SwiftUI
import PulsoStore
import PulsoIntegrations

/// 15 Agregar actividad: something the strap didn't detect (or you want named): pick it, say when, and where you wore
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
            VStack(spacing: 0) {
                DSSheetHeader("Agregar actividad")
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pulso calcula el esfuerzo, el pulso y las zonas con lo que midió la pulsera en ese rato.")
                            .dsFont(15).foregroundStyle(DS.t2).fixedSize(horizontal: false, vertical: true)
                        HoySheetLabel("Actividad")
                        NavigationLink { ActivityPickerView(selection: $activity) } label: {
                            HoySheetGroup {
                                HStack(spacing: 14) {
                                    Image(systemName: activity.map(ActivityPickerView.symbol) ?? "figure.mixed.cardio")
                                        .font(.system(size: 18)).foregroundStyle(activity == nil ? DS.t3 : DS.act).frame(width: 26)
                                    Text(activity ?? "Elige una actividad").dsFont(19, .semibold)
                                        .foregroundStyle(activity == nil ? DS.t2 : DS.t1).lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text(activity == nil ? "Elegir" : "Cambiar").dsFont(16).foregroundStyle(DS.t2)
                                    DSChevron()
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 58)
                                .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(.plain)
                        HoySheetLabel("Tiempo")
                        HoySheetGroup {
                            timeRow("Inicio", $start)
                            DSDivider(inset: 14)
                            timeRow("Fin", $end)
                        }
                        if end <= start {
                            Text("El fin tiene que ser después del inicio.").dsFont(13).foregroundStyle(DSLevel.justa.ink).padding(.leading, 4)
                        }
                        HoySheetLabel("Ubicación")
                        HoySheetGroup {
                            Menu {
                                Picker("Dónde llevabas la pulsera", selection: $placement) {
                                    ForEach(Self.placements, id: \.self) { Text($0 == "—" ? "Sin indicar" : $0).tag($0) }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Dónde llevabas la pulsera").dsFont(16, .medium).foregroundStyle(DS.t1).lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer(minLength: 6)
                                    Text(placement == "—" ? "Sin indicar" : placement).dsFont(16).foregroundStyle(DS.t2).lineLimit(1)
                                    DSChevron()
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Button("Guardar", action: save)
                            .buttonStyle(DSButtonStyle(tint: DS.act, size: .xl, fullWidth: true))
                            .disabled(!valid)
                            .opacity(valid ? 1 : 0.5)
                            .padding(.top, 22)
                    }
                    .padding(.horizontal, DS.gutter)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .background(DS.card.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: start) { _, s in
                if end <= s { end = min(s.addingTimeInterval(3600), Date()) }
            }
        }
        .dsSheet()
    }

    private func timeRow(_ title: String, _ date: Binding<Date>) -> some View {
        HStack {
            Text(title).dsFont(16, .medium).foregroundStyle(DS.t1)
            Spacer()
            DatePicker(title, selection: date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "es_ES"))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
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

/// 16 Elegir actividad: search, Todo / Esfuerzo / Recuperación / Sueño, your recent ones, then A to Z.
struct ActivityPickerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String?
    /// Only sports (starting an activity live: no sleep).
    var sportsOnly = false
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

    private var tabs: [Tab] { sportsOnly ? [.all, .effort, .recovery] : Tab.allCases }

    private var list: [String] {
        let sports = SportCatalog.all.filter { s in
            switch tab {
            case .all: return true
            case .effort: return s.kind == .effort
            case .recovery: return s.kind == .recovery
            case .sleep: return false
            }
        }.map(\.name)
        let sleeps = !sportsOnly && (tab == .all || tab == .sleep) ? Self.sleepKinds : []
        return (sports + sleeps).filter(matches).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        let recent = tab == .all && query.isEmpty ? model.recentActivityNames() : []
        VStack(spacing: 0) {
            DSSheetHeader("Elegir actividad") {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold)).foregroundStyle(DS.t2)
                        .frame(width: 32, height: 32).background(DS.fill, in: Circle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Atrás")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(DS.t3)
                        TextField("Buscar actividades", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .dsFont(16)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(DS.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    DSSegmented(options: tabs.map { ($0, $0.rawValue) }, selection: $tab)
                        .padding(.vertical, 4)
                    if !recent.isEmpty {
                        HoySheetLabel("Recientes")
                        HoySheetGroup {
                            ForEach(recent.indices, id: \.self) { i in
                                if i > 0 { DSDivider(inset: 50) }
                                row(recent[i])
                            }
                        }
                        HoySheetLabel("De la A a la Z")
                    }
                    HoySheetGroup {
                        ForEach(list.indices, id: \.self) { i in
                            if i > 0 { DSDivider(inset: 50) }
                            row(list[i])
                        }
                    }
                    if list.isEmpty {
                        Text("Ninguna actividad con «\(query)».").dsFont(15).foregroundStyle(DS.t2).padding(.top, 20)
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .background(DS.card.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ name: String) -> some View {
        Button {
            selection = name
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: Self.symbol(name)).font(.system(size: 16)).foregroundStyle(DS.t2).frame(width: 22)
                Text(name).dsFont(16, .medium).foregroundStyle(DS.t1).lineLimit(1)
                Spacer()
                if selection == name { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(DS.act) }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
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
