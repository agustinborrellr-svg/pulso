import XCTest

/// Captures every screen of the app from top to bottom, one screenshot per scroll step, into SHOTS_DIR
/// (passed by CI as TEST_RUNNER_SHOTS_DIR). The frames of each screen are stitched into one long page afterwards.
final class PageCaptureTests: XCTestCase {
    /// Every screen the app can open in screenshot mode (`-PulsoScreen`), tabs first.
    static let screens = [
        "today", "health", "trends", "trendsList", "live", "more",
        "recovery", "sleep", "strain", "stress", "trendRecovery", "trendStrain", "trendHRV", "trendHRV6M",
        "vo2", "plan", "behaviors", "cycle", "pressure", "monitor", "calendar", "explorer", "monthly", "intelDetail", "whatif",
        "scan", "coherence", "poincare", "orthostatic", "workout",
        "alarms", "alarmEditor", "notifications", "integrations", "doubleTap", "storage", "device", "deviceAdvanced", "pairing",
        "ecg", "ecgDetail", "bedtime", "whoopImport", "addActivity", "sleepQuestion", "guide", "lab",
    ]

    var outDir: URL {
        let path = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() + "pulso-pages"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func launch(_ screen: String, readyFlag: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PulsoScreenshots", "YES", "-PulsoScreen", screen, "-AppleLanguages", "(es)", "-AppleLocale", "es_ES"]
        app.launchEnvironment["PULSO_READY_PATH"] = readyFlag.path
        app.launch()
        return app
    }

    func testCaptureAllPages() throws {
        let flag = outDir.appendingPathComponent("ready.flag")
        try? FileManager.default.removeItem(at: flag)
        // The first launch builds the demo data: wait for the app to say it's ready.
        var app = launch("today", readyFlag: flag)
        let deadline = Date().addingTimeInterval(400)
        while !FileManager.default.fileExists(atPath: flag.path) && Date() < deadline { sleep(2) }
        app.terminate()

        for (n, screen) in Self.screens.enumerated() {
            app = launch(screen, readyFlag: flag)
            sleep(5)
            var previous: Data?
            for step in 0..<14 {
                let png = XCUIScreen.main.screenshot().pngRepresentation
                if png == previous { break } // reached the bottom: nothing moved
                let name = String(format: "%02d-%@-%02d.png", n + 1, screen, step + 1)
                try png.write(to: outDir.appendingPathComponent(name))
                previous = png
                // A slow drag with a hold at the end scrolls a predictable amount, without momentum.
                let window = app.windows.firstMatch
                let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
                let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.4)
                sleep(1)
            }
            app.terminate()
        }
    }
}
