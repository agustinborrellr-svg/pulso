import Foundation

/// Command opcodes (inner byte 2 of an outbound COMMAND frame). Only the safe, read-mostly subset
/// this app actually sends is exposed as builders; destructive opcodes are listed so nothing can
/// build them by accident.
public enum Opcode {
    public static let linkValid: UInt8 = 1
    public static let toggleRealtimeHR: UInt8 = 3
    public static let setClock: UInt8 = 10
    public static let getClock: UInt8 = 11
    public static let runHapticPatternMaverick: UInt8 = 19
    public static let abortHistoricalTransmits: UInt8 = 20
    public static let sendHistoricalData: UInt8 = 22
    public static let historicalDataResult: UInt8 = 23
    public static let getBatteryLevel: UInt8 = 26
    public static let getDataRange: UInt8 = 34
    public static let getHelloHarvard: UInt8 = 35
    public static let setAlarmTime: UInt8 = 66
    public static let getAlarmTime: UInt8 = 67
    public static let disableAlarm: UInt8 = 69
    public static let stopHaptics: UInt8 = 122
    public static let getAdvertisingName: UInt8 = 141
    public static let getHello: UInt8 = 145

    /// Never sent by this app. Numbers follow the WHOOP 5/MG 50.42.x command matrix documented by NOOP:
    /// 14 generic-HR profile (NV write), 15 FORGET_BONDS, 25 FORCE_TRIM, 29/32 reboot, 33 SET_READ_POINTER,
    /// 36–38 + 83 + 142–144 firmware image, 45 DFU, 61 AFE params, 73 smart-alarm haptics (NV), 77/140 advertising
    /// name, 99 fuel-gauge reset, 100/101 capsense, 115–121 persistent config/feature flags, 123 wrist select,
    /// 138 signal-processing config, 146/147 new clock pair (we use the legacy 10), 148 wear override,
    /// 149 LED accessibility, 150 gyro mode, 153/154 persistent R20/R21, 155–159 certificates + LOCK_DEVICE.
    public static let forbidden: Set<UInt8> = [
        14, 15, 25, 29, 32, 33, 36, 37, 38, 45, 61, 73, 77, 83, 99, 100, 101,
        115, 116, 117, 118, 119, 120, 121, 123, 138, 140, 142, 143, 144, 146, 147, 148, 149, 150,
        153, 154, 155, 156, 157, 158, 159,
    ]
}

/// Builds outbound command frames with a running sequence number.
public final class CommandBuilder {
    public let family: Family
    private var seq: UInt8

    public init(family: Family = .gen5, startSeq: UInt8 = 2) {
        self.family = family
        self.seq = startSeq
    }

    /// The sequence number the next frame will carry.
    public var nextSeq: UInt8 { seq }

    /// Builds a command frame. Returns nil for any opcode on the forbidden list.
    public func frame(_ opcode: UInt8, _ payload: [UInt8] = []) -> (seq: UInt8, bytes: [UInt8])? {
        guard !Opcode.forbidden.contains(opcode) else { return nil }
        let s = seq
        seq = seq &+ 1
        return (s, Framing.command(family, seq: s, cmd: opcode, payload: payload))
    }

    // MARK: - Builders

    /// The gen5 session opener: a type-35 COMMAND carrying GET_HELLO(145) with body `[0x01]`, seq 1.
    /// Written *with response* right after discovery: that confirmed write triggers the BLE bond.
    public static let gen5ClientHello: [UInt8] = Framing.command(.gen5, seq: 1, cmd: Opcode.getHello, payload: [0x01])

    public func getHello() -> (seq: UInt8, bytes: [UInt8])? { frame(Opcode.getHello, [0x01]) }
    public func getAdvertisingName() -> (seq: UInt8, bytes: [UInt8])? { frame(Opcode.getAdvertisingName, [0x01]) }
    public func getBattery() -> (seq: UInt8, bytes: [UInt8])? { frame(Opcode.getBatteryLevel, [0x01]) }
    public func getClock() -> (seq: UInt8, bytes: [UInt8])? { frame(Opcode.getClock, []) }
    /// GET_DATA_RANGE(34) with the `00` request byte NOOP sends with every command (as SEND_HISTORICAL_DATA,
    /// where an empty body makes the 5.0 serve nothing).
    public func getDataRange() -> (seq: UInt8, bytes: [UInt8])? { frame(Opcode.getDataRange, [0x00]) }

    public func toggleRealtimeHR(_ on: Bool) -> (seq: UInt8, bytes: [UInt8])? {
        frame(Opcode.toggleRealtimeHR, [on ? 0x01 : 0x00])
    }

