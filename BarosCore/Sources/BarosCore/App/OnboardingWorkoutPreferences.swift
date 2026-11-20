import Foundation
import SwiftData

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
