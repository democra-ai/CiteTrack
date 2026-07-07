import SwiftUI

// MARK: - Citation Context Section
/// Embedded inside CitingPaperDetailView to display verbatim citation text
/// sourced from Semantic Scholar. Sign-in with Google is required to unlock.
struct CitationContextSection: View {
    let citingPaper: CitingPaper
    /// Title of the user's paper that was cited (used as the search query)
    let myPaperTitle: String

    @StateObject private var contextService = CitationContextService.shared
    @StateObject private var auth = GoogleAuthService.shared

    @State private var context: CitationContext? = nil
    @State private var didLoad = false
    @State private var showSignIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            if !auth.isSignedIn {
                signInPrompt
            } else if contextService.isLoading(for: citingPaper.id) && !didLoad {
                loadingRow
            } else if let ctx = context {
                if ctx.contexts.isEmpty {
                    unavailableRow(source: ctx.source)
                } else {
                    contextContent(ctx)
                }
            } else if let err = contextService.errorMessages[citingPaper.id] {
                errorRow(err)
            } else if didLoad {
                unavailableRow(source: .semanticScholar)
            }
        }
        .onAppear {
            if auth.isSignedIn && !didLoad { load() }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn && !didLoad { load() }
        }
        .sheet(isPresented: $showSignIn) {
            GoogleSignInView { load() }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            Label("How They Cited Your Work", systemImage: "text.quote")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
            if contextService.isLoading(for: citingPaper.id) {
                ProgressView().scaleEffect(0.7)
            }
        }
    }

    // MARK: - States

    private var signInPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.circle")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ctx_signin_title".localized)
                        .font(.subheadline).fontWeight(.medium)
                    Text("ctx_signin_desc".localized)
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            SignInButtons(onGoogle: { showSignIn = true })
        }
        .padding(14)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView().scaleEffect(0.8)
            Text("ctx_searching".localized)
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func unavailableRow(source: CitationContext.ContextSource) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass.circle")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("ctx_unavailable".localized)
                    .font(.subheadline).fontWeight(.medium)
                Text(String(format: "ctx_not_indexed".localized, source.displayName))
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(message == "rate_limited" ? "insights_rate_limited".localized : "ctx_failed".localized)
                    .font(.subheadline).fontWeight(.medium)
                Text(message == "rate_limited" ? "ctx_ratelimit_msg".localized : message)
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("retry".localized) { load() }
                .font(.caption).foregroundColor(.accentColor)
        }
        .padding(14)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Context Content

    @ViewBuilder
    private func contextContent(_ ctx: CitationContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Intent badges
            if !ctx.intents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ctx.intents, id: \.self) { intentBadge($0) }
                    }
                }
            }

            // Quote cards
            ForEach(Array(ctx.contexts.enumerated()), id: \.offset) { idx, quote in
                quoteCard(quote: quote, index: idx + 1, total: ctx.contexts.count)
            }

            // Source attribution
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal")
                Text(String(format: "ctx_source".localized, ctx.source.displayName))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }

    private func quoteCard(quote: String, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if total > 1 {
                Text(String(format: "insights_context_i_of_n".localized, index, total))
                    .font(.caption2).foregroundColor(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)

                Text(quote)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button {
                    UIPasteboard.general.string = quote
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func intentBadge(_ intent: CitationContext.CitationIntent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: intent.icon).font(.caption2)
            Text(intent.displayName).font(.caption2).fontWeight(.medium)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(intentColor(intent).opacity(0.15))
        .foregroundColor(intentColor(intent))
        .cornerRadius(6)
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

    // MARK: - Load

    private func load() {
        didLoad = true
        contextService.errorMessages.removeValue(forKey: citingPaper.id)
        Task {
            let result = await contextService.getCitationContext(
                citingPaper: citingPaper,
                myPaperTitle: myPaperTitle
            )
            await MainActor.run { context = result }
        }
    }
}
