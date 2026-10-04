import Foundation

/// One per-second summary record from the strap's flash (HISTORICAL_DATA type 47, layout v18 on 5.0/MG).
/// Offsets are INNER-relative (frame-absolute − 8). Every field is range-gated so a wrong offset on an
/// unmapped firmware yields nil rather than a bogus number.
public struct HistorySample: Equatable, Sendable {
    public var unix: UInt32
    public var recordIndex: UInt32?
    public var heartRate: UInt8?
    public var rr: [UInt16]
    public var gravity: SIMD3<Float>?
    public var dynamicAccelG: Float?
    public var skinTempC: Float?
    public var spo2: UInt8?
    public var steps: UInt16?
    /// 0 still / 1 walk / 2 run
    public var activityClass: UInt8?
    /// Strap's own provisional state {0 still, 1 wake, 2 asleep, 3 up}
    public var sleepState: UInt8?
    public var signalFlags: UInt8?
    public var signalQuality: UInt8?
    /// Both optical amplitude channels read the 128 sentinel: the band's own beat detection was unreliable.
    public var signalPoor: Bool
    /// Off-wrist: flag bit 4, both optical baselines zero, or no HR at all.
    public var offWrist: Bool

    public init(unix: UInt32, recordIndex: UInt32? = nil, heartRate: UInt8? = nil, rr: [UInt16] = [],
                gravity: SIMD3<Float>? = nil, dynamicAccelG: Float? = nil, skinTempC: Float? = nil,
                spo2: UInt8? = nil, steps: UInt16? = nil, activityClass: UInt8? = nil, sleepState: UInt8? = nil,
                signalFlags: UInt8? = nil, signalQuality: UInt8? = nil, signalPoor: Bool = false, offWrist: Bool = false) {
        self.unix = unix
        self.recordIndex = recordIndex
        self.heartRate = heartRate
        self.rr = rr
        self.gravity = gravity
        self.dynamicAccelG = dynamicAccelG
        self.skinTempC = skinTempC
        self.spo2 = spo2
        self.steps = steps
        self.activityClass = activityClass
        self.sleepState = sleepState
        self.signalFlags = signalFlags
        self.signalQuality = signalQuality
        self.signalPoor = signalPoor
        self.offWrist = offWrist
    }

    /// Decodes a gen5 v18 record. Returns nil for any other frame.
    public static func decodeV18(_ f: Frame) -> HistorySample? {
        guard f.family == .gen5, f.canonicalType == .historicalData, f.version == 18 else { return nil }
        let b = f.inner
        guard let unix = LE.u32(b, 7) else { return nil }

        let hr = LE.u8(b, 14).flatMap { (25...240).contains($0) ? $0 : nil }
        let rr = readRR(b, countAt: 15, firstAt: 16, maxSlots: 4)

        var gravity: SIMD3<Float>?
        if let x = LE.f32(b, 37), let y = LE.f32(b, 41), let z = LE.f32(b, 45),
           x.isFinite, y.isFinite, z.isFinite {
            let mag = (x * x + y * y + z * z).squareRoot()
            if (0.5...1.5).contains(mag) { gravity = SIMD3(x, y, z) }
        }
        let dyn = LE.f32(b, 33).flatMap { ($0.isFinite && (0...8).contains($0)) ? $0 : nil }
        let temp = LE.u16(b, 65).flatMap { raw -> Float? in
            let c = Float(raw) / 100
            return (5...45).contains(c) ? c : nil
        }
        let spo2 = LE.u8(b, 74).flatMap { (70...100).contains($0) ? $0 : nil }
        let activity = LE.u8(b, 55).flatMap { $0 <= 2 ? $0 : nil }
        let sleepState = LE.u8(b, 73).map { ($0 >> 4) & 0x03 }
        let flags = LE.u8(b, 25)
        let quality = LE.u8(b, 32)
        let ampA = LE.u8(b, 100), ampB = LE.u8(b, 101)
        let poor = ampA == 128 && ampB == 128
        let baseA = LE.u8(b, 98), baseB = LE.u8(b, 99)
        let baselinesZero = baseA == 0 && baseB == 0
        let flagOff = ((flags ?? 0) & 0x10) != 0

        return HistorySample(
            unix: unix,
            recordIndex: LE.u32(b, 3),
            heartRate: hr,
            rr: rr,
            gravity: gravity,
            dynamicAccelG: dyn,
            skinTempC: temp,
            spo2: spo2,
            steps: LE.u16(b, 49),
            activityClass: activity,
            sleepState: sleepState,
            signalFlags: flags,
            signalQuality: quality,
            signalPoor: poor,
            offWrist: flagOff || baselinesZero || hr == nil
        )
    }

