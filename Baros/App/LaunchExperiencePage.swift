import SwiftUI

/// Shared layout for onboarding and What's New pages: hero symbol, title,
/// summary, optional content, and actions. Actions pin to the bottom edge,
/// except at accessibility text sizes, where they scroll with the content so
/// large labels never crowd the page out.
struct LaunchExperiencePage<Content: View, Actions: View>: View {
    let systemImage: String
    let title: String
    let summary: String
    let titleIdentifier: String
    let summaryIdentifier: String
    var focusesTitleOnAppear = false
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isTitleFocused)
                        .accessibilityIdentifier(titleIdentifier)

                    Text(summary)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(summaryIdentifier)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                content

                if dynamicTypeSize.isAccessibilitySize {
                    actionStack
                }
            }
            .padding(.horizontal, AppTheme.shellPadding + 8)
            .padding(.bottom, AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !dynamicTypeSize.isAccessibilitySize {
                actionStack
                    .padding(.horizontal, AppTheme.shellPadding + 8)
                    .padding(.vertical, AppTheme.shellPadding)
            }
        }
        .onAppear {
            if focusesTitleOnAppear {
                isTitleFocused = true
            }
        }
    }

    private var actionStack: some View {
        VStack(spacing: 12) {
            actions
        }
    }
}
