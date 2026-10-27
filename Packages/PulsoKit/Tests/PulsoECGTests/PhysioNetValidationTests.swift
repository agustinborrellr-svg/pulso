import XCTest
@testable import PulsoECG

/// Validation on real single-lead ECGs (PhysioNet/CinC Challenge 2017, 300 Hz, labelled by cardiologists).
/// Runs only when PULSO_ECG_DIR points at a folder of `N_*.txt` (normal) and `A_*.txt` (atrial
/// fibrillation) files with one mV value per line; the recordings are not part of the repository.
final class PhysioNetValidationTests: XCTestCase {
    func testAtrialFibrillationDetectionOnRealECGs() throws {
        guard let dir = ProcessInfo.processInfo.environment["PULSO_ECG_DIR"] else { throw XCTSkip("PULSO_ECG_DIR not set") }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".txt") }.sorted()
        var counts: [String: [Rhythm: Int]] = ["N": [:], "A": [:]]
        for name in files {
            let label = String(name.prefix(1))
            guard counts[label] != nil else { continue }
            let text = try String(contentsOfFile: dir + "/" + name, encoding: .utf8)
            let samples = text.split(separator: "\n").compactMap { Float($0) }
            let a = ECGAnalyzer.analyze(samples: samples, rate: 300)
            counts[label]![a.rhythm, default: 0] += 1
        }
        func total(_ l: String) -> Int { counts[l]!.values.reduce(0, +) }
        func n(_ l: String, _ r: Rhythm) -> Int { counts[l]![r] ?? 0 }
        let afReadable = total("A") - n("A", .inconclusive)
        let nReadable = total("N") - n("N", .inconclusive)
        let sensitivity = Double(n("A", .irregular)) / Double(max(1, afReadable))
        let specificity = Double(nReadable - n("N", .irregular)) / Double(max(1, nReadable))
        print("ECG PhysioNet: FA \(counts["A"]!.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
        print("ECG PhysioNet: normal \(counts["N"]!.map { "\($0.key.rawValue)=\($0.value)" }.sorted())")
        print(String(format: "ECG PhysioNet: sensibilidad FA %.0f %%, especificidad %.0f %%, no concluyentes FA %d/%d, normal %d/%d",
                     sensitivity * 100, specificity * 100, n("A", .inconclusive), total("A"), n("N", .inconclusive), total("N")))
        XCTAssertGreaterThan(total("A"), 20)
        XCTAssertGreaterThan(sensitivity, 0.75, "atrial fibrillation must be caught")
        XCTAssertGreaterThan(specificity, 0.90, "a normal rhythm must rarely read as irregular")
        XCTAssertLessThan(Double(n("N", .inconclusive)) / Double(total("N")), 0.25, "most clean recordings give an answer")
    }
}
