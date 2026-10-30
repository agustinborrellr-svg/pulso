import XCTest
@testable import WhoopProtocol

final class ProtocolTests: XCTestCase {
    // Real frames captured from WHOOP 5.0 hardware (published by the open-source community).
    static let clientHello: [UInt8] = [0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71, 0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D]
    static let realV18 = "aa01740001003fb12f128066b7760180fc546aeb710056011d0200000000000000002c0481555700ffb063f13d852b853db87ef43d298e803f7a01a100000000000000000051015901db0d6006010c020c00000000000000000000000000000000000000000000000100adb18080000000c8d69bc00000000d27d7e3"
    static let realHistoryEnd = "aa011c00010023d1319102b949596a705d3b000000fdba010010000000000000f269faec"
    static let referenceCommand = "aa010c000001e741" + "23f16a0101000000" + "58e961fc"

    func testChecksumStandardVectors() {
        let digits = Array("123456789".utf8)
        XCTAssertEqual(CRC.crc8(digits), 0xF4)
        XCTAssertEqual(CRC.crc16Modbus(digits), 0x4B37)
        XCTAssertEqual(CRC.crc32(digits), 0xCBF4_3926)
        XCTAssertEqual(CRC.crc16Modbus([0xAA, 0x01, 0x08, 0x00, 0x00, 0x01]), 0x71E6)
        XCTAssertEqual(CRC.crc32([0x23, 0x01, 0x91, 0x01]), 0x8D5C_3E36)
    }

    func testClientHelloIsByteIdentical() {
        XCTAssertEqual(CommandBuilder.gen5ClientHello, Self.clientHello)
        let f = try! Framing.decode(.gen5, Self.clientHello)
        XCTAssertTrue(f.crcOK)
        XCTAssertEqual(f.packetType, .command)
        XCTAssertEqual(f.cmd, Opcode.getHello)
        XCTAssertEqual(f.payload, [0x01])
    }

    func testPublishedReferenceFrameValidates() throws {
        let wire = try XCTUnwrap(Hex.decode(Self.referenceCommand))
        let f = try Framing.decode(.gen5, wire)
        XCTAssertTrue(f.crcOK)
        XCTAssertEqual(f.cmd, 0x6A)
    }

    func testRealV18RecordDecodes() throws {
        let wire = try XCTUnwrap(Hex.decode(Self.realV18))
        let f = try Framing.decode(.gen5, wire)
        XCTAssertTrue(f.crcOK)
        let s = try XCTUnwrap(HistorySample.decodeV18(f))
        XCTAssertEqual(s.unix, 1_783_954_560)
        XCTAssertEqual(s.recordIndex, 24_557_414)
        XCTAssertEqual(s.heartRate, 86)
        XCTAssertEqual(s.rr, [541])
        XCTAssertEqual(s.steps, 378)
        XCTAssertEqual(s.activityClass, 0)
        XCTAssertEqual(s.signalQuality, 255)
        XCTAssertEqual(s.sleepState, 0)
        XCTAssertNil(s.spo2)
        XCTAssertEqual(Double(try XCTUnwrap(s.skinTempC)), 35.47, accuracy: 0.001)
        let g = try XCTUnwrap(s.gravity)
        XCTAssertEqual(Double(g.z), 1.0043, accuracy: 0.001)
        XCTAssertEqual(Double(try XCTUnwrap(s.dynamicAccelG)), 0.1179, accuracy: 0.001)
        XCTAssertTrue(s.signalPoor)
        XCTAssertFalse(s.offWrist)
    }

    func testRealHistoryEndGivesTokenAndAck() throws {
        let wire = try XCTUnwrap(Hex.decode(Self.realHistoryEnd))
        let f = try Framing.decode(.gen5, wire)
        XCTAssertTrue(f.crcOK)
        let m = try XCTUnwrap(OffloadMetadata.decode(f))
        XCTAssertEqual(m.kind, .historyEnd)
        XCTAssertEqual(m.unix, 1_784_236_473)
        XCTAssertEqual(m.trimCursor, 113_405)
        XCTAssertEqual(m.token, [0xFD, 0xBA, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00])

        let builder = CommandBuilder()
        let ack = try XCTUnwrap(builder.historyAck(token: m.token!))
        let af = try Framing.decode(.gen5, ack.bytes)
        XCTAssertTrue(af.crcOK)
        XCTAssertEqual(af.cmd, Opcode.historicalDataResult)
        XCTAssertEqual(Array(af.payload.prefix(9)), [0x01, 0xFD, 0xBA, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00])
    }

    func testDeframerReassemblesFragmentsAndSkipsGarbage() throws {
        let d = Deframer(family: .gen5)
        let v18 = try XCTUnwrap(Hex.decode(Self.realV18))
        var stream: [UInt8] = [0x00, 0xAA, 0x13] + Self.clientHello + v18 + Self.clientHello
        var frames: [Frame] = []
        while !stream.isEmpty {
            let n = min(20, stream.count)
            frames += d.push(Array(stream.prefix(n)))
            stream.removeFirst(n)
        }
        XCTAssertEqual(frames.count, 3)
        XCTAssertTrue(frames.allSatisfy { $0.crcOK })
        XCTAssertEqual(frames[1].version, 18)
    }

