import SwiftUI
import PulsoStore
import PulsoAnalytics
import PulsoFeatures

/// "Me voy a dormir": tomorrow's alarm, tonight's need, a quick journal and a calm send-off.
struct BedtimeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private static let quickHabits = ["alcohol", "late_caffeine", "late_meal", "screens_bed", "high_stress", "meditation", "reading", "magnesium"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Theme.sleep)
                        .padding(.top, 8)
                    Text("Buenas noches").font(.title.bold())

                    Card {
                        if let next = model.nextAlarm {
                            HStack {
                                Image(systemName: "alarm.fill").foregroundStyle(Theme.sleep)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(next.isSmart ? "Entre \(Fmt.clock(next.earliest)) y \(Fmt.clock(next.latest))" : "A las \(Fmt.clock(next.latest))")
                                        .font(.headline)
                                    Text("\(next.alarm.label) · \(next.alarm.mode.label.lowercased())").font(.caption).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                NavigationLink("Cambiar") { AlarmsView() }.font(.subheadline)
                            }
                        } else {
                            HStack {
                                Image(systemName: "alarm").foregroundStyle(Theme.secondary)
                                Text("Sin alarma para mañana").font(.subheadline)
                                Spacer()
                                NavigationLink("Poner una") { AlarmsView() }.font(.subheadline)
                            }
                        }
                        if let plan = model.tonightPlan {
                            Divider().overlay(Color.white.opacity(0.1))
                            let left = plan.wake.timeIntervalSinceNow / 60 - 15
                            HStack {
                                Image(systemName: "bed.double.fill").foregroundStyle(Theme.sleep)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Necesitas \(Fmt.hm(plan.needMinutes)) esta noche").font(.subheadline.bold())
                                    Text(left > 0 ? "Si te duermes ya, podrías dormir \(Fmt.hm(min(left, 14 * 60)))." : "")
                                        .font(.caption).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                    }

                    Card {
                        SectionTitle(title: "¿Qué ha habido hoy?", subtitle: "Para aprender qué te afecta")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                            ForEach(Self.quickHabits, id: \.self) { key in
                                let item = JournalCatalog.items.first { $0.key == key }
                                let on = (model.journal(for: DayKey.string(Date()))[key] ?? 0) > 0
                                Button {
                                    model.setJournal(day: DayKey.string(Date()), key: key, on: !on)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: item?.icon ?? "circle")
                                        Text(item?.label ?? key).lineLimit(1).minimumScaleFactor(0.8)
                                        Spacer(minLength: 0)
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 9)
                                    .foregroundStyle(on ? Color.black : Color.white)
                                    .background(on ? Theme.sleep : Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        model.startBreathingGuide()
                    } label: {
                        Label(model.breathingGuideActive ? "Respirando… sigue la vibración" : "1 minuto de respiración con la pulsera",
                              systemImage: "wind")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.strapState.isConnected || model.breathingGuideActive)

                    Button {
                        model.goToSleep()
                        dismiss()
                    } label: {
                        Text("Me voy a dormir").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.sleep)

                    Text("Deja Pulso en segundo plano (sin cerrarla) y el iPhone cerca, con Bluetooth activado.")
                        .font(.caption).foregroundStyle(Theme.tertiary).multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Evening card on Today that opens the bedtime sheet.
struct BedtimeCard: View {
    @EnvironmentObject var model: AppModel
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "moon.zzz.fill").font(.title2).foregroundStyle(Theme.sleep)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Me voy a dormir").font(.headline).foregroundStyle(.white)
                    Text(model.tonightPlan.map { "Lo ideal: acostarte a las \(Fmt.clock($0.bedtime))" } ?? "Prepara la alarma y apunta tu día")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { BedtimeView().environmentObject(model) }
    }
}
