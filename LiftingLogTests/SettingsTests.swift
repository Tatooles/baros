import SwiftData
import XCTest
@testable import LiftingLog

@MainActor
final class SettingsTests: XCTestCase {
    func testSettingsSingletonExistsAfterSeed() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext

        try SeedDataService.seedIfNeeded(context: context)

        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.weightUnit, .pounds)
    }

    func testUpdatingWeightUnitPersists() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context)

        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        try settings.updateWeightUnit(.kilograms, context: context)

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(fetched.weightUnit, .kilograms)
    }

    func testUpdatingWeightUnitConvertsExistingLoggedWeights() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context)
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        let set = LoggedSet(orderIndex: 0, weight: 225, reps: 5, isCompleted: true)
        context.insert(set)
        try context.save()

        try settings.updateWeightUnit(.kilograms, context: context)

        XCTAssertEqual(set.weight ?? 0, 102.058, accuracy: 0.001)
        XCTAssertEqual(set.completedVolume, 510.291, accuracy: 0.001)
    }

    func testSeedDoesNotOverwriteUserEditedSettings() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context)

        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        settings.weightUnit = .kilograms
        settings.defaultRestTimerSeconds = 120
        try context.save()

        try SeedDataService.seedIfNeeded(context: context)

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertEqual(fetched.weightUnit, .kilograms)
        XCTAssertEqual(fetched.defaultRestTimerSeconds, 120)
    }
}
