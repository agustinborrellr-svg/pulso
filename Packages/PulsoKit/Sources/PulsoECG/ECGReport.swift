import Foundation
import PulsoStore

/// One-page A4 PDF of an ECG on standard paper (25 mm/s, 10 mm/mV) — what a doctor expects to see.
/// Pure Swift (no UIKit), so it is generated and tested anywhere.
public enum ECGReport {
    static let mm = 72.0 / 25.4
    static let pageW = 842.0, pageH = 595.0 // A4 landscape

    /// PDF string literal in WinAnsi (Latin-1 for Spanish), escaping specials.
    static func pdfText(_ s: String) -> String {
        var out = "("
        for scalar in s.unicodeScalars {
            let v = scalar.value
            switch v {
            case 0x28: out += "\\("
            case 0x29: out += "\\)"
            case 0x5C: out += "\\\\"
            case 0x20...0x7E: out.unicodeScalars.append(scalar)
            case 0xA0...0xFF: out += String(format: "\\%03o", v)
            case 0x2013, 0x2014: out += "-"
            case 0x2082: out += "2"   // subscript two (SpO₂)
            case 0x2264: out += "<="
            case 0x2265: out += ">="
            case 0x2022, 0x00B7: out += String(format: "\\%03o", 0xB7)
            default: out += "?"
            }
        }
        return out + ")"
    }

    static func f(_ v: Double) -> String { String(format: "%.2f", v) }

    public struct Info {
        public var name: String
        public var age: Int?
        public var deviceLabel: String

        public init(name: String, age: Int?, deviceLabel: String) {
            self.name = name
            self.age = age
            self.deviceLabel = deviceLabel
        }
    }

