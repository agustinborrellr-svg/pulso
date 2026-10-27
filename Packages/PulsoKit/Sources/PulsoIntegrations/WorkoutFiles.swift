import Foundation
import PulsoStore

/// A workout plus its heart-rate track, ready to export.
public struct WorkoutTrack: Equatable, Sendable {
    public var workout: Workout
    /// (unix seconds, bpm), sorted.
    public var heartRate: [(ts: Int, bpm: Int)]
    /// Lap boundaries (unix seconds) inside the workout.
    public var laps: [Int]

    public init(workout: Workout, heartRate: [(ts: Int, bpm: Int)], laps: [Int] = []) {
        self.workout = workout
        self.heartRate = heartRate.sorted { $0.ts < $1.ts }
        self.laps = laps.filter { $0 > workout.start && $0 < workout.end }.sorted()
    }

    public static func == (a: WorkoutTrack, b: WorkoutTrack) -> Bool {
        a.workout == b.workout && a.laps == b.laps && a.heartRate.map { $0.ts } == b.heartRate.map { $0.ts }
            && a.heartRate.map { $0.bpm } == b.heartRate.map { $0.bpm }
    }

    /// Builds the track from stored seconds (and live HR, which fills gaps when the history wasn't synced yet).
    public static func from(workout: Workout, samples: [Sample], live: [(ts: Int, hr: Int)] = [], laps: [Int] = []) -> WorkoutTrack {
        var byTs: [Int: Int] = [:]
        for l in live where l.ts >= workout.start && l.ts < workout.end && l.hr > 25 { byTs[l.ts] = l.hr }
        for s in samples where s.ts >= workout.start && s.ts < workout.end && s.worn {
            if let hr = s.hr { byTs[s.ts] = hr }
        }
        return WorkoutTrack(workout: workout, heartRate: byTs.map { (ts: $0.key, bpm: $0.value) }, laps: laps)
    }

    struct LapStats {
        var start: Int
        var end: Int
        var avg: Int?
        var max: Int?
    }

    func lapStats() -> [LapStats] {
        let bounds = [workout.start] + laps + [workout.end]
        return (0..<(bounds.count - 1)).map { i in
            let a = bounds[i], b = bounds[i + 1]
            let hrs = heartRate.filter { $0.ts >= a && $0.ts < b }.map { $0.bpm }
            return LapStats(start: a, end: b, avg: hrs.isEmpty ? nil : hrs.reduce(0, +) / hrs.count, max: hrs.max())
        }
    }
}

// MARK: - FIT

/// Garmin FIT activity file writer (the format Strava, Garmin Connect, TrainingPeaks and
/// Intervals.icu import best). Writes file_id, timer events, one record per second of heart rate,
/// laps, a session and the activity summary.
public enum FITEncoder {
    /// FIT epoch: 1989-12-31 00:00:00 UTC.
    static let epochOffset = 631_065_600

    static let crcTable: [UInt16] = [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
                                     0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]

