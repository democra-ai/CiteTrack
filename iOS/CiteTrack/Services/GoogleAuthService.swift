import Foundation
import UIKit
import AuthenticationServices
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

// MARK: - Google Auth Service
/// Handles Google Sign-In flow. Only Google sign-in is supported per product requirements.
/// Uses GoogleSignIn-iOS SDK when available; provides a clean mock path for simulators.
public class GoogleAuthService: ObservableObject {
    public static let shared = GoogleAuthService()

    @Published public var currentUser: GoogleUser? = nil
    @Published public var isSignedIn: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private let persistenceKey = "CiteTrack_GoogleUser_v1"

    private init() {
        restorePersistedUser()
        #if canImport(GoogleSignIn)
        if Self.hasGIDClientID {
            restorePreviousSession()
        }
        #endif
    }

    /// Check whether GIDClientID is configured in Info.plist before touching the SDK
    static var hasGIDClientID: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty else {
            return false
        }
        return true
    }

    /// Whether real Google Sign-In is wired up. When false, the Agent features stay
    /// locked in Release (no silent mock session); DEBUG builds may use a mock for testing.
    public static var isConfigured: Bool { hasGIDClientID }

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
            // No OAuth client configured. Mock only in DEBUG; Release locks the feature.
            #if DEBUG
            signInMockUser()
            #else
            reportNotConfigured()
            #endif
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
        // GoogleSignIn SDK not linked: mock only in DEBUG, lock in Release.
        #if DEBUG
        signInMockUser()
        #else
        reportNotConfigured()
        #endif
        #endif
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