    public static func pdf(_ rec: ECGRecording, analysis: ECGAnalysis, info: Info) -> [UInt8] {
        var c = ""
        let left = 18 * mm, rowW = 250 * mm // 10 s per row at 25 mm/s
        let rowH = 36 * mm, top = pageH - 40 * mm
        let rows = 3
        let secondsPerRow = 10.0

        // Header text.
        let date: String = {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "es_ES")
            fmt.dateFormat = "d 'de' MMMM 'de' yyyy, HH:mm"
            return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(rec.start)))
        }()
        func text(_ s: String, _ x: Double, _ y: Double, size: Double, bold: Bool = false) {
            c += "BT /\(bold ? "F2" : "F1") \(f(size)) Tf \(f(x)) \(f(y)) Td \(pdfText(s)) Tj ET\n"
        }
        c += "0 0 0 rg\n"
        text("ECG de una derivación - \(analysis.rhythm.title)", left, pageH - 16 * mm, size: 15, bold: true)
        var who = info.name.isEmpty ? "" : info.name
        if let a = info.age { who += (who.isEmpty ? "" : " · ") + "\(a) años" }
        let hrText = analysis.heartRate.map { "\(Int($0.rounded())) lpm de media" } ?? "frecuencia no disponible"
        text([who, date, hrText].filter { !$0.isEmpty }.joined(separator: "   ·   "), left, pageH - 23 * mm, size: 9.5)
        text("\(info.deviceLabel) · derivación I · 25 mm/s · 10 mm/mV · \(Int(rec.sampleRate)) Hz", left, pageH - 28 * mm, size: 8.5)

        // Grid + traces.
        let samplesPerRow = Int(rec.sampleRate * secondsPerRow)
        let filtered = ECGAnalyzer.filter(rec.samples, rate: rec.sampleRate)
        for r in 0..<rows {
            let y0 = top - Double(r) * (rowH + 4 * mm) - rowH // bottom of the row
            // minor grid
            c += "1 0.85 0.85 RG 0.25 w\n"
            var k = 0.0
            while k <= 250.001 { c += "\(f(left + k * mm)) \(f(y0)) m \(f(left + k * mm)) \(f(y0 + rowH)) l\n"; k += 1 }
            k = 0
            while k <= 36.001 { c += "\(f(left)) \(f(y0 + k * mm)) m \(f(left + rowW)) \(f(y0 + k * mm)) l\n"; k += 1 }
            c += "S\n1 0.6 0.6 RG 0.6 w\n"
            k = 0
            while k <= 250.001 { c += "\(f(left + k * mm)) \(f(y0)) m \(f(left + k * mm)) \(f(y0 + rowH)) l\n"; k += 5 }
            k = 0
            while k <= 36.001 { c += "\(f(left)) \(f(y0 + k * mm)) m \(f(left + rowW)) \(f(y0 + k * mm)) l\n"; k += 5 }
            c += "S\n"
            // 1 mV calibration pulse at the start of the row.
            let mid = y0 + rowH / 2
            c += "0 0 0 RG 0.8 w \(f(left - 6 * mm)) \(f(mid)) m \(f(left - 5 * mm)) \(f(mid)) l \(f(left - 5 * mm)) \(f(mid + 10 * mm)) l \(f(left - 2 * mm)) \(f(mid + 10 * mm)) l \(f(left - 2 * mm)) \(f(mid)) l \(f(left - 1 * mm)) \(f(mid)) l S\n"
            // Trace.
            let a = r * samplesPerRow, b = min(filtered.count, a + samplesPerRow)
            guard a < b else { continue }
            c += "0 0 0 RG 0.7 w 1 j\n"
            let step = max(1, Int(rec.sampleRate / 250)) // ≤ 250 points per second is plenty on paper
            var first = true
            var i = a
            while i < b {
                let x = left + Double(i - a) / rec.sampleRate * 25 * mm
                let mv = max(-1.7, min(1.7, filtered[i]))
                let y = mid + mv * 10 * mm
                c += "\(f(x)) \(f(y)) \(first ? "m" : "l")\n"
                first = false
                i += step
            }
            c += "S\n"
            text(String(format: "%.0f-%.0f s", Double(r) * secondsPerRow, Double(r + 1) * secondsPerRow), left + rowW - 18 * mm, y0 + rowH + 1.2 * mm, size: 7)
        }

        // Footer: explanation + disclaimer.
        c += "0 0 0 rg\n"
        var y = 22 * mm
        for line in wrap(analysis.rhythm.explanation, width: 150) {
            text(line, left, y, size: 8.5)
            y -= 3.8 * mm
        }
        y -= 1 * mm
        for line in wrap(Rhythm.disclaimer, width: 150) {
            text(line, left, y, size: 7.5, bold: true)
            y -= 3.4 * mm
        }

        return assemble(content: c)
    }

    static func wrap(_ s: String, width: Int) -> [String] {
        var lines: [String] = []
        var cur = ""
        for word in s.split(separator: " ") {
            if cur.count + word.count + 1 > width, !cur.isEmpty {
                lines.append(cur)
                cur = String(word)
            } else {
                cur += (cur.isEmpty ? "" : " ") + word
            }
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    /// Minimal valid PDF: catalog, pages, one page, its content stream and two base-14 fonts.
    static func assemble(content: String) -> [UInt8] {
        let stream = Array(content.utf8)
        var objects: [[UInt8]] = []
        objects.append(Array("<< /Type /Catalog /Pages 2 0 R >>".utf8))
        objects.append(Array("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8))
        objects.append(Array("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(Int(pageW)) \(Int(pageH))] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 4 0 R >>".utf8))
        objects.append(Array("<< /Length \(stream.count) >>\nstream\n".utf8) + stream + Array("\nendstream".utf8))
        objects.append(Array("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>".utf8))
        objects.append(Array("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>".utf8))

        var out = Array("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        for (i, o) in objects.enumerated() {
            offsets.append(out.count)
            out += Array("\(i + 1) 0 obj\n".utf8) + o + Array("\nendobj\n".utf8)
        }
        let xref = out.count
        var x = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for off in offsets { x += String(format: "%010d 00000 n \n", off) }
        x += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        out += Array(x.utf8)
        return out
    }
}
