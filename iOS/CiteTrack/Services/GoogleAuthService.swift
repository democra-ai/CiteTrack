import Foundation
import UIKit
import AuthenticationServices
import CryptoKit
import Security
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

// MARK: - Keychain (session bearer token)
/// The bearer token is a full-account credential, so it lives in the Keychain —
/// never UserDefaults (plaintext plist, included in backups). `ThisDeviceOnly`
/// keeps it out of iCloud/device-transfer backups; `AfterFirstUnlock` lets the
/// fire-and-forget sign-out revoke run from the background.
enum AuthTokenStore {
    private static let service = "ai.democra.citetrack.auth"
    private static let account = "session_bearer_token"

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ token: String) {
        var q = baseQuery()
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}

// MARK: - Google Auth Service
/// Handles the app's sign-in session (Google, Apple). Google sign-in resolves in
/// priority order: native GoogleSignIn SDK (when a GIDClientID is configured) →
/// web OAuth through our own auth service (auth.democra.ai, when its Google
/// provider is configured) → DEBUG-only mock.
public final class GoogleAuthService: NSObject, ObservableObject {
    public static let shared = GoogleAuthService()

    @Published public var currentUser: GoogleUser? = nil
    @Published public var isSignedIn: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    /// Whether auth.democra.ai has its Google provider configured (probed at launch;
    /// cached so the button state is stable across launches). When this flips on
    /// server-side, the Google button appears without an app update.
    @Published public var serverGoogleAvailable: Bool = false

    private let persistenceKey = "CiteTrack_GoogleUser_v1"
    /// Legacy location; migrated into the Keychain on first launch after upgrade.
    private let legacyBearerTokenKey = "CiteTrack_AuthBearerToken_v1"
    private let serverGoogleKey = "CiteTrack_ServerGoogleAvailable_v1"
    private static let authBase = URL(string: "https://auth.democra.ai")!
    private static let appScheme = "citetrack"
    private var webAuthSession: ASWebAuthenticationSession?
    private var pendingOAuthState: String?
    private var pendingCodeVerifier: String?

    private override init() {
        super.init()
        serverGoogleAvailable = UserDefaults.standard.bool(forKey: serverGoogleKey)
        migrateLegacyBearerToken()
        restorePersistedUser()
        #if canImport(GoogleSignIn)
        if Self.hasGIDClientID {
            restorePreviousSession()
        }
        #endif
        probeServerProviders()
    }

    /// One-time move of any pre-Keychain token out of UserDefaults.
    private func migrateLegacyBearerToken() {
        guard let legacy = UserDefaults.standard.string(forKey: legacyBearerTokenKey) else { return }
        AuthTokenStore.save(legacy)
        UserDefaults.standard.removeObject(forKey: legacyBearerTokenKey)
    }

