import SwiftUI

// MARK: - Citation Insights View
/// New tab that aggregates citation context across all papers.
/// Requires Google Sign-In.
struct CitationInsightsView: View {
    @StateObject private var auth = GoogleAuthService.shared
    @StateObject private var dataManager = DataManager.shared
    @StateObject private var contextService = CitationContextService.shared

    @State private var showSignIn = false
    @State private var cachedContexts: [CitationContext] = []

    var body: some View {
        NavigationView {
            Group {
                if auth.isSignedIn {
                    insightsBody
                } else {
                    signInGate
                }
            }
            .navigationTitle("Citation Insights")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let user = auth.currentUser {
                        SignedInUserBadge(user: user) { auth.signOut() }
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showSignIn) {
            GoogleSignInView { refreshContexts() }
        }
        .onAppear {
            if auth.isSignedIn { refreshContexts() }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { refreshContexts() }
        }
    }

    // MARK: - Sign-In Gate

    private var signInGate: some View {
        VStack(spacing: 36) {
            Spacer()

            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 72, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            VStack(spacing: 8) {
                Text("Citation Insights")
                    .font(.title2).fontWeight(.bold)
                Text("Coming soon")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }

            Text("Discover how researchers worldwide (especially Big Names — see exactly how prominent academics reference your work) cite your work — word for word, powered by Semantic Scholar.")
                .font(.body).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            GoogleSignInButton { }
                .padding(.horizontal, 40)
                .disabled(true)
                .opacity(0.4)

            Spacer()
        }
    }

    // MARK: - Main Content

    private var insightsBody: some View {
        List {
            // Summary card
            Section {
                summaryCard
            }

            // Intent distribution
            if !cachedContexts.isEmpty {
                Section("Citation Intent Distribution") {
                    intentDistributionView
                }
            }

            // How it works
            Section("How to Use") {
                howItWorksCard
            }

            // Recent contexts
            Section("Recent Citation Contexts") {
                if cachedContexts.isEmpty {
                    emptyContextsRow
                } else {
                    ForEach(cachedContexts.filter { !$0.contexts.isEmpty }.prefix(10)) { ctx in
                        contextPreviewRow(ctx)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { refreshContexts() }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 20) {
            statCell(
                value: "\(cachedContexts.count)",
                label: "Papers Analyzed",
                icon: "doc.text.magnifyingglass",
                color: .blue
            )
            Divider().frame(height: 40)
            statCell(
                value: "\(cachedContexts.reduce(0) { $0 + $1.contexts.count })",
                label: "Quotes Found",
                icon: "quote.opening",
                color: .purple
            )
            Divider().frame(height: 40)
            statCell(
                value: "\(dataManager.scholars.count)",
                label: "Scholars",
                icon: "person.2",
                color: .green
            )
        }
        .padding(.vertical, 8)
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2).fontWeight(.bold)
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Intent Distribution

    private var intentDistributionView: some View {
        let counts = intentCounts(from: cachedContexts)
        let total = counts.values.reduce(0, +)

        return VStack(spacing: 10) {
            ForEach(CitationContext.CitationIntent.allCases, id: \.self) { intent in
                let count = counts[intent] ?? 0
                let fraction = total > 0 ? Double(count) / Double(total) : 0

                HStack(spacing: 10) {
                    Image(systemName: intent.icon)
                        .frame(width: 20)
                        .foregroundColor(intentColor(intent))

                    Text(intent.displayName)
                        .font(.subheadline)
                        .frame(width: 90, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(intentColor(intent))
                                .frame(width: max(4, geo.size.width * fraction))
                        }
                    }
                    .frame(height: 10)

                    Text("\(count)")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - How It Works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepRow(n: "1", text: "Open \"Who Cited Me\" and tap any citing paper")
            stepRow(n: "2", text: "Scroll to \"How They Cited Your Work\"")
            stepRow(n: "3", text: "Read the verbatim sentences — sourced from Semantic Scholar")
        }
        .padding(.vertical, 4)
    }

    private func stepRow(n: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 22, height: 22)
                Text(n).font(.caption).fontWeight(.bold).foregroundColor(.white)
            }
            Text(text).font(.subheadline)
        }
    }

    // MARK: - Context Preview Rows

    private var emptyContextsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray").foregroundColor(.secondary)
            Text("No contexts loaded yet.\nOpen papers in \"Who Cited Me\" to start.")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func contextPreviewRow(_ ctx: CitationContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ctx.citingPaperTitle)
                .font(.subheadline).fontWeight(.medium)
                .lineLimit(2)

            if let first = ctx.contexts.first {
                Text("\"\(first)\"")
                    .font(.caption).foregroundColor(.secondary)
                    .lineLimit(3).italic()
            }

            HStack(spacing: 6) {
                ForEach(ctx.intents.prefix(2), id: \.self) { intent in
                    intentPill(intent)
                }
                Spacer()
                Text(ctx.source.displayName)
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func intentPill(_ intent: CitationContext.CitationIntent) -> some View {
        Text(intent.displayName)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(intentColor(intent).opacity(0.15))
            .foregroundColor(intentColor(intent))
            .cornerRadius(4)
    }

    // MARK: - Helpers

    private func refreshContexts() {
        cachedContexts = contextService.allCachedContexts()
    }

    private func intentColor(_ intent: CitationContext.CitationIntent) -> Color {
        switch intent {
        case .methodology: return .blue
        case .background: return .gray
        case .result: return .green
        case .extends: return .purple
        case .unknown: return .orange
        }
    }

    private func intentCounts(from contexts: [CitationContext]) -> [CitationContext.CitationIntent: Int] {
        var counts: [CitationContext.CitationIntent: Int] = [:]
        for ctx in contexts {
            if ctx.intents.isEmpty && !ctx.contexts.isEmpty {
                counts[.unknown, default: 0] += 1
            } else {
                for intent in ctx.intents { counts[intent, default: 0] += 1 }
            }
        }
        return counts
    }
}

// MARK: - Preview
#Preview {
    CitationInsightsView()
}
