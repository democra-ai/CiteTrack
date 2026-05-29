import SwiftUI
import AppKit

// MARK: - Google Sign-In View (macOS)
// SwiftUI sign-in screen mirroring the iOS gate, hosted in a standalone window
// (the macOS app is a status-bar/AppKit app). Calls GoogleAuthService.signIn().
struct GoogleSignInView: View {
    @ObservedObject private var auth = GoogleAuthService.shared
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 36)

            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 54, weight: .thin))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .padding(.bottom, 18)

            VStack(spacing: 8) {
                Text("Sign in to CiteTrack")
                    .font(.title2).fontWeight(.bold)
                Text("Sign in with Google to unlock citation insights, impact scoring, and cross-device sync.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 44)
            }

            Spacer().frame(height: 26)

            VStack(alignment: .leading, spacing: 12) {
                featureRow("quote.opening", "Read verbatim citation sentences")
                featureRow("tag", "Understand citation intent (method / background / result)")
                featureRow("checkmark.seal", "Score your academic impact")
                featureRow("icloud.and.arrow.up", "Sync insights across your devices")
            }
            .padding(.horizontal, 52)

            Spacer().frame(height: 30)

            if auth.isLoading {
                ProgressView().padding()
            } else {
                Button(action: { auth.signIn() }) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4).fill(Color.white).frame(width: 28, height: 28)
                            Text("G")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                        }
                        Text("Continue with Google")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 280, height: 48)
                    .background(Color(red: 0.26, green: 0.52, blue: 0.96))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            if let err = auth.errorMessage {
                Text(err)
                    .font(.caption).foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40).padding(.top, 8)
            }

            Spacer().frame(height: 16)

            Button("Maybe later") { onClose?() }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer().frame(height: 28)
        }
        .frame(width: 460, height: 580)
        .onChange(of: auth.isSignedIn) { signed in
            if signed { onClose?() }
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.accentColor)
                .frame(width: 22, alignment: .center)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Window host
/// Presents the SwiftUI sign-in view in a standalone window from the AppKit app.
final class SignInWindowController {
    static let shared = SignInWindowController()
    private var window: NSWindow?

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: GoogleSignInView(onClose: { [weak self] in self?.close() }))
        let w = NSWindow(contentViewController: host)
        w.title = "Sign in to CiteTrack"
        w.styleMask = [.titled, .closable]
        w.setContentSize(NSSize(width: 460, height: 580))
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }
}
