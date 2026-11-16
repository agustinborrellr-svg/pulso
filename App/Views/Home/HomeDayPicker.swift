import SwiftUI
import PulsoStore
import PulsoAnalytics

/// Inicio's calendar: tap the date and the month drops down with each day's number in its recovery colour; tapping a
/// day shows Inicio for that day, so you don't have to walk there with the arrows.
struct HomeDayPicker: View {
    @EnvironmentObject var model: AppModel
    @State private var month = ""
    @State private var forward = true

    private static let weekdays = ["LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB", "DOM"]

    private var currentMonth: String { String(model.currentDayKey.prefix(7)) }
    private var firstMonth: String { model.days.map(\.day).min().map { String($0.prefix(7)) } ?? currentMonth }
    private var canGoBack: Bool { month > firstMonth }
    private var canGoForward: Bool { month < currentMonth }

    var body: some View {
        VStack(spacing: 18) {
            header
            weekdayRow
            grid
            legend
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.card.ignoresSafeArea(edges: .top))
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
        return f.string(from: d).uppercased()
    }

    private var header: some View {
        HStack {
            Button { go(-1) } label: {
                Image(systemName: "chevron.left").font(.title2.weight(.medium)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!canGoBack)
            .opacity(canGoBack ? 1 : 0.3)
            .accessibilityLabel("Mes anterior")
            Spacer()
            Caps(title(month), size: 14, color: .white, weight: .bold)
                .id(month)
                .transition(.opacity)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { go(1) } label: {
                Image(systemName: "chevron.right").font(.title2.weight(.medium)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1 : 0.3)
            .accessibilityLabel("Mes siguiente")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdays, id: \.self) { d in
                Text(d).scaledFont(12, weight: .semibold, relativeTo: .caption2)
                    .foregroundStyle(Theme.secondary)
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
                    Color.clear.frame(height: 46).accessibilityHidden(true)
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

    static func color(_ recovery: Double) -> Color {
        recovery >= 67 ? Theme.green : (recovery >= 34 ? Theme.yellow : Theme.red)
    }

    private func cell(_ key: String, _ byDay: [String: DaySummary]) -> some View {
        let recovery = byDay[key].flatMap { TrendMetric.recovery.value($0) }
        let future = key > model.currentDayKey
        let selected = key == model.selectedDay
        let hasDay = byDay[key] != nil
        let color: Color = recovery.map(Self.color) ?? (future ? Theme.tertiary.opacity(0.6) : (hasDay ? .white : Theme.tertiary))
        return Button {
            model.selectDay(key)
            close()
        } label: {
            Text("\(Int(key.suffix(2)) ?? 0)")
                .scaledFont(17, weight: .bold, relativeTo: .body)
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background {
                    if selected {
                        Circle().fill(Color.black.opacity(0.35))
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.9), lineWidth: 2))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(Fmt.dayTitle(key) + (key == model.currentDayKey ? ", hoy" : ""))
        .accessibilityValue(future ? "futuro" : (recovery.map { "Recuperación \(Int($0.rounded())) %" } ?? "sin recuperación"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var legend: some View {
        HStack(spacing: 10) {
            Spacer()
            item("<34 %", Theme.red)
            item("34 % - 66 %", Theme.yellow)
            item(">66 %", Theme.green)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recuperación: rojo menos de 34 %, amarillo de 34 a 66 %, verde más de 66 %")
    }

    private func item(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).scaledFont(14, weight: .semibold, relativeTo: .footnote).foregroundStyle(color)
        }
    }
}