    func testOffloadSessionChunksAndCompletes() throws {
        let session = OffloadSession()
        let v18 = try Framing.decode(.gen5, XCTUnwrap(Hex.decode(Self.realV18)))
        let end = try Framing.decode(.gen5, XCTUnwrap(Hex.decode(Self.realHistoryEnd)))
        let complete = try Framing.decode(.gen5, Framing.encode(.gen5, type: 49, seq: 0, cmd: 3, payload: []))
        XCTAssertNil(session.handle(v18))
        XCTAssertNil(session.handle(v18))
        guard case .chunk(let samples, let undecoded, let token, _)? = session.handle(end) else { return XCTFail("expected chunk") }
        XCTAssertEqual(samples.count, 2)
        XCTAssertTrue(undecoded.isEmpty)
        XCTAssertEqual(token.count, 8)
        guard case .complete(let rest, _)? = session.handle(complete) else { return XCTFail("expected complete") }
        XCTAssertTrue(rest.isEmpty)
    }

    func testUndecodedHistoryRecordsTravelWithTheirChunk() throws {
        let session = OffloadSession()
        let unknown = try Framing.decode(.gen5, Framing.encode(.gen5, type: 47, seq: 99, cmd: 0, payload: [1, 2, 3, 4]))
        let end = try Framing.decode(.gen5, XCTUnwrap(Hex.decode(Self.realHistoryEnd)))
        XCTAssertNil(session.handle(unknown))
        guard case .chunk(let samples, let undecoded, _, _)? = session.handle(end) else { return XCTFail("expected chunk") }
        XCTAssertTrue(samples.isEmpty)
        XCTAssertEqual(undecoded, [unknown])
        XCTAssertTrue(session.pendingUndecoded.isEmpty)
    }

    func testCorruptFrameIsIgnoredByOffload() throws {
        var wire = try XCTUnwrap(Hex.decode(Self.realHistoryEnd))
        wire[wire.count - 1] ^= 0xFF
        let f = try Framing.decode(.gen5, wire)
        XCTAssertFalse(f.crcOK)
        XCTAssertNil(OffloadSession().handle(f))
    }

    func testClockPayloadLayout() {
        let date = Date(timeIntervalSince1970: 1_784_000_000.5)
        let p = CommandBuilder.clockPayload(date)
        XCTAssertEqual(p.count, 8)
        XCTAssertEqual(LE.u32(p, 0), 1_784_000_000)
        XCTAssertEqual(LE.u16(p, 4), 16384)
        XCTAssertEqual(Array(p[6...]), [0, 0])
    }

    func testForbiddenOpcodesCannotBeBuilt() {
        let b = CommandBuilder()
        XCTAssertNil(b.frame(25))   // FORCE_TRIM
        XCTAssertNil(b.frame(45))   // ENTER_BLE_DFU
        XCTAssertNil(b.frame(29))   // REBOOT
        XCTAssertNil(b.frame(15))   // FORGET_BONDS
        XCTAssertNil(b.frame(33))   // SET_READ_POINTER
        XCTAssertNil(b.frame(140))  // SET_ADVERTISING_NAME
        XCTAssertNil(b.frame(159))  // LOCK_DEVICE
        XCTAssertNotNil(b.getBattery())
        XCTAssertNotNil(b.getDataRange())
        XCTAssertNotNil(b.setClock())
        XCTAssertNotNil(b.setAlarm(at: Date()))
    }

    func testHapticRepeatByteCountsPulsesAfterTheFirst() throws {
        // NOOP / whoop-rs: body[11] = repetitions after the first pulse, must be < 8.
        for (pulses, want): (UInt8, UInt8) in [(0, 0), (1, 0), (2, 1), (4, 3), (8, 7), (10, 7), (255, 7)] {
            let f = try Framing.decode(.gen5, XCTUnwrap(CommandBuilder().buzz(loops: pulses)).bytes)
            XCTAssertEqual(Array(f.payload.prefix(12)), [0x01, 47, 152, 0, 0, 0, 0, 0, 0, 0, 0, want], "pulses = \(pulses)")
            let h = try Framing.decode(.gen5, XCTUnwrap(CommandBuilder().haptic(effects: [47, 255], loops: pulses)).bytes)
            XCTAssertEqual(Array(h.payload.prefix(12)), [0x01, 47, 251, 0, 0, 0, 0, 0, 0, 0, 0, want])
        }
    }

    func testSendHistoricalDataCarriesExplicitRequestByte() throws {
        let f = try Framing.decode(.gen5, XCTUnwrap(CommandBuilder().sendHistoricalData()).bytes)
        XCTAssertEqual(f.cmd, Opcode.sendHistoricalData)
        XCTAssertEqual(f.payload, [0x00])
    }

    func testGetDataRangeCarriesExplicitRequestByte() throws {
        let f = try Framing.decode(.gen5, XCTUnwrap(CommandBuilder().getDataRange()).bytes)
        XCTAssertEqual(f.cmd, Opcode.getDataRange)
        XCTAssertEqual(f.payload, [0x00])
    }

