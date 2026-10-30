import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// nil = no real data (App Group missing or the app hasn't written yet): the widget says so.
    let snap: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    /// Gallery / redacted preview only: sample numbers are fine here, never at runtime.
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotEntry(date: Date(), snap: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let real = WidgetSnapshot.load()
        completion(SnapshotEntry(date: Date(), snap: real ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snap: WidgetSnapshot.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

/// Widget colours: the app's palette (`PulsoPalette`), so a recovery green is the same everywhere.
enum WTheme {
    static let bg = PulsoPalette.background
    static let green = PulsoPalette.recoveryHigh
    static let yellow = PulsoPalette.recoveryMid
    static let red = PulsoPalette.recoveryLow
    static let strain = PulsoPalette.strain
    static let sleep = PulsoPalette.sleep
    static let secondary = PulsoPalette.secondary

    static func recovery(_ v: Double?) -> Color { PulsoPalette.recovery(v) }
}

/// Honest empty state: no sample numbers dressed up as yours.
struct NoDataWidgetView: View {
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform.path.ecg")
            }
            .accessibilityLabel("Abre Pulso para ver tus datos")
        case .accessoryInline:
            Text("Abre Pulso para ver tus datos")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("Pulso", systemImage: "waveform.path.ecg").font(.headline)
                Text("Abre Pulso para ver tus datos").font(.caption)
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "waveform.path.ecg").font(.title3.weight(.semibold)).foregroundStyle(WTheme.red)
                Spacer(minLength: 0)
                Text("Sin datos todavía").font(.headline).foregroundStyle(.white)
                Text("Abre Pulso para ver tus datos").font(.caption).foregroundStyle(WTheme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
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
            if !label.isEmpty {
                Text(label).font(.caption2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(color)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? "Recuperación" : label)
        .accessibilityValue(value)
    }
}

// MARK: - Home / lock screen widget

struct DayWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: SnapshotEntry

    var body: some View {
        if let s = entry.snap { content(s) } else { NoDataWidgetView() }
    }

    /// "Datos de ayer" when the snapshot is from an earlier day.
    private func staleNote(_ s: WidgetSnapshot) -> String? {
        let age = entry.date.timeIntervalSince(s.updated)
        guard age > 12 * 3600 else { return nil }
        return "Actualizado " + s.updated.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    @ViewBuilder
    private func content(_ s: WidgetSnapshot) -> some View {
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
                    if let note = staleNote(s) { Text(note).font(.caption2.bold()).foregroundStyle(WTheme.yellow).lineLimit(2) }
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
                if let note = staleNote(s) { Text(note).font(.caption2).foregroundStyle(WTheme.yellow).lineLimit(1).minimumScaleFactor(0.8) }
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
    static func zoneColor(_ z: Int) -> Color { PulsoPalette.zone(z) }

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
