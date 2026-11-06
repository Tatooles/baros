import SwiftData
import SwiftUI

/// Onboarding's workout preferences: weight unit, rest timer, and RPE. Each
/// question shows the current value; only questions someone taps are saved, and
/// Settings stays the place to change them later.
struct OnboardingPreferencesPage: View {
    let onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(RestTimerCoordinator.self) private var restTimer
    @Environment(SyncScheduler.self) private var syncScheduler
    @AppStorage(RPEPreference.storageKey) private var storedRPEEnabled = false
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    @State private var answers = OnboardingWorkoutPreferences()
    @State private var saveFailureMessage: String?

    private var settings: UserSettings? {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).first
    }

    var body: some View {
        LaunchExperiencePage(
            systemImage: "dumbbell",
            title: "How do you lift?",
            summary: "Pick what fits. You can change these anytime in Settings.",
            titleIdentifier: "OnboardingPreferencesTitle",
            summaryIdentifier: "OnboardingPreferencesSummary",
            focusesTitleOnAppear: true
        ) {
            VStack(alignment: .leading, spacing: 24) {
                OnboardingChoiceQuestion(
                    title: "Weight unit",
                    detail: nil,
                    options: [
                        .init(value: MeasurementUnit.pounds, title: "lb", spokenTitle: "Pounds", identifier: "OnboardingWeightUnitPounds"),
                        .init(value: .kilograms, title: "kg", spokenTitle: "Kilograms", identifier: "OnboardingWeightUnitKilograms"),
                    ],
                    selection: answers.weightUnit ?? settings?.weightUnit ?? .pounds,
                    onSelect: { answers.weightUnit = $0 }
                )
                OnboardingChoiceQuestion(
                    title: "Rest timer",
                    detail: "Counts down your rest after you complete a set.",
                    options: Self.onOffOptions(identifierPrefix: "OnboardingRestTimer"),
                    selection: answers.restTimerEnabled ?? restTimer.isEnabled,
                    onSelect: { answers.restTimerEnabled = $0 }
                )
                OnboardingChoiceQuestion(
                    title: "Rate your effort (RPE)",
                    detail: "Rate how hard each set felt, from 6 to 10. A 10 means you couldn't do another rep.",
                    options: Self.onOffOptions(identifierPrefix: "OnboardingRPE"),
                    selection: answers.rpeEnabled ?? storedRPEEnabled,
                    onSelect: { answers.rpeEnabled = $0 }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } actions: {
            Button(action: saveAndContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(AppTheme.brandAccentFill)
            .accessibilityIdentifier("OnboardingPreferencesContinueButton")
        }
        .alert(
            "Couldn't Save Your Choices",
            isPresented: Binding(
                get: { saveFailureMessage != nil },
                set: { if !$0 { saveFailureMessage = nil } }
            ),
            presenting: saveFailureMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private static func onOffOptions(identifierPrefix: String) -> [OnboardingChoiceQuestion<Bool>.Option] {
        [
            .init(value: true, title: "On", spokenTitle: "On", identifier: "\(identifierPrefix)On"),
            .init(value: false, title: "Off", spokenTitle: "Off", identifier: "\(identifierPrefix)Off"),
        ]
    }

    private func saveAndContinue() {
        do {
            let settings = try settings ?? seededSettings()
            try answers.apply(
                to: settings,
                restTimer: restTimer,
                settingsMutation: SettingsMutationService(syncScheduler: syncScheduler),
                context: modelContext
            )
            onContinue()
        } catch {
            modelContext.rollback()
            saveFailureMessage = error.localizedDescription
        }
    }

    /// Launch seeds settings before onboarding appears; this only covers a seed
    /// that has not landed yet.
    private func seededSettings() throws -> UserSettings {
        let owner = currentOwnerCoordinator.localDataOwnerTokenIdentifier
        try SeedDataService.seedIfNeeded(context: modelContext, ownerTokenIdentifier: owner)
        let records = try modelContext.fetch(FetchDescriptor<UserSettings>(sortBy: [SortDescriptor(\.createdAt)]))
        guard let settings = UserSettings.visibleSettingsRecords(from: records, ownerTokenIdentifier: owner).first else {
            throw OnboardingPreferencesError.settingsUnavailable
        }
        return settings
    }
}

private enum OnboardingPreferencesError: LocalizedError {
    case settingsUnavailable

    var errorDescription: String? {
        "Your settings aren't ready yet. Try again in a moment."
    }
}

/// One question answered with large side-by-side choices. VoiceOver and Voice
/// Control name each choice with its question, since several say "On".
private struct OnboardingChoiceQuestion<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        let spokenTitle: String
        let identifier: String
    }

    let title: String
    let detail: String?
    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                ForEach(options, id: \.identifier) { option in
                    choiceButton(option)
                }
            }
        }
    }

    private func choiceButton(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button {
            onSelect(option.value)
        } label: {
            HStack(spacing: 6) {
                if isSelected, differentiateWithoutColor {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(option.title)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AppTheme.onBrandAccent : AppTheme.textPrimary)
        .background(
            isSelected ? AnyShapeStyle(AppTheme.brandAccentFill) : AnyShapeStyle(AppTheme.groupedSurface),
            in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius)
        )
        .accessibilityLabel("\(title), \(option.spokenTitle)")
        .accessibilityInputLabels(["\(title) \(option.spokenTitle)", option.spokenTitle])
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(option.identifier)
    }
}
