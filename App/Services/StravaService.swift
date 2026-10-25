import Foundation
import PulsoIntegrations

/// Strava connection: the user's own API app credentials and the OAuth tokens live in the Keychain.
@MainActor
final class StravaService: ObservableObject {
    @Published private(set) var credentials: StravaCredentials
    @Published private(set) var connected: Bool
    @Published private(set) var athleteName: String?
    @Published var status: String?

    private(set) var client: StravaClient

    init() {
        let creds = Keychain.get(StravaCredentials.self, for: "strava.credentials") ?? StravaCredentials(clientID: "", clientSecret: "")
        let tokens = Keychain.get(StravaTokens.self, for: "strava.tokens")
        credentials = creds
        connected = tokens != nil
        athleteName = tokens?.athleteName
        client = StravaClient(credentials: creds, tokens: tokens)
        attachTokenSink()
    }

    private func attachTokenSink() {
        client.onTokens = { [weak self] tokens in
            Keychain.set(tokens, for: "strava.tokens")
            DispatchQueue.main.async {
                self?.connected = tokens != nil
                self?.athleteName = tokens?.athleteName
            }
        }
    }

    func saveCredentials(clientID: String, clientSecret: String) {
        let c = StravaCredentials(clientID: clientID, clientSecret: clientSecret)
        Keychain.set(c, for: "strava.credentials")
        credentials = c
        client = StravaClient(credentials: c, tokens: client.tokens)
        attachTokenSink()
    }

    var authorizeURL: URL { client.authorizeURL() }

    func complete(callback url: URL) async {
        guard let code = StravaClient.code(fromCallback: url) else {
            status = "Has cancelado la conexión con Strava."
            return
        }
        do {
            try await client.exchange(code: code)
            status = "Conectado a Strava" + (client.tokens?.athleteName.map { " como \($0)" } ?? "")
        } catch {
            status = "No se pudo conectar: \(error)"
        }
    }

    func disconnect() async {
        await client.disconnect()
        status = "Strava desconectado"
    }
}
