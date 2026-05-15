import Foundation

/// Cloudflare Access service-token credentials for the citetrack-api Worker.
///
/// IMPORTANT:
/// - These credentials authenticate the iOS app to the analysis API.
/// - The token belongs to a `non_identity` Access policy on the
///   `citetrack-api.democra.ai` app.
/// - Rotate via the Cloudflare dashboard (Zero Trust → Access → Service Auth) if
///   the file is ever leaked. After rotation, replace the values below and ship
///   a new build.
/// - The values can also be overridden at runtime via:
///     - Info.plist keys `CFAccessClientId` / `CFAccessClientSecret`
///     - Environment variables `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET`
///   This lets debug builds or CI use different credentials without touching
///   source.
public enum CiteTrackAPIConfig {
    /// API base URL. Override via Info.plist `CiteTrackAPIBaseURL` if needed.
    public static var baseURL: URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "CiteTrackAPIBaseURL") as? String,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://citetrack-api.democra.ai")!
    }

    /// Service-token client id (`<id>.access`).
    public static var clientId: String {
        if let v = ProcessInfo.processInfo.environment["CF_ACCESS_CLIENT_ID"], !v.isEmpty {
            return v
        }
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFAccessClientId") as? String, !v.isEmpty {
            return v
        }
        return defaultClientId
    }

    /// Service-token client secret.
    public static var clientSecret: String {
        if let v = ProcessInfo.processInfo.environment["CF_ACCESS_CLIENT_SECRET"], !v.isEmpty {
            return v
        }
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFAccessClientSecret") as? String, !v.isEmpty {
            return v
        }
        return defaultClientSecret
    }

    // Compile-time defaults (the only place to update for a baseline ship).
    private static let defaultClientId =
        "3b36fc5799f14e56ba31315c5d43bbfa.access"
    private static let defaultClientSecret =
        "b8ce177a80ab4c2a4190d8b23655a92e8a008d1a8d9a5448ae4320b973290b73"
}
