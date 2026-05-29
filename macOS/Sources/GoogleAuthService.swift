import Foundation
import AppKit
import AuthenticationServices
import CryptoKit
import Combine
import Security

// MARK: - Google User
// Mirrors the iOS GoogleUser so the UI/persistence behave identically across platforms.
public struct GoogleUser: Codable, Identifiable {
    public let id: String
    public let email: String
    public let displayName: String
    public let photoURL: URL?

    public init(id: String, email: String, displayName: String, photoURL: URL?) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
    }

    /// Two-letter initials for avatar placeholder.
    public var initials: String {
        let base = displayName.isEmpty ? email : displayName
        return base
            .components(separatedBy: CharacterSet(charactersIn: " @."))
            .filter { !$0.isEmpty }
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }
}

// MARK: - Google Auth Service (macOS)
//
// macOS has no GoogleSignIn SDK, so sign-in uses ASWebAuthenticationSession with a
// standard PKCE OAuth 2.0 flow against Google. It activates when an OAuth client id
// is configured (Info.plist key "GIDClientID", same key iOS uses); otherwise it
// falls back to a dev mock user — exactly mirroring the iOS service's behavior when
// GIDClientID is absent. This keeps the whole login UI/flow complete and makes real
// sign-in a config-only change (add a macOS/Desktop OAuth client id to Info.plist).
public final class GoogleAuthService: NSObject, ObservableObject {
    public static let shared = GoogleAuthService()

    @Published public var currentUser: GoogleUser? = nil
    @Published public var isSignedIn: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private let persistenceKey = "CiteTrack_GoogleUser_v1"
    private var webAuthSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
        restorePersistedUser()
    }

    /// OAuth client id, read from Info.plist ("GIDClientID"). Nil → mock path.
    private var clientID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !id.isEmpty else { return nil }
        return id
    }

    /// Reversed-client-id custom scheme used as the OAuth redirect for installed apps.
    private var redirectScheme: String? {
        guard let id = clientID, id.hasSuffix(".apps.googleusercontent.com") else { return nil }
        let prefix = id.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    // MARK: - Sign In

    public func signIn() {
        errorMessage = nil

        guard let clientID = clientID, let scheme = redirectScheme else {
            // Mock fallback (mirrors iOS when no client id is configured).
            let mock = GoogleUser(
                id: "dev_mock_user",
                email: "researcher@university.edu",
                displayName: "Demo Researcher",
                photoURL: nil
            )
            currentUser = mock
            isSignedIn = true
            persist(mock)
            return
        }

        isLoading = true
        let verifier = Self.randomURLSafe(64)
        let challenge = Self.codeChallenge(for: verifier)
        let redirectURI = "\(scheme):/oauth2redirect"

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let authURL = comps.url else {
            isLoading = false
            errorMessage = "Could not build the sign-in URL."
            return
        }

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { [weak self] callbackURL, error in
            guard let self else { return }
            if let asError = error as? ASWebAuthenticationSessionError, asError.code == .canceledLogin {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            guard let callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value
            else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error?.localizedDescription ?? "Sign-in was not completed."
                }
                return
            }
            self.exchangeCode(code, clientID: clientID, redirectURI: redirectURI, verifier: verifier)
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.webAuthSession = session
        session.start()
    }

    // MARK: - Sign Out

    public func signOut() {
        currentUser = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    // MARK: - OAuth token + userinfo

    private func exchangeCode(_ code: String, clientID: String, redirectURI: String, verifier: String) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        req.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String
            else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error?.localizedDescription ?? "Token exchange failed."
                }
                return
            }
            self.fetchUserInfo(accessToken: accessToken)
        }.resume()
    }

    private func fetchUserInfo(accessToken: String) {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async { self.isLoading = false }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                DispatchQueue.main.async { self.errorMessage = error?.localizedDescription ?? "Could not load profile." }
                return
            }
            let user = GoogleUser(
                id: (json["sub"] as? String) ?? UUID().uuidString,
                email: (json["email"] as? String) ?? "",
                displayName: (json["name"] as? String) ?? (json["email"] as? String) ?? "",
                photoURL: (json["picture"] as? String).flatMap { URL(string: $0) }
            )
            DispatchQueue.main.async {
                self.currentUser = user
                self.isSignedIn = true
                self.persist(user)
            }
        }.resume()
    }

    // MARK: - Persistence

    private func restorePersistedUser() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let user = try? JSONDecoder().decode(GoogleUser.self, from: data)
        else { return }
        currentUser = user
        isSignedIn = true
    }

    private func persist(_ user: GoogleUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    // MARK: - PKCE helpers

    private static func randomURLSafe(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Presentation anchor for ASWebAuthenticationSession
extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "+&=?/")
        return cs
    }()
}