    /// Reads `count` (clamped) consecutive u16 R-R intervals, keeping only physiological values (300–2000 ms).
    static func readRR(_ b: [UInt8], countAt: Int, firstAt: Int, maxSlots: Int) -> [UInt16] {
        let n = min(Int(LE.u8(b, countAt) ?? 0), maxSlots)
        var out: [UInt16] = []
        for i in 0..<n {
            if let v = LE.u16(b, firstAt + i * 2), (300...2000).contains(v) { out.append(v) }
        }
        return out
    }
}

/// REALTIME_DATA (type 40): ~1 Hz while TOGGLE_REALTIME_HR is on.
public struct RealtimeHR: Equatable, Sendable {
    public var unix: UInt32
    public var heartRate: UInt8
    public var rr: [UInt16]
    public var valid: Bool

    public static func decode(_ f: Frame) -> RealtimeHR? {
        guard f.canonicalType == .realtimeData else { return nil }
        let b = f.inner
        guard let ts = LE.u32(b, 2), let hr = LE.u8(b, 8) else { return nil }
        let flag = LE.u8(b, 9) ?? 0
        let slots = max(0, (b.count - 10) / 2)
        let rr = HistorySample.readRR(b, countAt: 9, firstAt: 10, maxSlots: min(slots, 8))
        return RealtimeHR(unix: ts, heartRate: hr, rr: rr, valid: flag != 0 && hr > 0)
    }
}

/// Standard Bluetooth Heart Rate Measurement (0x2A37) value.
public struct StandardHRMeasurement: Equatable, Sendable {
    public var heartRate: Int
    public var rr: [Int]

    public static func decode(_ v: [UInt8]) -> StandardHRMeasurement? {
        guard let flags = v.first else { return nil }
        var i = 1
        let hr: Int
        if flags & 0x01 != 0 {
            guard let h = LE.u16(v, i) else { return nil }
            hr = Int(h); i += 2
        } else {
            guard let h = LE.u8(v, i) else { return nil }
            hr = Int(h); i += 1
        }
        if flags & 0x08 != 0 { i += 2 } // energy expended
        var rr: [Int] = []
        if flags & 0x10 != 0 {
            while let r = LE.u16(v, i) {
                let ms = Int((Double(r) / 1024.0 * 1000.0).rounded())
                if (300...2000).contains(ms) { rr.append(ms) }
                i += 2
            }
        }
        guard hr > 0 else { return nil }
        return StandardHRMeasurement(heartRate: hr, rr: rr)
    }
}

public enum StrapEventKind: UInt8, Sendable {
    case batteryLevel = 3
    case chargingOn = 7
    case chargingOff = 8
    case wristOn = 9
    case wristOff = 10
    case doubleTap = 14
    case bleBonded = 23
    case alarmSet = 56
    case strapAlarmExecuted = 57
    case appAlarmExecuted = 58
    case alarmDisabled = 59
    case hapticsFired = 60
    case hapticsTerminated = 100
}

/// EVENT (type 48 and the gen5 aliases 53/54).
public struct StrapEvent: Equatable, Sendable {
    public var number: UInt8
    public var unix: UInt32?
    public var kind: StrapEventKind? { StrapEventKind(rawValue: number) }
    /// Battery % (deci-percent / 10) for BATTERY_LEVEL events.
    public var batteryPercent: Double?
    public var charging: Bool?

    public static func decode(_ f: Frame) -> StrapEvent? {
        guard f.canonicalType == .event else { return nil }
        let b = f.inner
        var e = StrapEvent(number: f.cmd, unix: LE.u32(b, 4))
        if f.cmd == StrapEventKind.batteryLevel.rawValue, let deci = LE.u16(b, 13), deci <= 1000 {
            e.batteryPercent = Double(deci) / 10
            e.charging = LE.u8(b, 22).map { $0 & 1 != 0 }
        }
        return e
    }
}

