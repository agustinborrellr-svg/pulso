import XCTest
import WhoopProtocol
import PulsoStore
@testable import PulsoECG

final class ECGTests: XCTestCase {
    func testSinusRhythmDetected() {
        for hr in [55.0, 72.0, 90.0] {
            let sim = ECGSimulator(heartRate: hr, pattern: .sinus, seed: UInt64(hr))
            let a = ECGAnalyzer.analyze(samples: sim.generate(), rate: sim.rate)
            XCTAssertEqual(a.rhythm, .sinus, "HR \(hr): nRMSSD \(a.normalizedRMSSD ?? -1) TPR \(a.turningPointRatio ?? -1) q \(a.quality)")
            XCTAssertEqual(a.heartRate ?? 0, hr, accuracy: hr * 0.05)
            let expected = 30 * hr / 60
            XCTAssertEqual(Double(a.rPeaks.count), expected, accuracy: 3)
        }
    }

    func testRPeaksLandOnTheRWave() {
        var sim = ECGSimulator(heartRate: 60, pattern: .sinus)
        sim.noise = 0.005
        sim.sinusArrhythmia = 0
        let x = sim.generate()
        let a = ECGAnalyzer.analyze(samples: x, rate: sim.rate)
        // First beat is at 0.3 s, then ~every second.
        let first = Double(a.rPeaks[0]) / sim.rate
        XCTAssertEqual(first, 0.3, accuracy: 0.02)
        for p in a.rPeaks.prefix(10) {
            XCTAssertGreaterThan(x[p], 0.6, "peak sample should be on the tall R wave")
        }
    }

    func testBradyAndTachy() {
        let brady = ECGSimulator(heartRate: 44, pattern: .sinus, seed: 3)
        XCTAssertEqual(ECGAnalyzer.analyze(samples: brady.generate(), rate: brady.rate).rhythm, .lowHeartRate)
        let tachy = ECGSimulator(heartRate: 118, pattern: .sinus, seed: 4)
        XCTAssertEqual(ECGAnalyzer.analyze(samples: tachy.generate(), rate: tachy.rate).rhythm, .highHeartRate)
    }

    func testAtrialFibrillationLooksIrregular() {
        for seed in [1, 2, 3] as [UInt64] {
            let sim = ECGSimulator(heartRate: 85, pattern: .atrialFibrillation, seed: seed)
            let a = ECGAnalyzer.analyze(samples: sim.generate(), rate: sim.rate)
            XCTAssertEqual(a.rhythm, .irregular, "seed \(seed): nRMSSD \(a.normalizedRMSSD ?? -1) TPR \(a.turningPointRatio ?? -1)")
        }
        // Strong but smooth breathing-linked variation (young athlete) must not be called irregular.
        var rsa = ECGSimulator(heartRate: 58, pattern: .sinus, seed: 9)
        rsa.sinusArrhythmia = 0.12
        let r = ECGAnalyzer.analyze(samples: rsa.generate(), rate: rsa.rate)
        XCTAssertNotEqual(r.rhythm, .irregular, "nRMSSD \(r.normalizedRMSSD ?? -1) TPR \(r.turningPointRatio ?? -1)")
    }

    func testNoiseAndFlatlineAreInconclusive() {
        var lcg = ECGSimulator.LCG(seed: 5)
        let noise = (0..<(512 * 30)).map { _ in Float((lcg.next() - 0.5) * 0.6) }
        XCTAssertEqual(ECGAnalyzer.analyze(samples: noise, rate: 512).rhythm, .inconclusive)
        XCTAssertEqual(ECGAnalyzer.analyze(samples: [Float](repeating: 0, count: 512 * 30), rate: 512).rhythm, .inconclusive)
        XCTAssertEqual(ECGAnalyzer.analyze(samples: [0, 1, 2], rate: 512).rhythm, .inconclusive)
    }

    func testSessionBuilder() {
        let sim = ECGSimulator(heartRate: 70)
        let all = sim.generate()
        let b = ECGSessionBuilder(start: 1_790_000_000, sampleRate: sim.rate, targetSeconds: 30)
        var i = 0
        while i < all.count {
            b.append(Array(all[i..<min(all.count, i + 100)]))
            i += 100
        }
        b.append([1, 2, 3])
        XCTAssertTrue(b.isComplete)
        XCTAssertEqual(b.samples.count, Int(sim.rate * 30))
        let (rec, a) = b.finish(source: .simulated)
        XCTAssertEqual(rec.rhythm, Rhythm.sinus.rawValue)
        XCTAssertEqual(rec.avgHR ?? 0, 70, accuracy: 3)
        XCTAssertEqual(a.rhythm, .sinus)
    }

    func testMGDecoderIsInertUntilConfigured() throws {
        var d = MGECGDecoder()
        XCTAssertFalse(d.isConfigured)
        let raw = Framing.encode(.gen5, type: 43, seq: 1, cmd: 0, payload: [1, 0, 2, 0, 3, 0])
        let frame = try Framing.decode(.gen5, raw)
        XCTAssertTrue(d.decode(frame).isEmpty)
        // Once the layout is known it decodes signed 16-bit samples.
        d.sampleRate = 512
        d.packetType = 43
        d.firstSampleOffset = 3
        d.microvoltsPerLSB = 1000
        XCTAssertEqual(d.decode(frame).prefix(3), [1, 2, 3])
    }

    func testPDFReportIsValid() throws {
        let sim = ECGSimulator(heartRate: 66)
        var rec = sim.recording(start: 1_790_000_000)
        let a = ECGAnalyzer.analyze(rec)
        rec.rhythm = a.rhythm.rawValue
        let pdf = ECGReport.pdf(rec, analysis: a, info: .init(name: "Agustín", age: 32, deviceLabel: "Simulador"))
        let text = String(decoding: pdf, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("%PDF-1.4"))
        XCTAssertTrue(text.hasSuffix("%%EOF\n"))
        XCTAssertTrue(text.contains("/Type /Catalog"))
        XCTAssertTrue(text.contains("Ritmo sinusal"))
        XCTAssertTrue(text.contains("Agust\\355n"), "Latin-1 octal escape for í")
        // startxref points at the xref table.
        let startxref = text.range(of: "startxref\n")!
        let offset = Int(text[startxref.upperBound...].prefix { $0.isNumber })!
        XCTAssertEqual(String(decoding: pdf[offset..<(offset + 4)], as: UTF8.self), "xref")
        let dir = ProcessInfo.processInfo.environment["PULSO_ARTIFACTS"] ?? NSTemporaryDirectory()
        try Data(pdf).write(to: URL(fileURLWithPath: dir).appendingPathComponent("pulso-ecg-test.pdf"))
        XCTAssertEqual(ECGReport.pdfText("a(b)\\"), "(a\\(b\\)\\\\)")
    }
}
