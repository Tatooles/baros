import SwiftData
import XCTest
@testable import Baros

@MainActor
final class OnboardingWorkoutPreferencesTests: XCTestCase {
    private let suiteName = "OnboardingWorkoutPreferencesTests"
    private let owner = "issuer|owner_a"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    override func setUp() async throws {
        try await super.setUp()
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private var storedRPEChoice: Bool? {
        defaults.object(forKey: RPEPreference.storageKey) as? Bool
    }

    // MARK: - New users

    func testContinuingWithoutTappingChangesNothing() throws {
        let (context, settings) = try makeSignedOutSettings()
        var persistedRestTimerChoices: [Bool] = []
        let restTimer = RestTimerCoordinator(persistEnabled: { persistedRestTimerChoices.append($0) })

        try apply(OnboardingWorkoutPreferences(), settings: settings, restTimer: restTimer, context: context)

        XCTAssertEqual(settings.weightUnit, .pounds)
        XCTAssertEqual(settings.updatedAt, Date(timeIntervalSince1970: 10))
        XCTAssertTrue(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).isEmpty)
        XCTAssertTrue(restTimer.isEnabled)
        XCTAssertEqual(persistedRestTimerChoices, [])
        XCTAssertNil(storedRPEChoice, "An untouched RPE question stays undecided")
    }

    func testTappedAnswersAreSaved() throws {
        let (context, settings) = try makeSignedOutSettings()
        var persistedRestTimerChoices: [Bool] = []
        let restTimer = RestTimerCoordinator(persistEnabled: { persistedRestTimerChoices.append($0) })

        try apply(
            OnboardingWorkoutPreferences(weightUnit: .kilograms, restTimerEnabled: false, rpeEnabled: true),
            settings: settings,
            restTimer: restTimer,
            context: context
        )

        XCTAssertEqual(settings.weightUnit, .kilograms)
        let outbox = try context.fetch(FetchDescriptor<SyncOutboxEntry>())
        XCTAssertEqual(outbox.map(\.entityKind), [.userSettings])
        XCTAssertEqual(outbox.first?.entityID, settings.id)
        XCTAssertFalse(restTimer.isEnabled)
        XCTAssertEqual(persistedRestTimerChoices, [false])
        XCTAssertEqual(storedRPEChoice, true)
    }

