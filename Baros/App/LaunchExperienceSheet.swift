import SwiftUI

enum LaunchExperiencePresentation: Identifiable, Equatable {
    case onboarding
    case whatsNew(WhatsNewRelease)

    var id: String {
        switch self {
        case .onboarding:
            "onboarding"
        case .whatsNew(let release):
            "whats-new-\(release.version)"
        }
    }
}

struct LaunchExperienceSheet: View {
    let presentation: LaunchExperiencePresentation
    let primaryAction: () -> Void

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .onboarding:
            OnboardingFlow(onCompleted: primaryAction)
        case .whatsNew(let release):
            LaunchExperienceContentSheet(
                title: release.title,
                summary: release.summary,
                buttonTitle: "Got It",
                items: release.items,
                preventsInteractiveDismiss: false,
                primaryAction: primaryAction
            )
        }
    }
}

struct LaunchExperienceContentSheet: View {
    let title: String
    let summary: String
    let buttonTitle: String
    let items: [LaunchExperienceItem]
    let preventsInteractiveDismiss: Bool
    let primaryAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(AppTheme.accentBright)
                        .accessibilityHidden(true)

                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("LaunchExperienceTitle")

                    Text(summary)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("LaunchExperienceSummary")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 20) {
                    ForEach(items) { item in
                        LaunchExperienceItemRow(item: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppTheme.shellPadding + 8)
            .padding(.bottom, AppTheme.shellPadding)
        }
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button(action: primaryAction) {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(AppTheme.accentBright)
            .padding(.horizontal, AppTheme.shellPadding + 8)
            .padding(.vertical, AppTheme.shellPadding)
            .accessibilityIdentifier("LaunchExperiencePrimaryButton")
        }
        .interactiveDismissDisabled(preventsInteractiveDismiss)
    }
}

private struct LaunchExperienceItemRow: View {
    let item: LaunchExperienceItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accentBright)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