    public static func crc(_ data: [UInt8], start: UInt16 = 0) -> UInt16 {
        var crc = start
        for byte in data {
            var tmp = crcTable[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ crcTable[Int(byte & 0xF)]
            tmp = crcTable[Int(crc & 0xF)]
            crc = (crc >> 4) & 0x0FFF
            crc = crc ^ tmp ^ crcTable[Int((byte >> 4) & 0xF)]
        }
        return crc
    }

    enum Base: UInt8 {
        case enumT = 0x00, uint8 = 0x02, uint16 = 0x84, uint32 = 0x86, uint32z = 0x8C

        var size: UInt8 {
            switch self {
            case .enumT, .uint8: return 1
            case .uint16: return 2
            case .uint32, .uint32z: return 4
            }
        }
    }

    struct Field {
        var num: UInt8
        var base: Base
    }

    struct Writer {
        var bytes: [UInt8] = []

        mutating func define(local: UInt8, global: UInt16, _ fields: [Field]) {
            bytes.append(0x40 | (local & 0x0F))
            bytes += [0, 0] // reserved, little-endian
            bytes += [UInt8(global & 0xFF), UInt8(global >> 8)]
            bytes.append(UInt8(fields.count))
            for f in fields { bytes += [f.num, f.base.size, f.base.rawValue] }
        }

        mutating func data(local: UInt8, _ fields: [Field], _ values: [UInt64]) {
            bytes.append(local & 0x0F)
            for (f, v) in zip(fields, values) {
                for i in 0..<Int(f.base.size) { bytes.append(UInt8(truncatingIfNeeded: v >> (8 * UInt64(i)))) }
            }
        }
    }

    static func fitTime(_ unix: Int) -> UInt64 { UInt64(max(0, unix - epochOffset)) }

    /// Invalid markers per base type (fields we don't know are written as "invalid").
    static let invalid8: UInt64 = 0xFF, invalid16: UInt64 = 0xFFFF

    public static func encode(_ track: WorkoutTrack, serial: UInt32 = 0x50554C53) -> [UInt8] {
        let w = track.workout
        let sport = SportCatalog.named(w.sport)
        let elapsedMs = UInt64(max(0, w.end - w.start)) * 1000
        var out = Writer()

        // file_id
        let fileID = [Field(num: 0, base: .enumT), Field(num: 1, base: .uint16), Field(num: 2, base: .uint16),
                      Field(num: 3, base: .uint32z), Field(num: 4, base: .uint32)]
        out.define(local: 0, global: 0, fileID)
        out.data(local: 0, fileID, [4, 255, 1, UInt64(serial), fitTime(w.start)])

        // event (timer start / stop_all)
        let event = [Field(num: 253, base: .uint32), Field(num: 0, base: .enumT), Field(num: 1, base: .enumT)]
        out.define(local: 1, global: 21, event)
        out.data(local: 1, event, [fitTime(w.start), 0, 0])

        // records
        let record = [Field(num: 253, base: .uint32), Field(num: 3, base: .uint8)]
        out.define(local: 2, global: 20, record)
        for p in track.heartRate where p.bpm > 0 && p.bpm < 255 {
            out.data(local: 2, record, [fitTime(p.ts), UInt64(p.bpm)])
        }

        out.data(local: 1, event, [fitTime(w.end), 0, 4])

        // laps
        let lap = [Field(num: 253, base: .uint32), Field(num: 2, base: .uint32), Field(num: 7, base: .uint32),
                   Field(num: 8, base: .uint32), Field(num: 0, base: .enumT), Field(num: 1, base: .enumT),
                   Field(num: 15, base: .uint8), Field(num: 16, base: .uint8), Field(num: 11, base: .uint16),
                   Field(num: 254, base: .uint16)]
        out.define(local: 3, global: 19, lap)
        let laps = track.lapStats()
        let totalMinutes = max(1.0, Double(w.end - w.start) / 60)
        for (i, l) in laps.enumerated() {
            let ms = UInt64(max(0, l.end - l.start)) * 1000
            let kcal = UInt64((w.kcal * Double(l.end - l.start) / 60 / totalMinutes).rounded())
            out.data(local: 3, lap, [fitTime(l.end), fitTime(l.start), ms, ms, 9, 1,
                                     l.avg.map { UInt64($0) } ?? invalid8, l.max.map { UInt64($0) } ?? invalid8,
                                     min(kcal, 0xFFFE), UInt64(i)])
        }

        // session
        let session = [Field(num: 253, base: .uint32), Field(num: 2, base: .uint32), Field(num: 7, base: .uint32),
                       Field(num: 8, base: .uint32), Field(num: 5, base: .enumT), Field(num: 6, base: .enumT),
                       Field(num: 0, base: .enumT), Field(num: 1, base: .enumT), Field(num: 16, base: .uint8),
                       Field(num: 17, base: .uint8), Field(num: 11, base: .uint16), Field(num: 25, base: .uint16),
                       Field(num: 26, base: .uint16), Field(num: 9, base: .uint32)]
        out.define(local: 4, global: 18, session)
        let hrs = track.heartRate.map { $0.bpm }
        let avg = hrs.isEmpty ? (w.avgHR > 0 ? UInt64(w.avgHR.rounded()) : invalid8) : UInt64(hrs.reduce(0, +) / hrs.count)
        let mx = hrs.max().map { UInt64($0) } ?? (w.maxHR > 0 ? UInt64(w.maxHR.rounded()) : invalid8)
        let distance = w.distanceMeters.map { UInt64(($0 * 100).rounded()) } ?? 0xFFFF_FFFF
        out.data(local: 4, session, [fitTime(w.end), fitTime(w.start), elapsedMs, elapsedMs, UInt64(sport.fitSport),
                                     UInt64(sport.fitSubSport), 8, 1, avg, mx, min(UInt64(max(0, w.kcal.rounded())), 0xFFFE),
                                     0, UInt64(laps.count), distance])

        // activity
        let activity = [Field(num: 253, base: .uint32), Field(num: 0, base: .uint32), Field(num: 1, base: .uint16),
                        Field(num: 2, base: .enumT), Field(num: 3, base: .enumT), Field(num: 4, base: .enumT),
                        Field(num: 5, base: .uint32)]
        out.define(local: 5, global: 34, activity)
        let tzOffset = TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(w.end)))
        out.data(local: 5, activity, [fitTime(w.end), elapsedMs, 1, 0, 26, 1, fitTime(w.end + tzOffset)])

