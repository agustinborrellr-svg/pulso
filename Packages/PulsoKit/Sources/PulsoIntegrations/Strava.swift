import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PulsoStore

/// Minimal HTTP seam so the Strava client can be tested without the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error { return cont.resume(throwing: error) }
                cont.resume(returning: (data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
            }.resume()
        }
    }
}

/// The user's own Strava API application (created at strava.com/settings/api). Pulso has no
/// server, so each user brings their own client id / secret; they stay in the iPhone's Keychain.
public struct StravaCredentials: Codable, Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isComplete: Bool { !clientID.isEmpty && !clientSecret.isEmpty }
}

public struct StravaTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    /// Unix seconds.
    public var expiresAt: Int
    public var athleteName: String?
    public var athleteID: Int?

    public func isExpired(now: Int = Int(Date().timeIntervalSince1970)) -> Bool { now >= expiresAt - 120 }
}

public enum StravaError: Error, Equatable, CustomStringConvertible {
    case notConnected
    case http(Int, String)
    case badResponse
    case uploadFailed(String)
    case rateLimited

    public var description: String {
        switch self {
        case .notConnected: return "Strava no está conectado."
        case .http(let code, let msg): return "Strava respondió \(code): \(msg)"
        case .badResponse: return "Respuesta de Strava no válida."
        case .uploadFailed(let m): return "Strava no aceptó el archivo: \(m)"
        case .rateLimited: return "Límite de peticiones de Strava alcanzado; prueba más tarde."
        }
    }
}

/// A Strava activity summary (subset of `SummaryActivity`).
public struct StravaActivity: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public var sport_type: String?
    public var type: String?
    public var start_date: String
    public var elapsed_time: Int
    public var moving_time: Int?
    public var distance: Double?
    public var average_heartrate: Double?
    public var max_heartrate: Double?
    public var kilojoules: Double?
    public var calories: Double?
    public var external_id: String?
    public var device_name: String?
    public var upload_id: Int?

    public var startUnix: Int? {
        let f = ISO8601DateFormatter()
        return f.date(from: start_date).map { Int($0.timeIntervalSince1970) }
    }

    /// As a Pulso workout (source .strava). Uploads made by Pulso itself map back to their workout
    /// through `external_id`, so they're recognised and never imported twice.
    public func asWorkout() -> Workout? {
        guard let start = startUnix, elapsed_time > 0 else { return nil }
        let sport = SportCatalog.fromStrava(sport_type ?? type ?? "Workout")
        // Strava reports kilojoules of work for rides; ~1 kJ of work ≈ 1 kcal burned (gross efficiency ~24 %).
        let kcal = calories ?? kilojoules ?? 0
        var w = Workout(start: start, end: start + elapsed_time, sport: sport.name, source: .strava,
                        avgHR: average_heartrate ?? 0, maxHR: max_heartrate ?? 0, kcal: kcal, notes: name,
                        externalApp: device_name ?? "Strava", distanceMeters: distance.flatMap { $0 > 0 ? $0 : nil })
        w.setExternalID(String(id), for: "strava")
        return w
    }
}

public struct StravaUploadStatus: Codable, Equatable, Sendable {
    public var id: Int
    public var external_id: String?
    public var error: String?
    public var status: String?
    public var activity_id: Int?
}

public final class StravaClient: @unchecked Sendable {
    public static let redirectURI = "pulso://localhost/strava"
    public static let callbackScheme = "pulso"
    public static let scope = "read,activity:read_all,activity:write"

    let transport: HTTPTransport
    public var credentials: StravaCredentials
    public private(set) var tokens: StravaTokens?
    /// Called whenever tokens change (persist them in the Keychain).
    public var onTokens: ((StravaTokens?) -> Void)?

    public init(credentials: StravaCredentials, tokens: StravaTokens?, transport: HTTPTransport = URLSessionTransport()) {
        self.credentials = credentials
        self.tokens = tokens
        self.transport = transport
    }

    public var isConnected: Bool { tokens != nil }

