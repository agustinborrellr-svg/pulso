import SwiftUI
import PulsoStore
import PulsoAnalytics

/// «Ajustar sueño» / «Añadir sueño» (studio B-sueno 12): the night as a ruler with two handles, the exact date and
/// time of falling asleep and waking up, and «Eliminar este sueño».
struct SleepEditSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let session: SleepSession?
    /// The day whose night is being added (the night that ends that morning); defaults to the selected day.
    var forDay: String?
    var napDefault = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var isNap = false
    @State private var confirmDelete = false
    /// Ruler span, fixed when the sheet opens.
    @State private var span: ClosedRange<Date>?

    private var valid: Bool { end > start && end.timeIntervalSince(start) <= 16 * 3600 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(session == nil ? "Añadir sueño" : "Ajustar sueño").dsFont(17, .semibold).foregroundStyle(DS.t1)
                HStack {
                    Button("Cancelar") { dismiss() }.foregroundStyle(DS.t1)
                    Spacer()
                    Button("Guardar") {
                        if let s = session {
                            model.saveSleepEdit(s, start: start, end: end)
                        } else {
                            model.addManualSleep(start: start, end: end, nap: isNap)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(valid ? DS.sueno : DS.t3)
                    .disabled(!valid)
                }
                .dsFont(17)
                .buttonStyle(.plain)
            }
            .frame(height: 50)
            .padding(.top, 12)
            .padding(.horizontal, DS.gutter)
            ScrollView {
                VStack(alignment: .leading, spacing: DS.stack) {
                    if let span { ruler(span).dsCard(padding: 16) }
                    VStack(spacing: 0) {
                        timeRow("Me dormí", $start)
                        DSDivider(inset: 14)
                        timeRow("Me desperté", $end)
                        if session == nil {
                            DSDivider(inset: 14)
                            Toggle("Es una siesta", isOn: $isNap)
                                .dsFont(17).foregroundStyle(DS.t1)
                                .tint(DS.sueno)
                                .padding(.horizontal, 14).frame(minHeight: 52)
                        }
                    }
                    .background(DS.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                    Text("Las fases, la VFC y la recuperación se recalculan con las horas que indiques.")
                        .dsFont(13).foregroundStyle(DS.t2)
                        .padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                    if !valid {
                        Text(end <= start ? "La hora de despertar tiene que ser después de la de dormirte." : "Un sueño no puede pasar de 16 horas.")
                            .dsFont(13, .semibold).foregroundStyle(DSLevel.justa.ink).padding(.horizontal, 4)
                    }
                    if session != nil {
                        Button { confirmDelete = true } label: {
                            Text("Eliminar este sueño").dsFont(17).foregroundStyle(DSLevel.baja.ink)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(DS.fill.opacity(0.55), in: RoundedRectangle(cornerRadius: DS.radius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    }
                }
                .padding(.horizontal, DS.gutter)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.sheet.ignoresSafeArea())
        .confirmationDialog("¿Eliminar este sueño?", isPresented: $confirmDelete) {
            Button("Eliminar", role: .destructive) {
                if let s = session { model.deleteSleep(s) }
                dismiss()
            }
        }
        .onAppear(perform: load)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(DS.sheetRadius)
        .presentationBackground(DS.sheet)
        .preferredColorScheme(.dark)
    }

    private func load() {
        if let s = session {
            start = Date(timeIntervalSince1970: TimeInterval(s.start))
            end = Date(timeIntervalSince1970: TimeInterval(s.end))
        } else if let d = DayKey.date(forDay ?? model.selectedDay) {
            isNap = napDefault
            start = d.addingTimeInterval(napDefault ? 15 * 3600 : -60 * 60)
            end = d.addingTimeInterval(napDefault ? 15.5 * 3600 : 7 * 3600)
        }
        // Whole hours around the sleep: one before, one after (two around a short nap).
        let cal = Calendar.current
        let pad: TimeInterval = end.timeIntervalSince(start) < 3 * 3600 ? 2 * 3600 : 3600
        let a = cal.dateInterval(of: .hour, for: start.addingTimeInterval(-pad))?.start ?? start
        let b = (cal.dateInterval(of: .hour, for: end.addingTimeInterval(pad))?.end ?? end)
        span = a...b
    }

    private func timeRow(_ label: String, _ value: Binding<Date>) -> some View {
        HStack {
            Text(label).dsFont(17).foregroundStyle(DS.t1)
            Spacer()
            DatePicker(label, selection: value, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "es_ES"))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
    }

    /// The span as a track with the sleep in violet and a handle at each end (drag in 5-minute steps).
    private func ruler(_ span: ClosedRange<Date>) -> some View {
        let total = span.upperBound.timeIntervalSince(span.lowerBound)
        return VStack(spacing: 8) {
            GeometryReader { g in
                let w = g.size.width - 28
                let x = { (d: Date) in 14 + w * CGFloat(min(max(d.timeIntervalSince(span.lowerBound) / total, 0), 1)) }
                let date = { (px: CGFloat) -> Date in
                    let t = Double(min(max((px - 14) / w, 0), 1)) * total
                    let raw = span.lowerBound.addingTimeInterval(t).timeIntervalSince1970
                    return Date(timeIntervalSince1970: (raw / 300).rounded() * 300)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.bg).frame(height: 10).padding(.horizontal, 14)
                    Capsule().fill(DS.sueno).frame(width: max(0, x(end) - x(start)), height: 10).offset(x: x(start))
                    handle
                        .gesture(DragGesture(coordinateSpace: .named("ruler")).onChanged { v in
                            let d = date(v.location.x)
                            if d < end.addingTimeInterval(-600) { start = d }
                        })
                        .position(x: x(start), y: g.size.height / 2)
                    handle
                        .gesture(DragGesture(coordinateSpace: .named("ruler")).onChanged { v in
                            let d = date(v.location.x)
                            if d > start.addingTimeInterval(600) { end = d }
                        })
                        .position(x: x(end), y: g.size.height / 2)
                }
                .coordinateSpace(name: "ruler")
            }
            .frame(height: 34)
            GeometryReader { g in
                let w = g.size.width - 28
                ForEach(marks(span), id: \.self) { m in
                    Text(DSFmt.hour(Int(m.timeIntervalSince1970))).dsFont(13, .medium).foregroundStyle(DS.t3)
                        .fixedSize()
                        .position(x: 14 + w * CGFloat(m.timeIntervalSince(span.lowerBound) / total), y: 8)
                }
            }
            .frame(height: 16)
        }
        .accessibilityHidden(true)
    }

    private var handle: some View {
        Circle().fill(DS.t1).frame(width: 30, height: 30)
            .overlay(HStack(spacing: 3) { Capsule().frame(width: 2, height: 10); Capsule().frame(width: 2, height: 10) }.foregroundStyle(DS.bg))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .contentShape(Circle().inset(by: -10))
    }

    /// Even hours on the ruler.
    private func marks(_ span: ClosedRange<Date>) -> [Date] {
        var out: [Date] = []
        var t = span.lowerBound
        let cal = Calendar.current
        while t <= span.upperBound {
            if cal.component(.hour, from: t) % 2 == 0 { out.append(t) }
            t = t.addingTimeInterval(3600)
        }
        return out
    }
}
