import Foundation
import WhoopProtocol
import PulsoStore

/// Turns strap frames into ECG voltage samples. The WHOOP MG's ECG stream has not been publicly
/// documented yet, so the MG decoder is a clearly-marked hook: it recognises nothing until the
/// layout is known (see docs/ECG.md for how to capture frames with the Laboratorio tools and fill it in).
public protocol ECGFrameDecoder {
    var sampleRate: Double { get }
    /// Voltage samples (mV) carried by this frame, or [] if it isn't an ECG frame.
    mutating func decode(_ frame: Frame) -> [Float]
}

public struct MGECGDecoder: ECGFrameDecoder {
    /// Expected once documented; 0 means "unknown" and keeps the feature disabled.
    public var sampleRate: Double = 0
    /// Packet type that carries the ECG stream (candidates seen on gen5: 43 REALTIME_RAW_DATA).
    public var packetType: UInt8? = nil
    /// Byte offset of the first sample and sample width/scale, to be filled from captures.
    public var firstSampleOffset = 0
    public var bytesPerSample = 2
    public var microvoltsPerLSB: Double = 1

    public init() {}

    public var isConfigured: Bool { sampleRate > 0 && packetType != nil }

    public mutating func decode(_ frame: Frame) -> [Float] {
        guard isConfigured, frame.typeByte == packetType else { return [] }
        let b = frame.inner
        var out: [Float] = []
        var i = firstSampleOffset
        while i + bytesPerSample <= b.count {
            let raw: Int
            if bytesPerSample == 3 {
                var v = Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16
                if v & 0x800000 != 0 { v -= 0x1000000 }
                raw = v
            } else {
                raw = Int(LE.i16(b, i) ?? 0)
            }
            out.append(Float(Double(raw) * microvoltsPerLSB / 1000))
            i += bytesPerSample
        }
        return out
    }
}

/// Accumulates samples during a recording and produces the stored recording + analysis.
public final class ECGSessionBuilder {
    public let start: Int
    public let sampleRate: Double
    public let target: Double
    public private(set) var samples: [Float] = []

    public init(start: Int, sampleRate: Double, targetSeconds: Double = 30) {
        self.start = start
        self.sampleRate = sampleRate
        self.target = targetSeconds
    }

    public var seconds: Double { sampleRate > 0 ? Double(samples.count) / sampleRate : 0 }
    public var progress: Double { min(1, seconds / target) }
    public var isComplete: Bool { seconds >= target }

    public func append(_ s: [Float]) {
        guard !isComplete else { return }
        samples += s
        let cap = Int(sampleRate * target)
        if samples.count > cap { samples.removeLast(samples.count - cap) }
    }

    public func finish(source: ECGSource) -> (ECGRecording, ECGAnalysis) {
        var rec = ECGRecording(start: start, sampleRate: sampleRate, samples: samples, source: source)
        let a = ECGAnalyzer.analyze(rec)
        rec.rhythm = a.rhythm.rawValue
        rec.avgHR = a.heartRate
        return (rec, a)
    }
}
