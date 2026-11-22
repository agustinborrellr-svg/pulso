import SwiftUI
import Charts
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntelligence

/// Cards from the first home screen that other screens still use.

/// "Why is my recovery X?" — every contributor with its signed impact.
struct RecoveryBreakdown: View {
    let day: DaySummary

    var body: some View {
        if !day.contributors.isEmpty {
            Card {
                SectionTitle(title: "Por qué", subtitle: day.calibrating ? "Calibrando tus líneas base (4 noches)" : "Comparado con tus últimas 2–4 semanas")
                ForEach(day.contributors) { c in
                    HStack {
                        Text(c.label).font(.subheadline).foregroundStyle(.white)
                        Spacer()
                        Text(valueText(c)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondary)
                        ImpactBar(impact: c.impact).frame(width: 70, height: 8)
                    }
                }
            }
        }
    }

    private func valueText(_ c: Contributor) -> String {
        let v = c.value.map { c.unit == "°C" ? String(format: "%+.2f", $0) : String(format: "%.0f", $0) } ?? "–"
        if let b = c.baseline, c.unit != "°C" {
            return "\(v) / \(String(format: "%.0f", b)) \(c.unit)"
        }
        return "\(v) \(c.unit)"
    }
}

struct ImpactBar: View {
    let impact: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / 2
            let len = min(w, CGFloat(abs(impact)) * w / 1.2)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1).offset(x: w)
                Capsule()
                    .fill(impact >= 0 ? Theme.green : Theme.red)
                    .frame(width: max(2, len))
                    .offset(x: impact >= 0 ? w : w - len)
            }
        }
    }
}

struct JournalCard: View {
    @EnvironmentObject var model: AppModel
    let day: String
    @State private var expanded = false

    var body: some View {
        let entries = model.journal(for: day)
        Card {
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack {
                    SectionTitle(title: "Diario", subtitle: entries.isEmpty ? "¿Qué hiciste hoy? Aprende qué te afecta" : "\(entries.count) registrados")
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(Theme.secondary)
                }
            }
            .buttonStyle(.plain)
            if expanded {
                FlowChips(day: day, entries: entries)
            }
        }
    }
}

struct FlowChips: View {
    @EnvironmentObject var model: AppModel
    let day: String
    let entries: [String: Double]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(JournalCatalog.items) { item in
                let on = (entries[item.key] ?? 0) > 0
                Button {
                    model.setJournal(day: day, key: item.key, on: !on)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                        Text(item.label).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .foregroundStyle(on ? Color.black : Color.white)
                    .background(on ? Theme.green : Theme.cardHighlight, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Tonight's alarm, and big snooze / stop buttons while it rings.
struct AlarmBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let status = model.alarmStatus {
            Card(padding: 14) {
                HStack(spacing: 10) {
                    Image(systemName: model.alarmRinging ? "alarm.waves.left.and.right.fill" : "alarm")
                        .font(.title3)
                        .foregroundStyle(model.alarmRinging ? Theme.yellow : Theme.sleep)
                        .symbolEffect(.pulse, isActive: model.alarmRinging)
                    Text(status).font(.footnote).foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                if model.alarmRinging {
                    HStack {
                        Button {
                            model.alarmSnooze()
                        } label: {
                            Label("Posponer", systemImage: "zzz").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            model.alarmStop()
                        } label: {
                            Label("Apagar", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.green)
                    }
                }
            }
        }
    }
}
