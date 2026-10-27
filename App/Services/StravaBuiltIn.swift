import Foundation

/// Pulso's own Strava API app, so connecting is one tap. Empty in the repository: the CI build fills it from
/// the STRAVA_CLIENT_ID / STRAVA_CLIENT_SECRET secrets. Without them the user can still enter their own
/// (Conexiones → Strava → Avanzado).
enum StravaBuiltIn {
    static let clientID = ""
    static let clientSecret = ""
}
