import Foundation
import SwiftData

/// The answers someone gave on the onboarding preferences page. A question they
/// never tapped stays `nil` and is left alone, so it keeps following its usual
/// default: the unit a later sign-in restores, and RPE turning on when rated
/// sets arrive. A tap is a choice, even on the option already shown.
struct OnboardingWorkoutPreferences: Equatable {
    var weightUnit: MeasurementUnit?
    var restTimerEnabled: Bool?
    var rpeEnabled: Bool?

    @MainActor
    func apply(
        to settings: UserSettings,
        restTimer: RestTimerCoordinator,
        settingsMutation: SettingsMutationService,
        context: ModelContext,
        rpeDefaults: UserDefaults = .standard
    ) throws {
        if let weightUnit {
            try settingsMutation.chooseWeightUnit(weightUnit, settings: settings, context: context)
        }
        if let restTimerEnabled {
            restTimer.setEnabled(restTimerEnabled)
        }
        if let rpeEnabled {
            RPEPreference.choose(rpeEnabled, defaults: rpeDefaults)
        }
    }
}
