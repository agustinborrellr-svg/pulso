import XCTest
import Foundation
@testable import PulsoAnalytics

final class ZipWriterTests: XCTestCase {
    private func u16(_ d: Data, _ at: Int) -> Int { Int(d[at]) | Int(d[at + 1]) << 8 }
    private func u32(_ d: Data, _ at: Int) -> Int { u16(d, at) | u16(d, at + 2) << 16 }

    /// 568 bytes of CSV and their raw DEFLATE stream (zlib level 9, no header).
    private let plain = Data(("unix,fc\n" + String(repeating: "1793362993,58\n", count: 40)).utf8)
    private let deflated = Data([0x2B, 0xCD, 0xCB, 0xAC, 0xD0, 0x49, 0x4B, 0xE6, 0x32, 0x34, 0xB7, 0x34, 0x36, 0x36, 0x33, 0xB2,
                                 0xB4, 0x34, 0xD6, 0x31, 0xB5, 0x18, 0xE5, 0x8D, 0xF2, 0x08, 0xF0, 0x00])

    func testLayoutOfAStoredAndADeflatedEntry() throws {
        let stored = Data("fecha,recuperacion\n2026-11-16,46\n".utf8)
        let zip = ZipWriter.archive([
            .init(name: "pulso_días.csv", data: stored),
            .init(name: "pulso_segundos.csv", data: plain, deflated: deflated),
        ])
        // End of central directory: two entries, and the directory sits where it says.
        let end = zip.count - 22
        XCTAssertEqual(u32(zip, end), 0x0605_4B50)
        XCTAssertEqual(u16(zip, end + 10), 2)
        let dirSize = u32(zip, end + 12), dirOffset = u32(zip, end + 16)
        XCTAssertEqual(dirOffset + dirSize, end)
        XCTAssertEqual(u32(zip, dirOffset), 0x0201_4B50)

        // First entry: stored, sizes equal, the bytes are there verbatim.
        XCTAssertEqual(u32(zip, 0), 0x0403_4B50)
        XCTAssertEqual(u16(zip, 8), 0)
        XCTAssertEqual(u32(zip, 18), stored.count)
        XCTAssertEqual(u32(zip, 22), stored.count)
        let nameLength = u16(zip, 26)
        XCTAssertEqual(nameLength, "pulso_días.csv".utf8.count)
        XCTAssertEqual(zip.subdata(in: (30 + nameLength)..<(30 + nameLength + stored.count)), stored)

        // Second entry: deflated, with the CRC of the original bytes.
        let second = 30 + nameLength + stored.count
        XCTAssertEqual(u32(zip, second), 0x0403_4B50)
        XCTAssertEqual(u16(zip, second + 8), 8)
        XCTAssertEqual(u32(zip, second + 14), 0xDF88_F3F8)
        XCTAssertEqual(u32(zip, second + 18), deflated.count)
        XCTAssertEqual(u32(zip, second + 22), plain.count)

        // For checking the file with a real unzip: PULSO_ZIP_OUT=/tmp/x.zip swift test --filter ZipWriterTests
        if let path = ProcessInfo.processInfo.environment["PULSO_ZIP_OUT"] {
            try zip.write(to: URL(fileURLWithPath: path))
        }
    }

    func testCompressionThatDoesNotHelpIsStored() {
        let tiny = Data("a".utf8)
        let zip = ZipWriter.archive([.init(name: "a.txt", data: tiny, deflated: Data([0x4B, 0x04, 0x00]))])
        XCTAssertEqual(u16(zip, 8), 0)
        XCTAssertEqual(u32(zip, 18), 1)
    }
}