/// METADATA (type 49/56): offload chunk boundaries.
public struct OffloadMetadata: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        case historyStart = 1
        case historyEnd = 2
        case historyComplete = 3
    }

    public var kind: Kind?
    public var unix: UInt32
    public var trimCursor: UInt32
    /// 8-byte token (inner 13..<21) the strap expects echoed in HISTORICAL_DATA_RESULT.
    public var token: [UInt8]?

    public static func decode(_ f: Frame) -> OffloadMetadata? {
        guard f.canonicalType == .metadata else { return nil }
        let b = f.inner
        let token: [UInt8]? = b.count >= 21 ? Array(b[13..<21]) : nil
        return OffloadMetadata(kind: Kind(rawValue: f.cmd), unix: LE.u32(b, 3) ?? 0,
                               trimCursor: LE.u32(b, 13) ?? 0, token: token)
    }
}

/// COMMAND_RESPONSE (type 36/38). Gen5 payload = `[origin seq][status][body…]`.
public struct CommandResponse: Equatable, Sendable {
    public enum Status: UInt8, Sendable {
        case failure = 0, success = 1, pending = 2, unsupported = 3
    }

    public var cmd: UInt8
    public var originSeq: UInt8?
    public var status: Status?
    public var body: [UInt8]

    public static func decode(_ f: Frame) -> CommandResponse? {
        guard f.canonicalType == .commandResponse else { return nil }
        let p = f.payload
        if f.family == .gen5 {
            return CommandResponse(cmd: f.cmd, originSeq: LE.u8(p, 0), status: LE.u8(p, 1).flatMap { Status(rawValue: $0) },
                                   body: p.count > 2 ? Array(p[2...]) : [])
        }
        return CommandResponse(cmd: f.cmd, originSeq: nil, status: nil, body: p)
    }

    /// Gen5 GET_BATTERY_LEVEL reply: body[0] is the percent.
    public var batteryPercent: Double? {
        guard cmd == Opcode.getBatteryLevel, let v = LE.u8(body, 0), v <= 100 else { return nil }
        return Double(v)
    }
}

/// Gen5 GET_HELLO revision-1 reply body.
public struct HelloInfo: Equatable, Sendable {
    public var revision: UInt8
    public var batteryPercent: Int?
    public var charging: Bool
    public var strapUnix: UInt32?
    public var serial: String
    public var firmware: String
    public var wristOn: Bool
    public var isMG: Bool

    public static func decode(_ r: CommandResponse) -> HelloInfo? {
        guard r.cmd == Opcode.getHello, r.status == .success || r.status == nil else { return nil }
        let b = r.body
        guard b.count >= 25 else { return nil }
        let rawBatt = LE.u32(b, 1).map { Int($0 / 10) }
        let ts = LE.u32(b, 6).flatMap { (1_600_000_000...2_200_000_000).contains($0) ? $0 : nil }
        var fw = ""
        if let a = LE.u8(b, 91), let c = LE.u8(b, 92), let d = LE.u8(b, 93) {
            fw = "\(a).\(c).\(d)"
        }
        let optical = LE.u32(b, 87)
        return HelloInfo(
            revision: b[0],
            batteryPercent: rawBatt.flatMap { (0...100).contains($0) ? $0 : nil },
            charging: (LE.u8(b, 5) ?? 0) & 1 == 1,
            strapUnix: ts,
            serial: LE.asciiZ(b, 14, maxLen: 11),
            firmware: fw,
            wristOn: LE.u8(b, 102) == 1,
            isMG: b[0] == 1 && (optical.map { $0 < 38 } ?? false)
        )
    }
}

/// Everything a notification can decode to.
public enum StrapMessage: Equatable, Sendable {
    case history(HistorySample)
    case otherHistory(version: UInt8)
    case realtime(RealtimeHR)
    case event(StrapEvent)
    case metadata(OffloadMetadata)
    case response(CommandResponse)
    case ignored(UInt8)

    public static func decode(_ f: Frame) -> StrapMessage {
        guard let t = f.canonicalType else { return .ignored(f.typeByte) }
        switch t {
        case .historicalData:
            if let s = HistorySample.decodeV18(f) { return .history(s) }
            return .otherHistory(version: f.version)
        case .realtimeData:
            if let r = RealtimeHR.decode(f) { return .realtime(r) }
        case .event:
            if let e = StrapEvent.decode(f) { return .event(e) }
        case .metadata:
            if let m = OffloadMetadata.decode(f) { return .metadata(m) }
        case .commandResponse:
            if let r = CommandResponse.decode(f) { return .response(r) }
        default:
            break
        }
        return .ignored(f.typeByte)
    }
}
