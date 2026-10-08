import SwiftData
import SwiftUI

struct SettingsTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var settings: UserSettings? {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).first
    }

    var body: some View {
        Group {
            if let settings {
                SettingsView(settings: settings)
            } else {
                ProgressView()
                    .tint(AppTheme.brandAccentFill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.canvasBackground.ignoresSafeArea())
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            #if DEBUG
            if AppEnvironmentConfiguration.current.environment == .development {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("DEV")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.brandAccentMuted, in: Capsule())
                        .accessibilityIdentifier("SettingsEnvironmentBadge")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            #endif
        }
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .exerciseLibrary:
                ExerciseLibraryView()
            case .deleteData(let mode):
                DeleteDataDestination(mode: mode)
            #if DEBUG
            case .developerDiagnostics:
                DeveloperDiagnosticsView()
            #endif
            }
        }
        .task(id: currentOwnerCoordinator.localDataOwnerTokenIdentifier) {
            seedSettingsIfNeeded()
        }
    }

    private func seedSettingsIfNeeded() {
        if UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).isEmpty {
            try? SeedDataService.seedIfNeeded(
                context: modelContext,
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
            )
        }
    }
}