    /// Page to open in an ASWebAuthenticationSession (callback scheme `pulso`).
    public func authorizeURL() -> URL {
        var c = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: Self.scope),
        ]
        return c.url!
    }

    /// Extracts the authorization code from the callback URL (nil if the user declined).
    public static func code(fromCallback url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.contains(where: { $0.name == "error" }) { return nil }
        return items.first { $0.name == "code" }?.value
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.sorted { $0.key < $1.key }.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }

    struct TokenResponse: Decodable {
        struct Athlete: Decodable {
            var id: Int?
            var firstname: String?
            var lastname: String?
        }

        var access_token: String
        var refresh_token: String
        var expires_at: Int
        var athlete: Athlete?
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> StravaTokens {
        var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form(fields.merging(["client_id": credentials.clientID, "client_secret": credentials.clientSecret]) { a, _ in a })
        let (data, status) = try await transport.send(req)
        guard status == 200 else { throw StravaError.http(status, String(decoding: data.prefix(300), as: UTF8.self)) }
        guard let t = try? JSONDecoder().decode(TokenResponse.self, from: data) else { throw StravaError.badResponse }
        let name = [t.athlete?.firstname, t.athlete?.lastname].compactMap { $0 }.joined(separator: " ")
        return StravaTokens(accessToken: t.access_token, refreshToken: t.refresh_token, expiresAt: t.expires_at,
                            athleteName: name.isEmpty ? tokens?.athleteName : name, athleteID: t.athlete?.id ?? tokens?.athleteID)
    }

    public func exchange(code: String) async throws {
        let t = try await tokenRequest(["code": code, "grant_type": "authorization_code"])
        tokens = t
        onTokens?(t)
    }

    /// A valid access token, refreshing it if needed.
    public func accessToken(now: Int = Int(Date().timeIntervalSince1970)) async throws -> String {
        guard let t = tokens else { throw StravaError.notConnected }
        if !t.isExpired(now: now) { return t.accessToken }
        let fresh = try await tokenRequest(["refresh_token": t.refreshToken, "grant_type": "refresh_token"])
        tokens = fresh
        onTokens?(fresh)
        return fresh.accessToken
    }

    public func disconnect() async {
        if let t = tokens {
            var req = URLRequest(url: URL(string: "https://www.strava.com/oauth/deauthorize")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(t.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await transport.send(req)
        }
        tokens = nil
        onTokens?(nil)
    }

    private func authorized(_ url: URL, method: String = "GET") async throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        return req
    }

    private func check(_ data: Data, _ status: Int) throws {
        if status == 429 { throw StravaError.rateLimited }
        if status == 401 { throw StravaError.notConnected }
        guard (200..<300).contains(status) else { throw StravaError.http(status, String(decoding: data.prefix(300), as: UTF8.self)) }
    }

    /// Activities that started after `after` (unix), newest pages first; up to `pages` × 100.
    public func activities(after: Int, pages: Int = 3) async throws -> [StravaActivity] {
        var out: [StravaActivity] = []
        for page in 1...max(1, pages) {
            var c = URLComponents(string: "https://www.strava.com/api/v3/athlete/activities")!
            c.queryItems = [URLQueryItem(name: "after", value: String(after)), URLQueryItem(name: "per_page", value: "100"),
                            URLQueryItem(name: "page", value: String(page))]
            let (data, status) = try await transport.send(try await authorized(c.url!))
            try check(data, status)
            guard let list = try? JSONDecoder().decode([StravaActivity].self, from: data) else { throw StravaError.badResponse }
            out += list
            if list.count < 100 { break }
        }
        return out
    }

    /// Multipart body for POST /uploads.
    static func multipart(boundary: String, fields: [(String, String)], file: [UInt8], filename: String) -> Data {
        var d = Data()
        for (k, v) in fields {
            d.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(k)\"\r\n\r\n\(v)\r\n".utf8))
        }
        d.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        d.append(Data(file))
        d.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return d
    }

    /// The external id Pulso stamps on its uploads (lets imports recognise them).
    public static func externalID(for w: Workout) -> String { "pulso-\(w.start)" }

    /// Uploads a FIT file of the workout; returns the upload id to poll.
    public func upload(_ track: WorkoutTrack, name: String? = nil, description: String? = nil) async throws -> StravaUploadStatus {
        let boundary = "pulso-\(UUID().uuidString)"
        var req = try await authorized(URL(string: "https://www.strava.com/api/v3/uploads")!, method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let w = track.workout
        var fields: [(String, String)] = [("data_type", "fit"), ("external_id", Self.externalID(for: w)),
                                          ("name", name ?? w.sport)]
        let desc = description ?? String(format: "Esfuerzo %.1f · %d kcal · registrado con Pulso", w.strain, Int(w.kcal.rounded()))
        fields.append(("description", desc))
        if ["Elíptica"].contains(w.sport) { fields.append(("trainer", "1")) }
        req.httpBody = Self.multipart(boundary: boundary, fields: fields, file: FITEncoder.encode(track), filename: "pulso-\(w.start).fit")
        let (data, status) = try await transport.send(req)
        try check(data, status)
        guard let s = try? JSONDecoder().decode(StravaUploadStatus.self, from: data) else { throw StravaError.badResponse }
        if let e = s.error, !e.isEmpty { throw StravaError.uploadFailed(e) }
        return s
    }

    public func uploadStatus(id: Int) async throws -> StravaUploadStatus {
        let (data, status) = try await transport.send(try await authorized(URL(string: "https://www.strava.com/api/v3/uploads/\(id)")!))
        try check(data, status)
        guard let s = try? JSONDecoder().decode(StravaUploadStatus.self, from: data) else { throw StravaError.badResponse }
        return s
    }

    /// Uploads and waits (polling) until Strava has created the activity; returns its id.
    /// A duplicate (already on Strava) returns the existing activity id when Strava reports it.
    public func uploadAndWait(_ track: WorkoutTrack, pollEvery: UInt64 = 2_000_000_000, attempts: Int = 15) async throws -> Int {
        var s = try await upload(track)
        for _ in 0..<attempts {
            if let a = s.activity_id { return a }
            if let e = s.error, !e.isEmpty {
                if let dup = Self.duplicateActivityID(e) { return dup }
                throw StravaError.uploadFailed(e)
            }
            try await Task.sleep(nanoseconds: pollEvery)
            s = try await uploadStatus(id: s.id)
        }
        if let a = s.activity_id { return a }
        throw StravaError.uploadFailed(s.status ?? "sin respuesta")
    }

    /// "… duplicate of <a href='/activities/123'>…" → 123
    static func duplicateActivityID(_ error: String) -> Int? {
        guard error.lowercased().contains("duplicate"), let r = error.range(of: "/activities/") else { return nil }
        let digits = error[r.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}