    func testNegativeSkinTemperatureIsNotMisreadAsHot() throws {
        var wire = try XCTUnwrap(Hex.decode(Self.realV18))
        // inner[65..67] = frame[73..75]: write the -50.00 °C unavailable sentinel, then re-seal the CRC32.
        let inner = Array(wire[8..<(wire.count - 4)])
        var patched = inner
        patched[65] = 0x70; patched[66] = 0xEC   // -5000 LE
        wire.replaceSubrange(8..<(wire.count - 4), with: patched)
        wire.replaceSubrange((wire.count - 4)..., with: LE.bytes(CRC.crc32(patched)))
        let s = try XCTUnwrap(HistorySample.decodeV18(Framing.decode(.gen5, wire)))
        XCTAssertNil(s.skinTempC)
    }

    func testGen5CommandsArePaddedToFourBytes() throws {
        let b = CommandBuilder()
        for frame in [b.getHello(), b.getBattery(), b.sendHistoricalData(), b.toggleRealtimeHR(true), b.setClock(), b.buzz()] {
            let bytes = try XCTUnwrap(frame).bytes
            let f = try Framing.decode(.gen5, bytes)
            XCTAssertTrue(f.crcOK)
            XCTAssertEqual(f.inner.count % 4, 0)
        }
    }

    func testRealtimeDecode() throws {
        var payload = [UInt8](repeating: 0, count: 17)
        // inner = [0x28][0x02][ts@2..6][x][x][hr@8][flag@9][rr@10..]
        let ts = LE.bytes(UInt32(1_789_945_840))
        let inner: [UInt8] = [0x28, 0x02] + ts + [0, 0, 62, 1] + LE.bytes(UInt16(968)) + [0, 0, 0, 0, 0, 0, 0, 0]
        payload = Array(inner[3...])
        let wire = Framing.encode(.gen5, type: inner[0], seq: inner[1], cmd: inner[2], payload: payload)
        let f = try Framing.decode(.gen5, wire)
        let r = try XCTUnwrap(RealtimeHR.decode(f))
        XCTAssertEqual(r.heartRate, 62)
        XCTAssertEqual(r.rr, [968])
        XCTAssertEqual(r.unix, 1_789_945_840)
        XCTAssertTrue(r.valid)

        // No R-R this second (count 0) must not invalidate the heart rate.
        let noRR: [UInt8] = [0x28, 0x02] + ts + [0, 0, 131, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let f2 = try Framing.decode(.gen5, Framing.encode(.gen5, type: noRR[0], seq: noRR[1], cmd: noRR[2], payload: Array(noRR[3...])))
        let r2 = try XCTUnwrap(RealtimeHR.decode(f2))
        XCTAssertEqual(r2.heartRate, 131)
        XCTAssertEqual(r2.rr, [])
        XCTAssertTrue(r2.valid)
        let zero: [UInt8] = [0x28, 0x02] + ts + [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let f3 = try Framing.decode(.gen5, Framing.encode(.gen5, type: zero[0], seq: zero[1], cmd: zero[2], payload: Array(zero[3...])))
        XCTAssertFalse(try XCTUnwrap(RealtimeHR.decode(f3)).valid)
    }

    func testStandardHeartRateMeasurement() {
        // flags: uint8 HR + RR present
        let v: [UInt8] = [0x10, 70] + LE.bytes(UInt16(870)) // 870/1024 s = 850 ms
        let m = StandardHRMeasurement.decode(v)
        XCTAssertEqual(m?.heartRate, 70)
        XCTAssertEqual(m?.rr, [850])
    }

    func testHelloDecode() {
        var body = [UInt8](repeating: 0, count: 104)
        body[0] = 1
        body.replaceSubrange(1..<5, with: LE.bytes(UInt32(730)))
        body[5] = 1
        body.replaceSubrange(6..<10, with: LE.bytes(UInt32(1_790_000_000)))
        let serial = Array("5AG0268206".utf8)
        body.replaceSubrange(14..<(14 + serial.count), with: serial)
        body.replaceSubrange(87..<91, with: LE.bytes(UInt32(82)))
        body[91] = 50; body[92] = 40; body[93] = 1
        body[102] = 1
        let payload: [UInt8] = [7, 1] + body
        let wire = Framing.encode(.gen5, type: 36, seq: 0, cmd: Opcode.getHello, payload: payload)
        let f = try! Framing.decode(.gen5, wire)
        let r = CommandResponse.decode(f)!
        XCTAssertEqual(r.originSeq, 7)
        XCTAssertEqual(r.status, .success)
        let h = HelloInfo.decode(r)!
        XCTAssertEqual(h.serial, "5AG0268206")
        XCTAssertEqual(h.batteryPercent, 73)
        XCTAssertTrue(h.charging)
        XCTAssertEqual(h.strapUnix, 1_790_000_000)
        XCTAssertEqual(h.firmware, "50.40.1")
        XCTAssertTrue(h.wristOn)
        XCTAssertFalse(h.isMG)
    }
}
