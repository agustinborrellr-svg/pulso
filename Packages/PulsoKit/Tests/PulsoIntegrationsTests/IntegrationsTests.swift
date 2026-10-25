import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif
import WhoopProtocol
import PulsoStore
@testable import PulsoIntegrations

/// Records requests and answers from a queue of canned responses.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    var responses: [(Int, String)]
    var requests: [URLRequest] = []
    let lock = NSLock()

    init(_ responses: [(Int, String)]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        guard !responses.isEmpty else { return (Data(), 500) }
        let r = responses.removeFirst()
        return (Data(r.1.utf8), r.0)
    }
}

final class IntegrationsTests: XCTestCase {
    func track() -> WorkoutTrack {
        var w = Workout(start: 1_790_000_000, end: 1_790_000_600, sport: "Carrera", source: .live, strain: 9.4,
                        avgHR: 150, maxHR: 172, kcal: 140, distanceMeters: 2000)
        w.notes = "Rodaje & series <test>"
        let hr = (0..<600).map { (ts: 1_790_000_000 + $0, bpm: 120 + $0 / 12) }
        return WorkoutTrack(workout: w, heartRate: hr, laps: [1_790_000_300])
    }

    // MARK: FIT

    func testFITCRCProperty() {
        // FIT's CRC-16 (poly 0xA001, init 0): appending the CRC (LE) to a message makes the running CRC zero.
        XCTAssertEqual(FITEncoder.crc([]), 0)
        let msg: [UInt8] = Array("Pulso FIT".utf8)
        let c = FITEncoder.crc(msg)
        XCTAssertEqual(FITEncoder.crc(msg + [UInt8(c & 0xFF), UInt8(c >> 8)]), 0)
    }

    func testFITStructure() {
        let bytes = FITEncoder.encode(track())
        XCTAssertEqual(bytes[0], 14)
        XCTAssertEqual(Array(bytes[8..<12]), Array(".FIT".utf8))
        let dataSize = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16 | Int(bytes[7]) << 24
        XCTAssertEqual(bytes.count, 14 + dataSize + 2)
        XCTAssertEqual(FITEncoder.crc(Array(bytes[0..<14])), 0, "header CRC")
        XCTAssertEqual(FITEncoder.crc(bytes), 0, "file CRC")
        // 600 records of 6 bytes (header + u32 + u8) dominate the size.
        XCTAssertGreaterThan(dataSize, 600 * 6)

        // Walk the records and count message types to make sure the stream is self-consistent.
        var defs: [UInt8: (global: UInt16, size: Int)] = [:]
        var counts: [UInt16: Int] = [:]
        var i = 14
        let end = 14 + dataSize
        while i < end {
            let h = bytes[i]
            let local = h & 0x0F
            if h & 0x40 != 0 {
                let global = UInt16(bytes[i + 3]) | UInt16(bytes[i + 4]) << 8
                let n = Int(bytes[i + 5])
                var size = 0
                for f in 0..<n { size += Int(bytes[i + 6 + f * 3 + 1]) }
                defs[local] = (global, size)
                i += 6 + n * 3
            } else {
                guard let d = defs[local] else { return XCTFail("data before definition at \(i)") }
                counts[d.global, default: 0] += 1
                i += 1 + d.size
            }
        }
        XCTAssertEqual(i, end)
        XCTAssertEqual(counts[0], 1, "file_id")
        XCTAssertEqual(counts[20], 600, "records")
        XCTAssertEqual(counts[19], 2, "laps")
        XCTAssertEqual(counts[18], 1, "session")
        XCTAssertEqual(counts[34], 1, "activity")
        XCTAssertEqual(counts[21], 2, "timer start/stop")
    }

