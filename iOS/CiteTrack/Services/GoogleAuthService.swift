import Foundation
import UIKit
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
    private static var hasGIDClientID: Bool {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              !clientID.isEmpty else {
            return false
        }
        return true
    }

    // MARK: - Sign In

    public func signIn(presenting viewController: UIViewController) {
        errorMessage = nil

        #if canImport(GoogleSignIn)
        guard Self.hasGIDClientID else {
            // Fall through to mock path when GIDClientID is not configured
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
        // Development fallback when GoogleSignIn SDK is not yet linked
        let mock = GoogleUser(
            id: "dev_mock_user",
            email: "researcher@university.edu",
            displayName: "Demo Researcher",
            photoURL: nil
        )
        currentUser = mock
        isSignedIn = true
        persist(mock)
        #endif
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
