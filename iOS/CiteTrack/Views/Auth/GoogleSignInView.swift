import SwiftUI

// MARK: - Google Sign-In Gate View
/// Full-screen sign-in sheet. Only Google sign-in is supported.
struct GoogleSignInView: View {
    @StateObject private var auth = GoogleAuthService.shared
    @Environment(\.dismiss) private var dismiss
    var onSignedIn: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Spacer()

                // Hero icon
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(.bottom, 24)

                // Title + subtitle
                VStack(spacing: 8) {
                    Text("signin_headline".localized)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("signin_subtitle".localized)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer().frame(height: 40)

                // Feature highlights
                VStack(alignment: .leading, spacing: 14) {
                    featureRow(icon: "quote.opening", text: "Read verbatim citation sentences")
                    featureRow(icon: "tag", text: "Understand citation intent (method / background / result)")
                    featureRow(icon: "arrow.triangle.branch", text: "Powered by Semantic Scholar — no scraping")
                    featureRow(icon: "icloud.and.arrow.up", text: "Sync insights across your devices")
                }
                .padding(.horizontal, 40)

                Spacer().frame(height: 48)

                // Sign-in button
                if auth.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding()
                } else {
                    GoogleSignInButton { signIn() }
                        .padding(.horizontal, 32)
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }

                Spacer().frame(height: 24)

                Button("signin_maybe_later".localized) { dismiss() }
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .navigationBarHidden(true)
        }
        .onChange(of: auth.isSignedIn) { _, signed in
            if signed {
                onSignedIn?()
                dismiss()
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 22, alignment: .center)
            Text(text)
                .font(.subheadline)
        }
    }

    private func signIn() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var rootVC = scene.windows.first?.rootViewController
        else { return }
        while let presented = rootVC.presentedViewController { rootVC = presented }
        auth.signIn(presenting: rootVC)
    }
}

// MARK: - Google Sign-In Button
/// Styled button that matches Google's brand guidelines.
struct GoogleSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Google "G" monogram
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                    Text("G")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                }
                Text("signin_continue_google".localized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color(red: 0.26, green: 0.52, blue: 0.96))
            .cornerRadius(8)
        }
    }
}

// MARK: - Signed-In User Badge
/// Compact card shown in the nav bar after sign-in.
struct SignedInUserBadge: View {
    let user: GoogleUser
    let onSignOut: () -> Void

    var body: some View {
        Menu {
            Text(user.email).font(.caption)
            Divider()
            Button(role: .destructive, action: onSignOut) {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 30, height: 30)
                Text(user.initials)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Agent Sign-In Gate
/// Reusable wrapper that hard-gates an "Agent" (AI-powered) feature behind Google
/// sign-in. While signed out it shows a clean prompt with a Google sign-in button;
/// once signed in it renders `content`. Because `content` is only built when signed
/// in, any data-loading `.onAppear`/`.task` inside it will not fire until the user
/// has authenticated — exactly the gating the product requires.
struct AgentSignInGate<Content: View>: View {
    @StateObject private var auth = GoogleAuthService.shared
    @State private var showSignIn = false

    let icon: String
    let title: String
    let subtitle: String
    let desc: String
    @ViewBuilder let content: () -> Content

    init(
        icon: String = "sparkles",
        title: String,
        subtitle: String,
        desc: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.desc = desc
        self.content = content
    }

    var body: some View {
        Group {
            if auth.isSignedIn {
                content()
            } else {
                gate
            }
        }
        .sheet(isPresented: $showSignIn) {
            GoogleSignInView()
        }
    }

    private var gate: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 70, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(desc)
                .font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            GoogleSignInButton { showSignIn = true }
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview
#Preview {
    GoogleSignInView()
}