    /// SET_CLOCK(10): `[u32 seconds][u32 subseconds (1/32768 s)]`, written here as u16 + two zero bytes.
    /// Opcode 10 is the legacy clock command (NOOP lists 146/147 as the current pair) but the 8-byte body on
    /// opcode 10 is the one OpenStrap verified to latch on real 5.0 hardware; an un-clocked WHOOP 5 discards
    /// sensor data, so this must run before any history offload.
    public func setClock(_ date: Date = Date()) -> (seq: UInt8, bytes: [UInt8])? {
        frame(Opcode.setClock, CommandBuilder.clockPayload(date))
    }

    public static func clockPayload(_ date: Date) -> [UInt8] {
        let ms = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        let sec = UInt32(truncatingIfNeeded: ms / 1000)
        let sub = UInt16(((ms % 1000) * 32768) / 1000)
        return LE.bytes(sec) + LE.bytes(sub) + [0, 0]
    }

    /// SEND_HISTORICAL_DATA(22) with the explicit `00` request byte every reference client sends (padding
    /// would produce the same bytes, but the byte is semantic, not filler).
    public func sendHistoricalData() -> (seq: UInt8, bytes: [UInt8])? { frame(Opcode.sendHistoricalData, [0x00]) }
    public func abortHistorical() -> (seq: UInt8, bytes: [UInt8])? { frame(Opcode.abortHistoricalTransmits, [0x00]) }

    /// HISTORICAL_DATA_RESULT(23) success: `[0x01] + 8-byte token` echoed from HISTORY_END.
    /// Acknowledging lets the strap advance (and eventually free) that chunk, so it must only be
    /// sent after the chunk has been persisted.
    public func historyAck(token: [UInt8]) -> (seq: UInt8, bytes: [UInt8])? {
        guard token.count == 8 else { return nil }
        return frame(Opcode.historicalDataResult, [0x01] + token)
    }

    /// Body byte 11 of RUN_HAPTIC_PATTERN_MAVERICK counts repetitions *after* the first pulse and the
    /// firmware rejects values of 8 or more, so `pulses` buzzes are encoded as `pulses - 1`, capped at 7.
    static func overallRepeat(pulses: UInt8) -> UInt8 { min(max(pulses, 1) - 1, 7) }

    /// Gen5 one-shot buzz (RUN_HAPTIC_PATTERN_MAVERICK 0x13): the notification waveform pair 47/152,
    /// played `loops` times (1…8).
    public func buzz(loops: UInt8 = 1) -> (seq: UInt8, bytes: [UInt8])? {
        frame(Opcode.runHapticPatternMaverick, [0x01, 47, 152, 0, 0, 0, 0, 0, 0, 0, 0, Self.overallRepeat(pulses: loops)])
    }

    /// RUN_HAPTIC_PATTERN_MAVERICK with up to 8 waveform ids (used by the Laboratorio tester to find
    /// stronger / softer effects on a given firmware). Non-persistent: it only vibrates. Effect ids above
    /// 251 are rejected by the firmware, so they are clamped.
    public func haptic(effects: [UInt8], loops: UInt8 = 1) -> (seq: UInt8, bytes: [UInt8])? {
        let fx = Array(effects.prefix(8)).map { min($0, 251) } + [UInt8](repeating: 0, count: max(0, 8 - effects.count))
        guard fx.contains(where: { $0 != 0 }) else { return nil }
        return frame(Opcode.runHapticPatternMaverick, [0x01] + fx + [0, 0, Self.overallRepeat(pulses: loops)])
    }

    /// STOP_HAPTICS(122): cuts a running vibration short.
    public func stopHaptics() -> (seq: UInt8, bytes: [UInt8])? { frame(Opcode.stopHaptics, [0x00]) }

    /// Gen5 on-strap alarm, REVISION_4 body (21 bytes on the wire: the trailing alarm-type/crescendo byte is
    /// 0 and comes from the 4-byte padding). Experimental on 5.0 firmware.
    /// `[0]=4 [1]=id(1…6) [2..6]=u32 epoch s [6..8]=u16 subsec [8..16]=effects [16..18]=0 [18]=repeats(<8) [19]=duration s`
    /// With repeats = 7 the firmware requires a duration of 30–120 s. The time must be strictly in the future.
    public func setAlarm(at date: Date, id: UInt8 = 1) -> (seq: UInt8, bytes: [UInt8])? {
        let ms = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        var body = [UInt8](repeating: 0, count: 20)
        body[0] = 4
        body[1] = min(max(id, 1), 6)
        let s = LE.bytes(UInt32(truncatingIfNeeded: ms / 1000))
        body[2] = s[0]; body[3] = s[1]; body[4] = s[2]; body[5] = s[3]
        let sub = LE.bytes(UInt16(((ms % 1000) * 32768) / 1000))
        body[6] = sub[0]; body[7] = sub[1]
        body[8] = 47; body[9] = 152
        body[18] = 7
        body[19] = 30
        return frame(Opcode.setAlarmTime, body)
    }

    public func disableAlarm() -> (seq: UInt8, bytes: [UInt8])? { frame(Opcode.disableAlarm, [0x02, 0xFF]) }
}
