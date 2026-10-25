import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snap: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snap: WidgetSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snap: WidgetSnapshot.load() ?? .placeholder)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

enum WTheme {
    static let bg = Color(red: 0.035, green: 0.043, blue: 0.055)
    static let green = Color(red: 0.16, green: 0.84, blue: 0.45)
    static let yellow = Color(red: 1.00, green: 0.78, blue: 0.18)
    static let red = Color(red: 1.00, green: 0.30, blue: 0.30)
    static let strain = Color(red: 0.24, green: 0.56, blue: 1.00)
    static let sleep = Color(red: 0.58, green: 0.50, blue: 1.00)

    static func recovery(_ v: Double?) -> Color {
        guard let v else { return .gray }
        return v >= 67 ? green : (v >= 34 ? yellow : red)
    }
}

struct Ring: View {
    let progress: Double
    let color: Color
    let value: String
    var label: String = ""
    var lineWidth: CGFloat = 6

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: lineWidth)
                Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value).font(.system(.headline, design: .rounded).weight(.bold)).monospacedDigit().minimumScaleFactor(0.6)
            }
            if !label.isEmpty { Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(color) }
        }
    }
}

// MARK: - Home / lock screen widget

struct DayWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapshotEntry

    var body: some View {
        let s = entry.snap
        switch family {
        case .accessoryCircular:
            Gauge(value: (s.recovery ?? 0) / 100) {
                Text("REC")
            } currentValueLabel: {
                Text(s.recovery.map { "\(Int($0))" } ?? "–")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Recuperación \(s.recovery.map { "\(Int($0)) %" } ?? "–")").font(.headline)
                Text("Esfuerzo \(s.strain.map { String(format: "%.1f", $0) } ?? "–")\(s.strainTarget.map { " / \($0)" } ?? "")")
                Text("Sueño \(s.sleepMinutes.map { "\(Int($0) / 60)h \(Int($0) % 60)m" } ?? "–")")
            }
            .font(.caption)
        case .accessoryInline:
            Text("Rec \(s.recovery.map { "\(Int($0))%" } ?? "–") · Esf \(s.strain.map { String(format: "%.1f", $0) } ?? "–")")
        case .systemMedium:
            HStack(spacing: 14) {
                Ring(progress: (s.recovery ?? 0) / 100, color: WTheme.recovery(s.recovery),
                     value: s.recovery.map { "\(Int($0))" } ?? "–", label: "RECUP.")
                Ring(progress: (s.strain ?? 0) / 21, color: WTheme.strain, value: s.strain.map { String(format: "%.1f", $0) } ?? "–",
                     label: "ESFUERZO")
                Ring(progress: s.sleepPerformance ?? 0, color: WTheme.sleep,
                     value: s.sleepPerformance.map { "\(Int(($0 * 100).rounded()))" } ?? "–", label: "SUEÑO")
                VStack(alignment: .leading, spacing: 4) {
                    if let h = s.headline { Text(h).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
                    if let t = s.strainTarget { Text("Objetivo \(t)").font(.caption2.bold()).foregroundStyle(WTheme.strain) }
                    if let a = s.nextAlarm { Label(a.formatted(date: .omitted, time: .shortened), systemImage: "alarm").font(.caption2) }
                }
            }
            .padding(4)
        default:
            VStack(spacing: 6) {
                Ring(progress: (s.recovery ?? 0) / 100, color: WTheme.recovery(s.recovery),
                     value: s.recovery.map { "\(Int($0))%" } ?? "–", lineWidth: 8)
                    .frame(width: 74, height: 74)
                HStack(spacing: 8) {
                    Label(s.strain.map { String(format: "%.1f", $0) } ?? "–", systemImage: "flame.fill").foregroundStyle(WTheme.strain)
                    Label(s.sleepPerformance.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", systemImage: "moon.fill").foregroundStyle(WTheme.sleep)
                }
                .font(.caption2.bold())
            }
        }
    }
}

struct DayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PulsoDay", provider: SnapshotProvider()) { entry in
            DayWidgetView(entry: entry)
                .containerBackground(WTheme.bg, for: .widget)
        }
        .configurationDisplayName("Pulso · Hoy")
        .description("Recuperación, esfuerzo y sueño.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Workout Live Activity

struct WorkoutLiveActivity: Widget {
    static func zoneColor(_ z: Int) -> Color {
        switch z {
        case 1: return Color(red: 0.55, green: 0.75, blue: 1.0)
        case 2: return Color(red: 0.25, green: 0.85, blue: 0.55)
        case 3: return Color(red: 1.0, green: 0.80, blue: 0.20)
        case 4: return Color(red: 1.0, green: 0.50, blue: 0.20)
        case 5: return Color(red: 1.0, green: 0.25, blue: 0.30)
        default: return .gray
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.attributes.symbol).font(.title2).foregroundStyle(WTheme.strain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.sport).font(.headline)
                    Text(context.attributes.start, style: .timer).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    if let step = context.state.step { Text(step).font(.caption).foregroundStyle(WTheme.yellow) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Label("\(context.state.heartRate)", systemImage: "heart.fill")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(Self.zoneColor(context.state.zone))
                    Text(String(format: "Esf. %.1f · %d kcal", context.state.strain, context.state.kcal)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(WTheme.bg)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.sport, systemImage: context.attributes.symbol).font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.start, style: .timer).font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("\(context.state.heartRate) lpm", systemImage: "heart.fill")
                            .foregroundStyle(Self.zoneColor(context.state.zone))
                        Spacer()
                        Text(String(format: "Esfuerzo %.1f", context.state.strain)).foregroundStyle(WTheme.strain)
                        Spacer()
                        if let step = context.state.step { Text(step).foregroundStyle(WTheme.yellow).lineLimit(1) }
                    }
                    .font(.subheadline.bold())
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundStyle(Self.zoneColor(context.state.zone))
            } compactTrailing: {
                Text("\(context.state.heartRate)").monospacedDigit()
            } minimal: {
                Text("\(context.state.heartRate)").monospacedDigit().foregroundStyle(Self.zoneColor(context.state.zone))
            }
        }
    }
}

@main
struct PulsoWidgetBundle: WidgetBundle {
    var body: some Widget {
        DayWidget()
        WorkoutLiveActivity()
    }
}
