import SwiftUI
import AppKit
import Combine

// MARK: - Shared selection state (lets menu items open the window at a section)
final class MainWindowState: ObservableObject {
    static let shared = MainWindowState()
    @Published var section: MacMainWindow.Pane = .scholars
}

// MARK: - Unified main window
// One coherent front-end: a sidebar (Scholars · Charts · Insights · Settings) +
// an account footer, replacing the scattered status-bar entries and floating
// windows. Reuses the existing SwiftUI views (ChartsContentView, SettingsView,
// MacInsightsView) so every section shares one window and one Liquid-Glass style.
struct MacMainWindow: View {
    enum Pane: String, CaseIterable, Identifiable {
        case scholars, charts, insights, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .scholars: return "Scholars"
            case .charts: return "Charts"
            case .insights: return "Insights"
            case .settings: return "Settings"
            }
        }
        var icon: String {
            switch self {
            case .scholars: return "person.2"
            case .charts: return "chart.line.uptrend.xyaxis"
            case .insights: return "quote.bubble"
            case .settings: return "gearshape"
            }
        }
    }

    @ObservedObject private var state = MainWindowState.shared
    @ObservedObject private var auth = GoogleAuthService.shared

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: Binding(get: { state.section }, set: { state.section = $0 })) {
                    Section {
                        ForEach(Pane.allCases) { p in
                            Label(p.title, systemImage: p.icon).tag(p)
                        }
                    } header: {
                        Text("CiteTrack").font(.headline).foregroundColor(.primary).padding(.bottom, 2)
                    }
                }
                .listStyle(.sidebar)

                Divider()
                accountFooter
                    .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 224, max: 300)
        } detail: {
            detail
                .frame(minWidth: 560, minHeight: 560)
                .navigationTitle(state.section.title)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.section {
        case .scholars:
            MacScholarsView()
        case .charts:
            ChartsContentView()
        case .insights:
            if auth.isSignedIn {
                MacInsightsView()
            } else {
                GoogleSignInView()
            }
        case .settings:
            SettingsView()
        }
    }

    private var accountFooter: some View {
        HStack(spacing: 8) {
            if let u = auth.currentUser {
                Circle().fill(Color.accentColor).frame(width: 26, height: 26)
                    .overlay(Text(u.initials).font(.caption2).fontWeight(.semibold).foregroundColor(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text(u.displayName).font(.caption).lineLimit(1)
                    Text(u.email).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { auth.signOut() } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Sign out")
            } else {
                Button { auth.signIn() } label: {
                    Label("Sign in with Google", systemImage: "person.crop.circle")
                        .font(.caption)
                }
                .controlSize(.small)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Scholars section
struct MacScholarsView: View {
    @State private var scholars: [Scholar] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.cardSpacing) {
                if scholars.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No scholars yet").font(.headline)
                            Text("Add a scholar from the CiteTrack menu-bar icon; they'll appear here.")
                                .font(.callout).foregroundColor(.secondary)
                        }
                    }
                } else {
                    ForEach(scholars) { s in
                        GlassCard { MacScholarRow(scholar: s) }
                    }
                }
            }
            .padding(GlassMetrics.screenPadding)
        }
        .liquidGlassCanvas()
        .onAppear { scholars = PreferencesManager.shared.scholars }
    }
}

private struct MacScholarRow: View {
    let scholar: Scholar
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.85))
                .frame(width: 42, height: 42)
                .overlay(
                    Text(String(scholar.name.prefix(1)).uppercased())
                        .font(.title3).fontWeight(.bold).foregroundColor(.white)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(scholar.name).font(.headline)
                HStack(spacing: 10) {
                    if let c = scholar.citations {
                        Label("\(c)", systemImage: "quote.bubble")
                            .font(.caption).foregroundColor(.blue)
                    }
                    if let u = scholar.lastUpdated {
                        Text(u, style: .date).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Window host
final class MainWindowController {
    static let shared = MainWindowController()
    private var window: NSWindow?

    func show(section: MacMainWindow.Pane? = nil) {
        if let section { MainWindowState.shared.section = section }
        NSApp.setActivationPolicy(.regular)
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: MacMainWindow())
        let w = NSWindow(contentViewController: host)
        w.title = "CiteTrack"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.setContentSize(NSSize(width: 960, height: 680))
        w.center()
        w.isReleasedWhenClosed = false
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
