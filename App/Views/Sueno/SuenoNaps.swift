import SwiftUI
import PulsoStore
import PulsoAnalytics

/// «Siestas» (studio B-sueno 10 and 11): the open question about a recent daytime sleep, the day's daytime sleeps with
/// their menu (fue una siesta · era mi sueño · ajustar horas · no dormí), tonight's need and the week's naps.
struct SuenoNapsView: View {
    @EnvironmentObject var model: AppModel
    /// Screenshot runs only: open the first row's menu (with a sample nap when the demo has none).
    var demoMenu = false
    @State private var menuFor: Int?
    @State private var editing: SleepSession?
    @State private var addingNap = false

    private var demoNap: SleepSession {
        let start = Int((DayKey.date(model.selectedDay) ?? Date()).timeIntervalSince1970) + 15 * 3600 + 600
        return SleepSession(start: start, end: start + 22 * 60, isNap: true, minutesAwake: 1, minutesLight: 19, minutesDeep: 2)
    }

    var body: some View {
        let list = model.daytimeSleeps(on: model.selectedDay)
        let shown = list.isEmpty && demoMenu ? [demoNap] : list
        let questions = model.pendingSleepQuestions
        DSScreen("Siestas", subtitle: DSFmt.shortDate(model.selectedDay), back: "Sueño") {
            ForEach(questions, id: \.start) { q in SleepQuestionCard(session: q) }
            DSSectionHeader("Sueño durante el día")
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shown, id: \.start) { n in
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { menuFor = menuFor == n.start ? nil : n.start }
                    } label: { SuenoNapRow(nap: n) }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        if menuFor == n.start {
                            menu(n).offset(y: 52).transition(.opacity)
                        }
                    }
                    .zIndex(menuFor == n.start ? 2 : 0)
                    DSDivider()
                }
                Button { addingNap = true } label: {
                    Label("Añadir siesta", systemImage: "plus").dsFont(16, .semibold).foregroundStyle(DS.sueno)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .dsCard(padding: 16)
            .zIndex(2)
            if let plan = model.tonightPlan {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Image(systemName: "moon.fill").font(.system(size: 14)).foregroundStyle(DS.sueno)
                        Text("Esta noche necesitas").dsFont(17, .medium).foregroundStyle(DS.t1)
                        Spacer()
                        Text(DSFmt.duration(plan.needMinutes)).dsFont(18, .semibold).foregroundStyle(DS.t1)
                    }
                    if list.contains(where: { $0.isNap }) && model.selectedDay >= model.currentDayKey {
                        Text("la siesta ya está descontada").dsFont(13).foregroundStyle(DS.t2)
                    }
                }
                .dsCard(padding: 16)
            }
            week
        }
        .onAppear { if demoMenu { menuFor = shown.first?.start } }
        .sheet(item: $editing) { SleepEditSheet(session: $0).environmentObject(model) }
        .sheet(isPresented: $addingNap) { SleepEditSheet(session: nil, napDefault: true).environmentObject(model) }
    }

    private func menu(_ n: SleepSession) -> some View {
        VStack(spacing: 0) {
            item(n.isNap ? "checkmark" : nil, "Fue una siesta") { model.answerSleepQuestion(n, isNap: true) }
            DSDivider()
            item(n.isNap ? nil : "checkmark", "Era mi sueño") { model.answerSleepQuestion(n, isNap: false) }
            DSDivider()
            item("clock", "Ajustar horas") { editing = n }
            DSDivider()
            item("xmark.circle", n.manual ? "Eliminar" : "No dormí: descartar", destructive: true) {
                if n.manual { model.deleteSleep(n) } else { model.answerSleepQuestion(n, kind: .notSleep) }
            }
        }
        .frame(width: 250)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    private func item(_ icon: String?, _ title: String, destructive: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button {
            menuFor = nil
            action()
        } label: {
            HStack {
                Text(title).dsFont(16).foregroundStyle(destructive ? DSLevel.baja.ink : DS.t1)
                Spacer()
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(destructive ? DSLevel.baja.ink : DS.t1) }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Daytime naps of the last 7 days (what each day stored).
    @ViewBuilder
    private var week: some View {
        let keys = (0..<7).map { DayKey.shift(model.selectedDay, days: $0 - 6) }
        let naps = keys.map { k in (k, model.daytimeSleeps(on: k).filter { $0.isNap }) }
        let all = naps.flatMap(\.1)
        if !all.isEmpty {
            let maxM = max(naps.map { $0.1.reduce(0) { $0 + $1.asleepMinutes } }.max() ?? 1, 1)
            let mean = all.map(\.asleepMinutes).reduce(0, +) / Double(all.count)
            VStack(alignment: .leading, spacing: 14) {
                SuenoCardTitle(title: "Esta semana", note: "\(all.count) \(all.count == 1 ? "siesta" : "siestas") · media \(DSFmt.duration(mean))")
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(naps, id: \.0) { k, list in
                        let m = list.reduce(0) { $0 + $1.asleepMinutes }
                        VStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: m > 0 ? 7 : 2, style: .continuous)
                                .fill(k == model.selectedDay ? DS.sueno : DS.fill2)
                                .frame(width: m > 0 ? 22 : 18, height: m > 0 ? max(22, 56 * m / maxM) : 4)
                            Text(SFmt.weekdayLetter(k)).dsFont(13, k == model.selectedDay ? .bold : .medium)
                                .foregroundStyle(k == model.selectedDay ? DS.t1 : DS.t3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 86, alignment: .bottom)
            }
            .dsCard(padding: 16)
        }
    }
}
