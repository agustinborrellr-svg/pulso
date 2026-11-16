import Foundation
import WhoopProtocol

/// A minimal .zip writer (no ZIP64, so under 4 GB and 65 535 files): enough to share the CSV exports as one small
/// file. The caller compresses; this only lays out the container.
public enum ZipWriter {
    public struct Entry {
        public let name: String
        public let data: Data
        /// `data` as a raw DEFLATE stream (RFC 1951). Nil, or not smaller than `data`, stores it uncompressed.
        public let deflated: Data?

        public init(name: String, data: Data, deflated: Data? = nil) {
            self.name = name
            self.data = data
            self.deflated = deflated
        }
    }

    public static func archive(_ entries: [Entry], date: Date = Date(), calendar: Calendar = .current) -> Data {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let year: Int = max((c.year ?? 1980) - 1980, 0), month: Int = c.month ?? 1, day: Int = c.day ?? 1
        let dosTime = UInt16(truncatingIfNeeded: (hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(truncatingIfNeeded: (year << 9) | (month << 5) | day)

        var out = Data()
        var central = Data()
        for e in entries {
            let name = Array(e.name.utf8)
            let packed = e.deflated.flatMap { $0.count < e.data.count ? $0 : nil }
            let body = packed ?? e.data
            let crc = CRC.crc32([UInt8](e.data))
            let offset = UInt32(out.count)
            // Shared by the local header and the central directory: version, flags (bit 11 = UTF-8 names),
            // method, time, date, CRC, sizes, name and extra lengths.
            var common = Data()
            common.append(le16(20))
            common.append(le16(0x0800))
            common.append(le16(packed == nil ? 0 : 8))
            common.append(le16(dosTime))
            common.append(le16(dosDate))
            common.append(le32(crc))
            common.append(le32(UInt32(body.count)))
            common.append(le32(UInt32(e.data.count)))
            common.append(le16(UInt16(name.count)))
            common.append(le16(0))

            out.append(le32(0x0403_4B50))
            out.append(common)
            out.append(contentsOf: name)
            out.append(body)

            central.append(le32(0x0201_4B50))
            central.append(le16(20)) // made by
            central.append(common)
            central.append(le16(0)) // comment length
            central.append(le16(0)) // disk number
            central.append(le16(0)) // internal attributes
            central.append(le32(0)) // external attributes
            central.append(le32(offset))
            central.append(contentsOf: name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.append(le32(0x0605_4B50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(entries.count)))
        out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}
