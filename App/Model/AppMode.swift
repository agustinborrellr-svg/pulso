import Foundation

/// Launch modes used by the CI screenshot run (`-PulsoScreenshots YES -PulsoScreen <name>`).
enum AppMode {
    /// Simulator screenshots: demo data, no Bluetooth, no permission prompts, no onboarding.
    static let screenshots = ProcessInfo.processInfo.arguments.contains("-PulsoScreenshots")

    /// Screen to open on launch in screenshot mode.
    static var screen: String? { UserDefaults.standard.string(forKey: "PulsoScreen") }

    /// File written when the demo data is ready (the CI script waits for it).
    static var readyFlagURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("screenshots-ready")
    }
}
