import SwiftUI

enum LaunchExperiencePresentation: Identifiable, Equatable {
    case welcome
    case whatsNew(WhatsNewRelease)

    var id: String {
        switch self {
        case .welcome:
            "welcome"
        case .whatsNew(let release):
            "whats-new-\(release.version)"
        }
    }
}

struct LaunchExperienceSheet: View {
    let presentation: LaunchExperiencePresentation
    let primaryAction: () -> Void

    private var title: String {
        switch presentation {
        case .welcome:
            "Welcome to Baros"
        case .whatsNew(let release):
            release.title
        }
    }

    private var summary: String {
        switch presentation {
        case .welcome:
            "Log your lifts in seconds. Everything is saved on this iPhone, with optional cloud sync when you sign in."
        case .whatsNew(let release):
            release.summary
        }
    }

    private var buttonTitle: String {
        switch presentation {
        case .welcome:
            "Continue"
        case .whatsNew:
            "Got It"
        }
    }

    private var items: [WhatsNewItem] {
        switch presentation {
        case .welcome:
            [
                WhatsNewItem(
                    id: "logging",
                    systemImage: "bolt.fill",
                    title: "Fast workout logging",
                    detail: "Start a workout and log sets in a couple of taps — no network needed."
                ),
                WhatsNewItem(
                    id: "history",
                    systemImage: "clock.arrow.circlepath",
                    title: "Your history stays put",
                    detail: "Every finished workout is saved on this iPhone, even offline."
                ),
                WhatsNewItem(
                    id: "sync",
                    systemImage: "icloud",
                    title: "Optional cloud sync",
                    detail: "Sign in to back up finished workouts, exercises, and settings."
                ),
                WhatsNewItem(
                    id: "data",
                    systemImage: "lock.shield",
                    title: "Control your data",
                    detail: "Export history and manage privacy from Settings."
                ),
            ]
        case .whatsNew(let release):
            release.items
        }
    }

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
        .interactiveDismissDisabled(presentation == .welcome)
    }
}

private struct LaunchExperienceItemRow: View {
    let item: WhatsNewItem

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
