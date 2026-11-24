import SwiftUI
import PulsoStore
import PulsoAnalytics

/// Inicio's calendar: tap the date and the month drops down with each day's number in its recovery colour; tapping a
/// day shows Inicio for that day, so you don't have to walk there with the arrows.
struct HomeDayPicker: View {
    @EnvironmentObject var model: AppModel
    @State private var month = ""
    @State private var forward = true

    private static let weekdays = ["L", "M", "X", "J", "V", "S", "D"]

    private var currentMonth: String { String(model.currentDayKey.prefix(7)) }
    private var firstMonth: String { model.days.map(\.day).min().map { String($0.prefix(7)) } ?? currentMonth }
    private var canGoBack: Bool { month > firstMonth }
    private var canGoForward: Bool { month < currentMonth }

    var body: some View {
        VStack(spacing: 14) {
            HoyHeader().padding(.horizontal, 4)
            header
            weekdayRow
            grid
            DSDivider()
            legend
            Capsule().fill(DS.fill2).frame(width: 40, height: 5).padding(.top, 2)
        }
        .padding(.horizontal, DS.gutter)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: DS.sheetRadius, bottomTrailingRadius: DS.sheetRadius, style: .continuous)
                .fill(DS.card).ignoresSafeArea(edges: .top)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24).onEnded { g in
                if abs(g.translation.width) > abs(g.translation.height), abs(g.translation.width) > 50 {
                    go(g.translation.width < 0 ? 1 : -1)
                } else if g.translation.height < -50 {
                    close()
                }
            }
        )
        .onAppear { if month.isEmpty { month = String(model.selectedDay.prefix(7)) } }
    }

    private func close() {
        withAnimation(.easeInOut(duration: 0.28)) { model.showDayPicker = false }
    }

    private func go(_ by: Int) {
        guard by < 0 ? canGoBack : canGoForward else { return }
        forward = by > 0
        withAnimation(.easeInOut(duration: 0.3)) { month = MonthlyReport.shiftMonth(month, by) }
    }

    private func title(_ m: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: m) else { return m }
        // The year only when it isn't this one.
        f.dateFormat = m.prefix(4) == currentMonth.prefix(4) ? "LLLL" : "LLLL yyyy"
        let t = f.string(from: d)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private var header: some View {
        HStack {
            monthButton("chevron.left", enabled: canGoBack, label: "Mes anterior") { go(-1) }
            Spacer()
            Text(title(month)).dsFont(22, .semibold, relativeTo: .title2).foregroundStyle(DS.t1)
                .id(month)
                .transition(.opacity)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            monthButton("chevron.right", enabled: canGoForward, label: "Mes siguiente") { go(1) }
        }
    }

    private func monthButton(_ icon: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? DS.t1 : DS.t3)
                .frame(width: 40, height: 40)
                .background(DS.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdays, id: \.self) { d in
                Text(d).dsFont(13, .medium, relativeTo: .caption1)
                    .foregroundStyle(DS.t2)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        let layout = CalendarMonth.layout(month)
        let keys = CalendarMonth.dayKeys(month)
        let byDay = Dictionary(model.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
            ForEach(0..<(layout.leading + keys.count), id: \.self) { i in
                if i < layout.leading {
                    Color.clear.frame(height: 52).accessibilityHidden(true)
                } else {
                    cell(keys[i - layout.leading], byDay)
                }
            }
        }
        .id(month)
        .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        .clipped()
    }

    private func cell(_ key: String, _ byDay: [String: DaySummary]) -> some View {
        let recovery = byDay[key].flatMap { TrendMetric.recovery.value($0) }
        let future = key > model.currentDayKey
        let selected = key == model.selectedDay
        let level = recovery.map(DSLevel.init(score:))
        let color: Color = level?.ink ?? (future ? DS.t3.opacity(0.6) : DS.t3)
        return Button {
            model.selectDay(key)
            close()
        } label: {
            VStack(spacing: 3) {
                Text("\(Int(key.suffix(2)) ?? 0)")
                    .dsFont(20, .semibold, relativeTo: .body)
                    .foregroundStyle(color)
                Circle().fill(level?.mark ?? .clear).frame(width: 5, height: 5)
            }
            .frame(width: 44, height: 46)
            .background {
                if selected {
                    Circle().strokeBorder(level?.mark ?? DS.t2, lineWidth: 2).frame(width: 42, height: 42).offset(y: -3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(Fmt.dayTitle(key) + (key == model.currentDayKey ? ", hoy" : ""))
        .accessibilityValue(future ? "futuro" : (recovery.map { "Recarga \(Int($0.rounded())), \(DSLevel(score: $0).word)" } ?? "sin Recarga"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Text("Recarga").foregroundStyle(DS.t2)
            ForEach(DSLevel.allCases, id: \.self) { l in
                HStack(spacing: 5) {
                    Circle().fill(l.mark).frame(width: 7, height: 7)
                    Text(l.word).foregroundStyle(DS.t1)
                }
            }
        }
        .dsFont(14, .medium, relativeTo: .footnote)
        .lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recarga por colores: baja, justa, buena y excelente")
    }
}