    /// Check whether GIDClientID is configured in Info.plist before touching the SDK
    static var hasGIDClientID: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty else {
            return false
        }
        return true
    }

    /// Whether real Google Sign-In is wired up (native SDK or via our auth service).
    /// When false, the Agent features stay locked in Release (no silent mock session);
    /// DEBUG builds may use a mock for testing.
    public static var isConfigured: Bool { hasGIDClientID || shared.serverGoogleAvailable }

    #if DEBUG
    /// Dev-only mock session, used on simulators / when no OAuth client is configured.
    private func signInMockUser() {
        let mock = GoogleUser(
            id: "dev_mock_user",
            email: "researcher@university.edu",
            displayName: "Demo Researcher",
            photoURL: nil
        )
        currentUser = mock
        isSignedIn = true
        persist(mock)
    }
    #endif

    /// Shown when the user taps sign-in but no OAuth client is configured (Release).
    private func reportNotConfigured() {
        isLoading = false
        errorMessage = NSLocalizedString(
            "google_signin_unavailable",
            value: "Google Sign-In is temporarily unavailable. Please try again later.",
            comment: "Shown when the Google OAuth client is not yet configured"
        )
    }

    // MARK: - Sign In

    public func signIn(presenting viewController: UIViewController) {
        errorMessage = nil

        #if canImport(GoogleSignIn)
        guard Self.hasGIDClientID else {
            // No native OAuth client — try the web flow via our auth service.
            signInFallback()
            return
        }
        isLoading = true
        GIDSignIn.sharedInstance.signIn(withPresenting: viewController) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error as NSError?,
                   !(error.domain == "com.google.GIDSignIn" && error.code == -5) {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                if let user = result?.user {
                    self?.handleGIDUser(user)
                }
            }
        }
        #else
        // GoogleSignIn SDK not linked — try the web flow via our auth service.
        signInFallback()
        #endif
    }

    /// No native GIDClientID: web OAuth through auth.democra.ai when its Google
    /// provider is live; otherwise DEBUG-only mock / a clear "unavailable" error.
    private func signInFallback() {
        if serverGoogleAvailable { signInGoogleWeb(); return }
        #if DEBUG
        signInMockUser()
        #else
        reportNotConfigured()
        #endif
    }

    // MARK: - Web OAuth via our auth service (auth.democra.ai)

    /// Ask the auth service which providers are configured; the Google button
    /// follows this, so enabling Google server-side lights it up in the shipped app.
    private func probeServerProviders() {
        let url = Self.authBase.appendingPathComponent("providers")
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let providers = json["providers"] as? [String: Bool]
            else { return }
            DispatchQueue.main.async {
                self.serverGoogleAvailable = providers["google"] ?? false
                UserDefaults.standard.set(self.serverGoogleAvailable, forKey: self.serverGoogleKey)
            }
        }.resume()
    }

    // MARK: PKCE helpers

    private static func randomURLSafe(_ byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Google sign-in through our own auth service — no Google SDK, no GIDClientID
    /// in the app. ASWebAuthenticationSession → auth.democra.ai/mobile/oauth/start
    /// (server holds the Google client) → citetrack://auth?code=…&state=… → the code
    /// is redeemed over POST with the PKCE verifier, so the session token never
    /// travels in a URL and an intercepted code is useless without the verifier.
    private func signInGoogleWeb() {
        let state = Self.randomURLSafe(16)
        let verifier = Self.randomURLSafe(64)
        pendingOAuthState = state
        pendingCodeVerifier = verifier

        var comps = URLComponents(url: Self.authBase.appendingPathComponent("mobile/oauth/start"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "scheme", value: Self.appScheme),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
        ]

        isLoading = true
        let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: Self.appScheme) { [weak self] callbackURL, error in
            guard let self else { return }
            DispatchQueue.main.async {
                // Consume the one-shot flow state on EVERY exit path (cancel, error,
                // mismatch, success) — the nonce and verifier are single-use.
                self.webAuthSession = nil
                let expectedState = self.pendingOAuthState
                let verifier = self.pendingCodeVerifier
                self.pendingOAuthState = nil
                self.pendingCodeVerifier = nil

                if let asError = error as? ASWebAuthenticationSessionError, asError.code == .canceledLogin {
                    self.isLoading = false
                    return
                }
                guard let callbackURL,
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
                else {
                    self.isLoading = false
                    self.errorMessage = error?.localizedDescription ?? "Sign-in was not completed."
                    return
                }
                let value = { (name: String) in items.first(where: { $0.name == name })?.value }
                guard let expectedState, value("state") == expectedState else {
                    self.isLoading = false
                    self.errorMessage = "Sign-in state mismatch. Please try again."
                    return
                }
                guard let code = value("code"), !code.isEmpty, let verifier else {
                    self.isLoading = false
                    self.errorMessage = "Sign-in failed (\(value("error") ?? "no session")). Please try again."
                    return
                }
                self.exchangeCodeForToken(code: code, verifier: verifier)
            }
        }
        session.presentationContextProvider = self
        // Ephemeral: nothing from this flow persists into the shared Safari cookie jar.
        session.prefersEphemeralWebBrowserSession = true
        webAuthSession = session
        session.start()
    }

    /// Redeem the single-use code for the bearer token (POST body — never a URL).
    private func exchangeCodeForToken(code: String, verifier: String) {
        var req = URLRequest(url: Self.authBase.appendingPathComponent("mobile/oauth/exchange"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code, "code_verifier": verifier])

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["token"] as? String, !token.isEmpty
            else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error?.localizedDescription ?? "Sign-in could not be completed. Please try again."
                }
                return
            }
            self.fetchSessionUser(bearerToken: token)
        }.resume()
    }

    /// Fetch the profile with the bearer token and establish the session.
    private func fetchSessionUser(bearerToken: String) {
        var req = URLRequest(url: Self.authBase.appendingPathComponent("api/auth/get-session"))
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let userDict = json["user"] as? [String: Any],
                      let id = userDict["id"] as? String
                else {
                    self.errorMessage = error?.localizedDescription ?? "Could not load your profile. Please try again."
                    return
                }
                let user = GoogleUser(
                    id: id,
                    email: (userDict["email"] as? String) ?? "",
                    displayName: (userDict["name"] as? String) ?? (userDict["email"] as? String) ?? "",
                    photoURL: (userDict["image"] as? String).flatMap { URL(string: $0) }
                )
                AuthTokenStore.save(bearerToken)
                self.errorMessage = nil
                self.currentUser = user
                self.isSignedIn = true
                self.persist(user)
            }
        }.resume()
    }

    // MARK: - Sign In with Apple
    /// Establishes the shared session from a successful Apple authorization. Apple only
    /// returns email + full name on the FIRST authorization, so we fall back to any
    /// previously persisted values on subsequent sign-ins. Reuses the GoogleUser model
    /// as the app's generic "signed-in user" so the gate + every consumer works unchanged.
    public func handleAppleSignIn(_ authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else {
            errorMessage = NSLocalizedString("apple_signin_failed", value: "Apple Sign-In failed. Please try again.", comment: "")
            return
        }
        let name = [cred.fullName?.givenName, cred.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        let user = GoogleUser(
            id: cred.user,
            email: cred.email ?? currentUser?.email ?? "",
            displayName: name.isEmpty ? (currentUser?.displayName ?? "CiteTrack") : name,
            photoURL: nil
        )
        errorMessage = nil
        currentUser = user
        isSignedIn = true
        persist(user)
    }

    /// Apple flow error handling — silent on user cancel, message otherwise.
    public func handleAppleError(_ error: Error) {
        isLoading = false
        if let asError = error as? ASAuthorizationError, asError.code == .canceled { return }
        errorMessage = error.localizedDescription
    }

    // MARK: - Sign Out

    public func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        // Revoke the server session too (fire-and-forget) when one exists.
        if let token = AuthTokenStore.read() {
            var req = URLRequest(url: Self.authBase.appendingPathComponent("api/auth/sign-out"))
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req).resume()
            AuthTokenStore.delete()
        }
        currentUser = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }

    // MARK: - URL Handling (required for Google OAuth redirect)

    @discardableResult
    public func handle(_ url: URL) -> Bool {
        #if canImport(GoogleSignIn)
        return GIDSignIn.sharedInstance.handle(url)
        #else
        return false
        #endif
    }

    // MARK: - Private

    #if canImport(GoogleSignIn)
    private func restorePreviousSession() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
            guard let user = user else { return }
            DispatchQueue.main.async { self?.handleGIDUser(user) }
        }
    }

    private func handleGIDUser(_ gidUser: GIDGoogleUser) {
        let profile = gidUser.profile
        let user = GoogleUser(
            id: gidUser.userID ?? UUID().uuidString,
            email: profile?.email ?? "",
            displayName: profile?.name ?? "",
            photoURL: profile?.imageURL(withDimension: 80)
        )
        currentUser = user
        isSignedIn = true
        persist(user)
    }
    #endif

    private func restorePersistedUser() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let user = try? JSONDecoder().decode(GoogleUser.self, from: data)
        else { return }
        #if !DEBUG
        // Never let a stale dev-mock session survive into a production build.
        if user.id == "dev_mock_user" {
            UserDefaults.standard.removeObject(forKey: persistenceKey)
            return
        }
        #endif
        currentUser = user
        isSignedIn = true
    }

    private func persist(_ user: GoogleUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }
}

// MARK: - Presentation anchor for ASWebAuthenticationSession
extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - Google User Model

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

    /// Two-letter initials for avatar placeholder
    public var initials: String {
        displayName
            .components(separatedBy: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }
}
