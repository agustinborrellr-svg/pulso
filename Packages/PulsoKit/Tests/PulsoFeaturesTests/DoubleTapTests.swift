import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PulsoFeatures

final class DoubleTapTests: XCTestCase {
    func testRoutingNewActions() {
        XCTAssertEqual(GestureRouter.route(action: .webhook, alarmActive: false, workoutActive: false), .webhook)
        XCTAssertEqual(GestureRouter.route(action: .webhook, alarmActive: true, workoutActive: false), .alarm, "a ringing alarm always wins")
        XCTAssertEqual(GestureRouter.route(action: .scan, alarmActive: false, workoutActive: true), .scan)
        XCTAssertEqual(GestureRouter.route(action: .speakStatus, alarmActive: false, workoutActive: false), .speakStatus)
        XCTAssertEqual(GestureRouter.route(action: .shortcut, alarmActive: false, workoutActive: false), .shortcut)
    }

    func testWebhookRequest() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let r = try XCTUnwrap(DoubleTapWebhook.request(url: " https://casa.local:8123/api/webhook/abrir-puerta ", method: .post, heartRate: 72, at: date))
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.url?.host, "casa.local")
        let body = try XCTUnwrap(r.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["event"] as? String, "double_tap")
        XCTAssertEqual(body["heart_rate"] as? Int, 72)
        XCTAssertEqual(body["ts"] as? Int, 1_790_000_000)
        let get = try XCTUnwrap(DoubleTapWebhook.request(url: "http://192.168.1.10/luz", method: .get, heartRate: nil, at: date))
        XCTAssertNil(get.httpBody)
        XCTAssertNil(DoubleTapWebhook.request(url: "file:///etc/passwd", method: .get, heartRate: nil, at: date))
        XCTAssertNil(DoubleTapWebhook.request(url: "", method: .post, heartRate: nil, at: date))
        XCTAssertEqual(DoubleTapWebhook.shortcutURL(name: "Abrir puerta")?.absoluteString, "shortcuts://run-shortcut?name=Abrir%20puerta")
        XCTAssertNil(DoubleTapWebhook.shortcutURL(name: "  "))
    }

    func testOldSettingsStillDecode() throws {
        let old = #"{"doubleTap":"lap","quickSport":"Carrera","hrBroadcast":false,"voiceCues":true}"#
        let s = try JSONDecoder().decode(FeatureSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.doubleTap, .lap)
        XCTAssertEqual(s.tapURL, "")
        XCTAssertEqual(s.tapMethod, .post)
        var n = s
        n.doubleTap = .webhook
        n.tapURL = "https://x.y/z"
        let back = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(n))
        XCTAssertEqual(back, n)
    }
}
