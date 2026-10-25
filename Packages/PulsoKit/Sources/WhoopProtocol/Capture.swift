import Foundation

/// Ring buffer of raw notifications for the "Laboratorio" screen: lets a pilot strap record what it
/// sends (unknown packet types, ECG/IMU streams…) and export it as text for reverse engineering.
public final class FrameRecorder {
    public struct Entry: Equatable, Sendable {
        public var ts: Double
        public var channel: String
        public var bytes: [UInt8]
        public var note: String
    }

    public let capacity: Int
    public private(set) var entries: [Entry] = []
    /// Count of frames per packet-type byte (inner[0]).
    public private(set) var typeCounts: [UInt8: Int] = [:]
    /// When false only unknown / unhandled frames are kept.
    public var recordAll = false
    public var isRecording = false

    public init(capacity: Int = 20_000) {
        self.capacity = capacity
    }

    /// Records a reassembled frame. `handled` = the app understood it.
    public func record(_ frame: Frame, channel: String, handled: Bool, at ts: Double = Date().timeIntervalSince1970) {
        typeCounts[frame.typeByte, default: 0] += 1
        guard isRecording, recordAll || !handled else { return }
        append(Entry(ts: ts, channel: channel, bytes: frame.raw,
                     note: "type=\(frame.typeByte) seq=\(frame.seq) cmd=\(frame.cmd)\(frame.crcOK ? "" : " CRC!")"))
    }

    /// Records raw bytes that never formed a frame (e.g. standard characteristics).
    public func recordRaw(_ bytes: [UInt8], channel: String, at ts: Double = Date().timeIntervalSince1970) {
        guard isRecording, recordAll else { return }
        append(Entry(ts: ts, channel: channel, bytes: bytes, note: "raw"))
    }

    private func append(_ e: Entry) {
        entries.append(e)
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    public func clear() {
        entries.removeAll()
        typeCounts.removeAll()
    }

    /// One line per frame: `unix_ms channel hex # note`.
    public func export() -> String {
        var lines = ["# Pulso frame capture · \(entries.count) frames", "# unix_ms\tchannel\thex\tnote"]
        for e in entries {
            lines.append("\(Int64(e.ts * 1000))\t\(e.channel)\t\(Hex.encode(e.bytes))\t\(e.note)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
