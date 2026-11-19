import Foundation
import SwiftData

/// The answers someone gave on the onboarding preferences page. A question they
/// never tapped stays `nil` and is left alone, so it keeps following its usual
/// default: the unit a later sign-in restores, and RPE turning on when rated
/// sets arrive. A tap is a choice, even on the option already shown.
public struct OnboardingWorkoutPreferences: Equatable {
    public var weightUnit: MeasurementUnit?
    public var restTimerEnabled: Bool?
    public var rpeEnabled: Bool?

    public init(
        weightUnit: MeasurementUnit? = nil,
        restTimerEnabled: Bool? = nil,
        rpeEnabled: Bool? = nil
    ) {
        self.weightUnit = weightUnit
        self.restTimerEnabled = restTimerEnabled
        self.rpeEnabled = rpeEnabled
    }

    @MainActor
    public func apply(
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
