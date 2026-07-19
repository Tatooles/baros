import SwiftUI

struct LoadingStateView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.accentBright)
            Text(title)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        SurfaceCard {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        SurfaceCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.accentBright)
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppTheme.textSecondary)
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accentBright)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