    func testFITWritesFileForPythonCheck() throws {
        // Leaves a sample file for the optional external validation (fitdecode) run by the dev script.
        let dir = ProcessInfo.processInfo.environment["PULSO_ARTIFACTS"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("pulso-test.fit")
        try Data(FITEncoder.encode(track())).write(to: url)
        let tcx = URL(fileURLWithPath: dir).appendingPathComponent("pulso-test.tcx")
        try TCXEncoder.encode(track()).write(to: tcx, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: TCX

    func testTCXIsWellFormed() throws {
        let xml = TCXEncoder.encode(track())
        XCTAssertTrue(xml.contains("<Activity Sport=\"Running\">"))
        XCTAssertTrue(xml.contains("<Id>2026-09-21T"), String(xml.prefix(400)))
        XCTAssertEqual(xml.components(separatedBy: "<Trackpoint>").count - 1, 600)
        XCTAssertEqual(xml.components(separatedBy: "<Lap ").count - 1, 2)
        XCTAssertTrue(xml.contains("Rodaje &amp; series &lt;test&gt;"))
        final class Counter: NSObject, XMLParserDelegate {
            var trackpoints = 0
            func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
                if elementName == "Trackpoint" { trackpoints += 1 }
            }
        }
        let parser = XMLParser(data: Data(xml.utf8))
        let counter = Counter()
        parser.delegate = counter
        XCTAssertTrue(parser.parse(), "TCX must be well-formed XML: \(String(describing: parser.parserError))")
        XCTAssertEqual(counter.trackpoints, 600)
    }

    // MARK: Sports

    func testSportMapping() {
        XCTAssertEqual(SportCatalog.fromStrava("TrailRun").name, "Carrera")
        XCTAssertEqual(SportCatalog.fromStrava("GravelRide").name, "Ciclismo")
        XCTAssertEqual(SportCatalog.fromStrava("Padel").name, "Pádel")
        XCTAssertEqual(SportCatalog.fromStrava("SomethingNew").name, "Actividad")
        XCTAssertEqual(SportCatalog.stravaType("Fuerza"), "WeightTraining")
        XCTAssertEqual(SportCatalog.named("Ciclismo").fitSport, 2)
        XCTAssertEqual(SportCatalog.fromHealth("yoga").name, "Yoga")
        XCTAssertEqual(Set(SportCatalog.names).count, SportCatalog.all.count, "unique names")
    }

    // MARK: HR broadcast

    func testHeartRateBroadcastRoundTrip() {
        let bytes = HeartRateBroadcast.measurement(heartRate: 142, rrMilliseconds: [420, 425, 5000])
        let m = StandardHRMeasurement.decode(bytes)
        XCTAssertEqual(m?.heartRate, 142)
        XCTAssertEqual(m?.rr, [420, 425], "out-of-range RR dropped")
        XCTAssertEqual(bytes[0] & 0x06, 0x06, "sensor contact detected")
        let plain = HeartRateBroadcast.measurement(heartRate: 61)
        XCTAssertEqual(plain, [0x06, 61])
        let big = HeartRateBroadcast.measurement(heartRate: 300)
        XCTAssertEqual(StandardHRMeasurement.decode(big)?.heartRate, 300)
    }

    // MARK: Strava

    func testAuthorizeURLAndCallback() {
        let c = StravaClient(credentials: StravaCredentials(clientID: " 12345 ", clientSecret: "s"), tokens: nil, transport: MockTransport([]))
        let url = c.authorizeURL().absoluteString
        XCTAssertTrue(url.hasPrefix("https://www.strava.com/oauth/authorize?"))
        XCTAssertTrue(url.contains("client_id=12345"))
        XCTAssertTrue(url.contains("redirect_uri=pulso://localhost/strava"))
        XCTAssertTrue(url.contains("activity:write"))
        XCTAssertEqual(StravaClient.code(fromCallback: URL(string: "pulso://localhost/strava?state=&code=abc123&scope=read")!), "abc123")
        XCTAssertNil(StravaClient.code(fromCallback: URL(string: "pulso://localhost/strava?state=&error=access_denied")!))
    }

    func testTokenExchangeRefreshAndActivities() async throws {
        let mock = MockTransport([
            (200, #"{"token_type":"Bearer","expires_at":100,"expires_in":21600,"refresh_token":"r1","access_token":"a1","athlete":{"id":7,"firstname":"Gus","lastname":"B"}}"#),
            (200, #"{"token_type":"Bearer","expires_at":99999999999,"refresh_token":"r2","access_token":"a2"}"#),
            (200, #"[{"id":111,"name":"Morning Ride","sport_type":"Ride","start_date":"2026-10-20T07:00:00Z","elapsed_time":3600,"moving_time":3400,"distance":30123.4,"average_heartrate":141.2,"max_heartrate":170,"kilojoules":650,"external_id":"garmin_123.fit","device_name":"Garmin Edge 540"}]"#),
        ])
        let c = StravaClient(credentials: StravaCredentials(clientID: "1", clientSecret: "sec"), tokens: nil, transport: mock)
        var saved: [StravaTokens?] = []
        c.onTokens = { saved.append($0) }
        try await c.exchange(code: "xyz")
        XCTAssertEqual(c.tokens?.athleteName, "Gus B")
        let body = String(decoding: mock.requests[0].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("code=xyz") && body.contains("client_secret=sec") && body.contains("grant_type=authorization_code"), body)

        // Expired (expires_at = 100) → refresh happens transparently before the API call.
        let acts = try await c.activities(after: 0)
        XCTAssertEqual(mock.requests[1].url?.absoluteString, "https://www.strava.com/oauth/token")
        XCTAssertTrue(String(decoding: mock.requests[1].httpBody ?? Data(), as: UTF8.self).contains("refresh_token=r1"))
        XCTAssertEqual(mock.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer a2")
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.last??.athleteName, "Gus B", "name kept across refresh")
        XCTAssertEqual(acts.count, 1)
        let w = acts[0].asWorkout()!
        XCTAssertEqual(w.sport, "Ciclismo")
        XCTAssertEqual(w.end - w.start, 3600)
        XCTAssertEqual(w.externalID("strava"), "111")
        XCTAssertEqual(w.distanceMeters ?? 0, 30123.4, accuracy: 0.01)
        XCTAssertEqual(w.kcal, 650)
        XCTAssertEqual(w.externalApp, "Garmin Edge 540")
        XCTAssertEqual(w.source, .strava)
    }

    func testUploadPollsUntilActivity() async throws {
        let mock = MockTransport([
            (201, #"{"id":555,"id_str":"555","external_id":"pulso-1790000000","error":null,"status":"Your activity is still being processed.","activity_id":null}"#),
            (200, #"{"id":555,"external_id":"pulso-1790000000","error":null,"status":"Your activity is ready.","activity_id":98765}"#),
        ])
        let c = StravaClient(credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
                             tokens: StravaTokens(accessToken: "tok", refreshToken: "r", expiresAt: Int.max), transport: mock)
        let id = try await c.uploadAndWait(track(), pollEvery: 1_000_000)
        XCTAssertEqual(id, 98765)
        let req = mock.requests[0]
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertTrue(req.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let body = req.httpBody ?? Data()
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"data_type\"\r\n\r\nfit"))
        XCTAssertTrue(text.contains("name=\"external_id\"\r\n\r\npulso-1790000000"))
        XCTAssertTrue(text.contains("filename=\"pulso-1790000000.fit\""))
        XCTAssertNotNil(body.range(of: Data(".FIT".utf8)), "binary FIT embedded")
        XCTAssertEqual(mock.requests[1].url?.absoluteString, "https://www.strava.com/api/v3/uploads/555")
    }

    func testDuplicateUploadAndErrors() async throws {
        XCTAssertEqual(StravaClient.duplicateActivityID("pulso-1.fit duplicate of <a href='/activities/4242' target='_blank'>Run</a>"), 4242)
        XCTAssertNil(StravaClient.duplicateActivityID("Improperly formatted data."))
        let mock = MockTransport([(201, #"{"id":1,"error":"pulso-1.fit duplicate of <a href='/activities/4242'>x</a>","status":"There was an error processing your activity.","activity_id":null}"#)])
        let c = StravaClient(credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
                             tokens: StravaTokens(accessToken: "t", refreshToken: "r", expiresAt: Int.max), transport: mock)
        do {
            _ = try await c.upload(track())
            XCTFail("an error in the upload response must throw")
        } catch let e as StravaError {
            if case .uploadFailed(let m) = e { XCTAssertTrue(m.contains("duplicate")) } else { XCTFail("\(e)") }
        }
        let limited = StravaClient(credentials: StravaCredentials(clientID: "1", clientSecret: "s"),
                                   tokens: StravaTokens(accessToken: "t", refreshToken: "r", expiresAt: Int.max),
                                   transport: MockTransport([(429, "{}")]))
        do {
            _ = try await limited.activities(after: 0)
            XCTFail("429 must throw")
        } catch let e as StravaError {
            XCTAssertEqual(e, .rateLimited)
        }
        let none = StravaClient(credentials: StravaCredentials(clientID: "1", clientSecret: "s"), tokens: nil, transport: MockTransport([]))
        do {
            _ = try await none.activities(after: 0)
            XCTFail()
        } catch let e as StravaError {
            XCTAssertEqual(e, .notConnected)
        }
    }

    func testTrackFromSamplesPrefersStoredSeconds() {
        let w = Workout(start: 100, end: 110, sport: "Carrera", source: .live)
        let samples = (100..<105).map { Sample(ts: $0, hr: 140, rr: []) } + [Sample(ts: 106, hr: 150, rr: [], off: true)]
        let live = (100..<110).map { (ts: $0, hr: 130) }
        let t = WorkoutTrack.from(workout: w, samples: samples, live: live)
        XCTAssertEqual(t.heartRate.count, 10)
        XCTAssertEqual(t.heartRate.first?.bpm, 140)
        XCTAssertEqual(t.heartRate.last?.bpm, 130)
        XCTAssertEqual(t.heartRate.first { $0.ts == 106 }?.bpm, 130, "off-wrist second ignored")
    }
}
