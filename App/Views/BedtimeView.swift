import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoFeatures

/// «Me voy a dormir» (studio B-sueno 13): what you can sleep if you fall asleep now against what you need, the
/// night as a ruler, tomorrow's alarm, a quick journal, a minute of breathing and a calm send-off.
struct BedtimeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private static let quickHabits = ["alcohol", "late_caffeine", "late_meal", "screens_bed", "high_stress", "meditation", "reading", "magnesium"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.stack) {
                    Button("Cerrar") { dismiss() }
                        .dsFont(17).foregroundStyle(DS.t1).buttonStyle(.plain)
                        .padding(.top, 14)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Buenas noches").dsFont(34, .bold, relativeTo: .largeTitle, maxScale: 1.2).foregroundStyle(DS.t1)
                        Text("\(DSFmt.shortDate(DayKey.string(Date()))) · \(DSFmt.clock(Date()))").dsFont(15).foregroundStyle(DS.t2)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    planCard
                    DSSectionHeader("¿Qué ha habido hoy?")
                    SuenoFlow(spacing: 8) {
                        ForEach(Self.quickHabits, id: \.self) { key in chip(key) }
                    }
                    .dsCard(padding: 14)
                    Button {
                        model.startBreathingGuide()
                    } label: {
                        Label(model.breathingGuideActive ? "Respirando… sigue la vibración" : "1 minuto de respiración con la pulsera",
                              systemImage: "wind")
                            .dsFont(17, .semibold)
                            .foregroundStyle(DS.cons)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(DS.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.strapState.isConnected || model.breathingGuideActive)
                    .opacity(model.strapState.isConnected ? 1 : 0.5)
                    .padding(.top, 10)
                    Button {
                        model.goToSleep()
                        dismiss()
                    } label: {
                        Label("Me voy a dormir", systemImage: "moon.fill")
                    }
                    .buttonStyle(SuenoSolidButtonStyle())
                    Text("Deja Pulso en segundo plano (sin cerrarla) y el iPhone cerca, con Bluetooth.")
                        .dsFont(13).foregroundStyle(DS.t3).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, DS.gutter)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(DS.card.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.sheetRadius)
        .presentationBackground(DS.card)
        .preferredColorScheme(.dark)
    }

    // MARK: Plan

    private var planCard: some View {
        let plan = model.tonightPlan
        let next = model.nextAlarm
        let wake = next?.latest ?? plan?.wake
        let left = wake.map { $0.timeIntervalSinceNow / 60 - 15 }
        return VStack(alignment: .leading, spacing: 14) {
            if plan != nil || (left ?? 0) > 0 {
                HStack(alignment: .top) {
                    if let left, left > 0 {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Si te duermes ya").dsFont(14).foregroundStyle(DS.t2)
                            hours(min(left, 14 * 60), size: 34)
                        }
                    }
                    Spacer()
                    if let plan {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("Necesitas").dsFont(14).foregroundStyle(DS.t2)
                            hours(plan.needMinutes, size: 28)
                        }
                    }
                }
                if let wake, wake > Date() { ruler(wake: wake) }
                DSDivider()
            }
            HStack(spacing: 10) {
                Image(systemName: "alarm").font(.system(size: 15)).foregroundStyle(DS.sueno)
                Text("Despertador").dsFont(17).foregroundStyle(DS.t1)
                Spacer()
                if let next {
                    Text(next.isSmart ? "\(Fmt.clock(next.earliest))–\(Fmt.clock(next.latest))" : Fmt.clock(next.latest))
                        .dsFont(17, .semibold).foregroundStyle(DS.t1).lineLimit(1).minimumScaleFactor(0.8)
                } else {
                    Text("Sin alarma").dsFont(16).foregroundStyle(DS.t2)
                }
                NavigationLink { AlarmsView() } label: {
                    Text(next == nil ? "Poner una" : "Cambiar").dsFont(17, .semibold).foregroundStyle(DS.sueno)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(DS.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
    }

    private func hours(_ minutes: Double, size: CGFloat) -> some View {
        let m = Int(minutes.rounded())
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(m / 60)").dsFont(size, .semibold).foregroundStyle(DS.t1)
            Text("h").dsFont(size * 0.55, .medium).foregroundStyle(DS.t2).padding(.trailing, 4)
            Text(String(format: "%02d", m % 60)).dsFont(size, .semibold).foregroundStyle(DS.t1)
            if size > 30 { Text("min").dsFont(size * 0.55, .medium).foregroundStyle(DS.t2) }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// From now to the alarm on a clock ruler: «ahora» tick, violet bar, a handle at the wake time.
    private func ruler(wake: Date) -> some View {
        let cal = Calendar.current
        let now = Date()
        let a = cal.dateInterval(of: .hour, for: now.addingTimeInterval(-3600))?.start ?? now
        let b = cal.dateInterval(of: .hour, for: wake.addingTimeInterval(1800))?.end ?? wake
        let total = max(b.timeIntervalSince(a), 1)
        var marks: [Date] = []
        var t = a
        while t <= b {
            if cal.component(.hour, from: t) % 2 == 0 { marks.append(t) }
            t = t.addingTimeInterval(3600)
        }
        return GeometryReader { g in
            let x = { (d: Date) in g.size.width * CGFloat(d.timeIntervalSince(a) / total) }
            ZStack(alignment: .topLeading) {
                Text("ahora").dsFont(12, .semibold).foregroundStyle(DS.t1).fixedSize().position(x: x(now), y: 6)
                Rectangle().fill(DS.t1).frame(width: 2, height: 22).position(x: x(now), y: 30)
                Capsule().fill(DS.sueno.opacity(0.6)).frame(width: max(0, x(wake) - x(now)), height: 10)
                    .position(x: (x(now) + x(wake)) / 2, y: 30)
                RoundedRectangle(cornerRadius: 5).fill(DS.sueno).frame(width: 20, height: 20).position(x: x(wake), y: 30)
                ForEach(marks, id: \.self) { m in
                    Text(DSFmt.hour(Int(m.timeIntervalSince1970))).dsFont(12, .medium).foregroundStyle(DS.t3)
                        .fixedSize().position(x: x(m), y: 56)
                }
            }
        }
        .frame(height: 64)
        .accessibilityHidden(true)
    }

    private func chip(_ key: String) -> some View {
        let item = JournalCatalog.items.first { $0.key == key }
        let on = (model.journal(for: model.currentDayKey)[key] ?? 0) > 0
        return Button {
            model.setJournal(day: model.currentDayKey, key: key, on: !on)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item?.icon ?? "circle").font(.system(size: 14))
                Text(item?.label ?? key).dsFont(16, .semibold).lineLimit(1)
            }
            .foregroundStyle(DS.t1)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(on ? DS.sueno.opacity(0.35) : DS.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