        // Header (14 bytes, protocol 2.0, profile 21.40) + data + file CRC.
        let size = UInt32(out.bytes.count)
        var header: [UInt8] = [14, 0x20, 0x5C, 0x08]
        header += [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8(size >> 24)]
        header += Array(".FIT".utf8)
        let hcrc = crc(header)
        header += [UInt8(hcrc & 0xFF), UInt8(hcrc >> 8)]
        var file = header + out.bytes
        let fcrc = crc(file)
        file += [UInt8(fcrc & 0xFF), UInt8(fcrc >> 8)]
        return file
    }
}

// MARK: - TCX

public enum TCXEncoder {
    static func iso(_ ts: Int) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    public static func encode(_ track: WorkoutTrack) -> String {
        let w = track.workout
        let sport = SportCatalog.named(w.sport)
        let totalMinutes = max(1.0, Double(w.end - w.start) / 60)
        var x = """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities>
            <Activity Sport="\(sport.tcx)">
              <Id>\(iso(w.start))</Id>

        """
        for l in track.lapStats() {
            let kcal = Int((w.kcal * Double(l.end - l.start) / 60 / totalMinutes).rounded())
            x += """
                  <Lap StartTime="\(iso(l.start))">
                    <TotalTimeSeconds>\(l.end - l.start)</TotalTimeSeconds>
                    <DistanceMeters>\(String(format: "%.1f", (w.distanceMeters ?? 0) * Double(l.end - l.start) / Double(max(1, w.end - w.start))))</DistanceMeters>
                    <Calories>\(max(0, kcal))</Calories>

            """
            if let a = l.avg { x += "        <AverageHeartRateBpm><Value>\(a)</Value></AverageHeartRateBpm>\n" }
            if let m = l.max { x += "        <MaximumHeartRateBpm><Value>\(m)</Value></MaximumHeartRateBpm>\n" }
            x += "        <Intensity>Active</Intensity>\n        <TriggerMethod>Manual</TriggerMethod>\n        <Track>\n"
            for p in track.heartRate where p.ts >= l.start && p.ts < l.end {
                x += "          <Trackpoint><Time>\(iso(p.ts))</Time><HeartRateBpm><Value>\(p.bpm)</Value></HeartRateBpm></Trackpoint>\n"
            }
            x += "        </Track>\n      </Lap>\n"
        }
        x += """
              <Notes>\(escape(w.notes.isEmpty ? "Registrado con Pulso" : w.notes))</Notes>
              <Creator xsi:type="Device_t" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Name>Pulso</Name><UnitId>0</UnitId><ProductID>0</ProductID><Version><VersionMajor>1</VersionMajor><VersionMinor>1</VersionMinor><BuildMajor>0</BuildMajor><BuildMinor>0</BuildMinor></Version></Creator>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>

        """
        return x
    }
}
