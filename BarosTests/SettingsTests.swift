import SwiftData
import XCTest
@testable import Baros

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

    func testUpdatingWeightUnitDoesNotRewriteExistingLoggedWeights() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context)
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        let originalUpdatedAt = Date(timeIntervalSince1970: 50)
        let set = LoggedSet(
            orderIndex: 0,
            weight: 225,
            reps: 5,
            isCompleted: true,
            updatedAt: originalUpdatedAt
        )
        context.insert(set)
        try context.save()

        try settings.updateWeightUnit(.kilograms, context: context)

        XCTAssertEqual(settings.weightUnit, .kilograms)
        XCTAssertEqual(set.weight, 225)
        XCTAssertEqual(set.completedVolume, 1125)
        XCTAssertEqual(set.updatedAt, originalUpdatedAt)
    }

    func testUpdatingWeightUnitDoesNotRewriteTombstonedSets() throws {
        let container = try SwiftDataTestSupport.makeInMemoryContainer()
        let context = container.mainContext
        try SeedDataService.seedIfNeeded(context: context)
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        let set = LoggedSet(
            orderIndex: 0,
            weight: 225,
            reps: 5,
            isCompleted: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let deletedAt = Date(timeIntervalSince1970: 200)
        set.markDeleted(now: deletedAt)
        context.insert(set)
        try context.save()

        try settings.updateWeightUnit(.kilograms, context: context)

        XCTAssertEqual(set.weight, 225)
        XCTAssertEqual(set.updatedAt, deletedAt)
        XCTAssertEqual(set.deletedAt, deletedAt)
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
