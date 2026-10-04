import Foundation

/// Wire generation. The 5.0 and the MG frame identically ("puffin"/"maverick"); the 4.0 ("harvard")
/// uses a shorter header with a CRC-8.
public enum Family: String, Codable, Sendable {
    case gen4
    case gen5

    var innerStart: Int { self == .gen5 ? 8 : 4 }
    var lengthOffset: Int { self == .gen5 ? 2 : 1 }

    /// `AA 01 …` ⇒ gen5 (format byte), a lone `AA` ⇒ gen4.
    public static func detect(_ bytes: [UInt8]) -> Family? {
        guard bytes.first == 0xAA else { return nil }
        return bytes.count > 1 && bytes[1] == 0x01 ? .gen5 : .gen4
    }
}

/// Packet-type byte (inner byte 0).
public enum PacketType: UInt8, Sendable {
    case command = 35
    case commandResponse = 36
    case puffinCommand = 37
    case puffinCommandResponse = 38
    case realtimeData = 40
    case realtimeRawData = 43
    case historicalData = 47
    case event = 48
    case metadata = 49
    case consoleLogs = 50
    case realtimeImuStream = 51
    case historicalImuStream = 52
    case relativePuffinEvents = 53
    case puffinEventsFromStrap = 54
    case puffinMetadata = 56

    /// Folds the gen5 aliases onto their base type so routing is generation-agnostic.
    public var canonical: PacketType {
        switch self {
        case .puffinCommand: return .command
        case .puffinCommandResponse: return .commandResponse
        case .relativePuffinEvents, .puffinEventsFromStrap: return .event
        case .puffinMetadata: return .metadata
        default: return self
        }
    }
}

/// One complete, reassembled frame. `inner` = `[type][seq][cmd][payload…]` (CRC-covered bytes).
public struct Frame: Equatable, Sendable {
    public let family: Family
    public let raw: [UInt8]
    public let inner: [UInt8]
    public let crcOK: Bool

    public var typeByte: UInt8 { inner.first ?? 0 }
    public var packetType: PacketType? { PacketType(rawValue: typeByte) }
    public var canonicalType: PacketType? { packetType?.canonical }
    /// Byte 1. For HISTORICAL_DATA frames this is the record layout version.
    public var seq: UInt8 { inner.count > 1 ? inner[1] : 0 }
    public var version: UInt8 { seq }
    /// Byte 2: command opcode / event number / metadata sub-type.
    public var cmd: UInt8 { inner.count > 2 ? inner[2] : 0 }
    public var payload: [UInt8] { inner.count > 3 ? Array(inner[3...]) : [] }
}

public enum FrameError: Error, Equatable {
    case badStartOfFrame
    case tooShort
    case badLength
}

public enum Framing {
    /// Builds a complete outbound frame for `[type][seq][cmd] + payload`.
    /// Gen5 inners are zero-padded to a 4-byte multiple before length/CRC (the strap rejects otherwise).
    public static func encode(_ family: Family, type: UInt8, seq: UInt8, cmd: UInt8, payload: [UInt8]) -> [UInt8] {
        var inner: [UInt8] = [type, seq, cmd] + payload
        if family == .gen5 {
            let pad = (4 - inner.count % 4) % 4
            inner += [UInt8](repeating: 0, count: pad)
        }
        let declared = UInt16(inner.count + 4)
        var frame: [UInt8] = []
        frame.reserveCapacity(family.innerStart + inner.count + 4)
        switch family {
        case .gen4:
            frame.append(0xAA)
            frame += LE.bytes(declared)
            frame.append(CRC.crc8(Array(frame[1..<3])))
        case .gen5:
            frame += [0xAA, 0x01]
            frame += LE.bytes(declared)
            frame += [0x00, 0x01]
            frame += LE.bytes(CRC.crc16Modbus(Array(frame[0..<6])))
        }
        frame += inner
        frame += LE.bytes(CRC.crc32(inner))
        return frame
    }

    /// Convenience for the common COMMAND frame.
    public static func command(_ family: Family, seq: UInt8, cmd: UInt8, payload: [UInt8]) -> [UInt8] {
        encode(family, type: PacketType.command.rawValue, seq: seq, cmd: cmd, payload: payload)
    }

    /// Parses exactly one complete frame. A checksum mismatch is reported via `crcOK`, not thrown.
    public static func decode(_ family: Family, _ bytes: [UInt8]) throws -> Frame {
        guard bytes.first == 0xAA else { throw FrameError.badStartOfFrame }
        guard let declared16 = LE.u16(bytes, family.lengthOffset) else { throw FrameError.tooShort }
        let declared = Int(declared16)
        guard declared > 4 else { throw FrameError.badLength }
        let total = declared + family.innerStart
        guard bytes.count >= total else { throw FrameError.tooShort }
        let innerEnd = family.innerStart + declared - 4
        let inner = Array(bytes[family.innerStart..<innerEnd])

        let headerOK: Bool
        switch family {
        case .gen4:
            headerOK = CRC.crc8(Array(bytes[1..<3])) == bytes[3]
        case .gen5:
            headerOK = LE.u16(bytes, 6) == CRC.crc16Modbus(Array(bytes[0..<6]))
        }
        let payloadOK = LE.u32(bytes, innerEnd) == CRC.crc32(inner)
        return Frame(family: family, raw: Array(bytes[0..<total]), inner: inner, crcOK: headerOK && payloadOK)
    }
}

/// Length-based reassembly of BLE notification fragments into frames. Resyncs on the SOF byte
/// (payloads can legitimately contain 0xAA, so an implausible length just skips one byte).
/// Use one Deframer per notify characteristic so interleaved streams stay aligned.
public final class Deframer {
    public let family: Family
    private var buffer: [UInt8] = []
    private static let maxFrame = 8192

    public init(family: Family) {
        self.family = family
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    public func push(_ data: [UInt8]) -> [Frame] {
        buffer += data
        var out: [Frame] = []
        var head = 0
        let lenOff = family.lengthOffset
        while true {
            while head < buffer.count && buffer[head] != 0xAA { head += 1 }
            let available = buffer.count - head
            if available < lenOff + 2 { break }
            let declared = Int(buffer[head + lenOff]) | (Int(buffer[head + lenOff + 1]) << 8)
            let total = declared + family.innerStart
            if declared < 5 || total > Deframer.maxFrame {
                head += 1
                continue
            }
            if family == .gen5 {
                // Cheap early rejection of fake SOFs: the gen5 format byte and header CRC must match.
                if available >= 8 {
                    let hdr = Array(buffer[head..<head + 6])
                    let crcOK = hdr[1] == 0x01 && LE.u16(buffer, head + 6) == CRC.crc16Modbus(hdr)
                    if !crcOK {
                        head += 1
                        continue
                    }
                } else {
                    break
                }
            }
            if available < total { break }
            let end = head + total
            if let frame = try? Framing.decode(family, Array(buffer[head..<end])) {
                out.append(frame)
            }
            head = end
        }
        if head > 0 {
            buffer.removeFirst(min(head, buffer.count))
        }
        return out
    }
}
