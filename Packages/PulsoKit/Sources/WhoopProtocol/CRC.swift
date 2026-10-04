/// The checksums used on the WHOOP wire.
/// - crc8:        WHOOP 4.0 header check over the two length bytes (poly 0x07, MSB-first, init 0).
/// - crc16Modbus: WHOOP 5.0/MG header check over the first 6 header bytes (poly 0xA001 reflected, init 0xFFFF).
/// - crc32:       inner-record trailer, both generations (standard zlib/IEEE).
public enum CRC {
    public static func crc8(_ data: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for b in data {
            crc ^= b
            for _ in 0..<8 {
                crc = (crc & 0x80) != 0 ? (crc << 1) ^ 0x07 : (crc << 1)
            }
        }
        return crc
    }

    public static func crc16Modbus(_ data: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in data {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : (crc >> 1)
            }
        }
        return crc
    }

    private static let table32: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (c >> 1) ^ 0xEDB8_8320 : (c >> 1)
            }
            return c
        }
    }()

    public static func crc32(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data {
            crc = table32[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
