import SwiftUI

// macOS-native Liquid Glass kit — mirrors the iOS design system (GlassMetrics,
// GlassCard, glassSurface, liquidGlassCanvas, LiquidGlassBackground) but uses
// macOS-available APIs (native glassEffect on macOS 26, Material fallback below;
// MeshGradient on macOS 14+, LinearGradient below). The iOS app keeps its own copy
// (it imports UIKit), so this is a clean, self-contained macOS version.

enum GlassMetrics {
    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 14
    static let screenPadding: CGFloat = 18
}

struct LiquidGlassBackground: View {
    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        Color(nsColor: .windowBackgroundColor), Color.blue.opacity(0.10), Color(nsColor: .windowBackgroundColor),
                        Color.teal.opacity(0.08), Color(nsColor: .windowBackgroundColor), Color.indigo.opacity(0.10),
                        Color(nsColor: .windowBackgroundColor), Color.green.opacity(0.07), Color(nsColor: .windowBackgroundColor)
                    ]
                )
            } else {
                LinearGradient(
                    colors: [Color(nsColor: .windowBackgroundColor), Color.blue.opacity(0.08), Color(nsColor: .windowBackgroundColor)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Shared Liquid Glass canvas behind a screen; hides opaque scroll background.
    @ViewBuilder
    func liquidGlassCanvas() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(LiquidGlassBackground())
    }

    /// The single glass surface used by every card (native glassEffect on macOS 26,
    /// Material fallback below), plus a soft shadow and a hairline edge.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = GlassMetrics.cardRadius, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(
                    tint != nil ? Glass.regular.tint(tint!.opacity(0.16)) : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
    }
}

/// A padded Liquid Glass card — the base content surface.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = GlassMetrics.cardRadius
    var padding: CGFloat = GlassMetrics.cardPadding
    var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .glassSurface(cornerRadius: cornerRadius, tint: tint)
    }
}

/// Small uppercase section header used inside cards.
struct GlassSectionTitle: View {
    let text: String
    var icon: String? = nil
    var count: Int? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.caption).foregroundColor(.secondary) }
            Text(text).font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            if let count, count > 0 {
                Text("(\(count))").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .textCase(.uppercase)
    }
}

/// Small rounded chip.
struct GlassChip: View {
    let text: String
    var tint: Color = .secondary
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundColor(tint == .secondary ? .secondary : tint)
    }
}