    func testTappingTheShownUnitStillCountsAsAChoice() throws {
        let (context, settings) = try makeSignedOutSettings()

        try apply(OnboardingWorkoutPreferences(weightUnit: .pounds), settings: settings, context: context)

        XCTAssertEqual(settings.weightUnit, .pounds)
        XCTAssertGreaterThan(settings.updatedAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(try context.fetch(FetchDescriptor<SyncOutboxEntry>()).map(\.entityKind), [.userSettings])
    }

    // MARK: - Returning users signing in after onboarding

    func testSignInRestoresTheSyncedUnitWhenTheQuestionWasUntouched() async throws {
        let (context, settings) = try makeSignedOutSettings()
        try apply(OnboardingWorkoutPreferences(rpeEnabled: false), settings: settings, context: context)

        let remoteID = UUID()
        let client = FakeSyncClient()
        client.fetchResponses = [settingsResponse(remoteID: remoteID, weightUnitRaw: "kilograms", updatedAt: 20)]

        try await SyncCoordinator(client: client, rpeDefaults: defaults).run(ownerTokenIdentifier: owner, context: context)

        let synced = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(synced.id, remoteID)
        XCTAssertEqual(synced.weightUnit, .kilograms, "A default must not overwrite the synced unit")
        XCTAssertFalse(client.upsertedSettings.contains { $0.weightUnitRaw == "pounds" })
    }

    func testSignInKeepsTheUnitChosenDuringOnboarding() async throws {
        let (context, settings) = try makeSignedOutSettings()
        try apply(OnboardingWorkoutPreferences(weightUnit: .pounds), settings: settings, context: context)

        let remoteID = UUID()
        let client = FakeSyncClient()
        client.fetchResponses = [
            settingsResponse(remoteID: remoteID, weightUnitRaw: "kilograms", updatedAt: 20),
            settingsResponse(remoteID: remoteID, weightUnitRaw: "pounds", updatedAt: settings.updatedAt.timeIntervalSince1970),
        ]

        try await SyncCoordinator(client: client, rpeDefaults: defaults).run(ownerTokenIdentifier: owner, context: context)

        let synced = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(synced.id, remoteID)
        XCTAssertEqual(synced.weightUnit, .pounds, "The synced unit must not overwrite a new choice")
        XCTAssertEqual(client.upsertedSettings.map(\.clientId), [remoteID.uuidString.lowercased()])
        XCTAssertEqual(client.upsertedSettings.map(\.weightUnitRaw), ["pounds"])
    }

    func testUntouchedRPEStillTurnsOnWhenRatedSetsArrive() throws {
        let (context, settings) = try makeSignedOutSettings()
        try apply(OnboardingWorkoutPreferences(), settings: settings, context: context)

        // What SyncCoordinator does when a rated set arrives (see RPEPreferenceTests).
        RPEPreference.enableIfUndecided(defaults: defaults)

        XCTAssertEqual(storedRPEChoice, true)
    }

    func testRPEAnsweredOffStaysOffWhenRatedSetsArrive() throws {
        let (context, settings) = try makeSignedOutSettings()
        try apply(OnboardingWorkoutPreferences(rpeEnabled: false), settings: settings, context: context)

        RPEPreference.enableIfUndecided(defaults: defaults)

        XCTAssertEqual(storedRPEChoice, false)
    }

    // MARK: - Later changes in Settings

    func testSettingsCanChangeEveryOnboardingChoiceLater() throws {
        let (context, settings) = try makeSignedOutSettings()
        let restTimer = RestTimerCoordinator()
        try apply(
            OnboardingWorkoutPreferences(weightUnit: .kilograms, restTimerEnabled: false, rpeEnabled: true),
            settings: settings,
            restTimer: restTimer,
            context: context
        )

        // The same storage the Settings controls write to.
        try SettingsMutationService().updateWeightUnit(.pounds, settings: settings, context: context)
        restTimer.setEnabled(true)
        defaults.set(false, forKey: RPEPreference.storageKey)

        XCTAssertEqual(settings.weightUnit, .pounds)
        XCTAssertTrue(restTimer.isEnabled)
        XCTAssertEqual(storedRPEChoice, false)
    }

    // MARK: - Helpers

    private func makeSignedOutSettings() throws -> (ModelContext, UserSettings) {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        retainedContainers.append(container)
        let context = container.mainContext
        let settings = UserSettings(
            weightUnit: .pounds,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        context.insert(settings)
        try context.save()
        return (context, settings)
    }

    private var retainedContainers: [ModelContainer] = []

    private func apply(
        _ answers: OnboardingWorkoutPreferences,
        settings: UserSettings,
        restTimer: RestTimerCoordinator = RestTimerCoordinator(),
        context: ModelContext
    ) throws {
        try answers.apply(
            to: settings,
            restTimer: restTimer,
            settingsMutation: SettingsMutationService(),
            context: context,
            rpeDefaults: defaults
        )
    }

    private func settingsResponse(remoteID: UUID, weightUnitRaw: String, updatedAt: Double) -> SyncFetchChangesResponse {
        SyncFetchChangesResponse(
            userSettings: [
                UserSettingsSyncRecord(
                    clientId: remoteID.uuidString.lowercased(),
                    createdAt: 5,
                    updatedAt: updatedAt,
                    deletedAt: nil,
                    serverUpdatedAt: updatedAt + 1,
                    weightUnitRaw: weightUnitRaw,
                    defaultRestTimerSeconds: 90,
                    hasCompletedOnboarding: true
                )
            ],
            exercises: [],
            workoutSessions: [],
            loggedExercises: [],
            loggedSets: [],
            cursors: SyncChangeCursors(userSettings: updatedAt + 1, exercises: 0),
            hasMore: SyncHasMore(userSettings: false, exercises: false)
        )
    }
}
