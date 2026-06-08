import ConvexMobile
import XCTest
@testable import LiftingLog

final class ConvexSyncArgumentMapperTests: XCTestCase {
    func testUserSettingsArgsEncodeRestTimerAsDouble() throws {
        let payload = UserSettingsSyncPayload(
            clientId: "settings-1",
            createdAt: 1,
            updatedAt: 2,
            deletedAt: nil,
            weightUnitRaw: "kilograms",
            defaultRestTimerSeconds: 90,
            hasCompletedOnboarding: true
        )

        let record = ConvexSyncArgumentMapper.userSettingsRecord(payload)
        let encodedRestTimer = try XCTUnwrap(try XCTUnwrap(record["defaultRestTimerSeconds"]))

        XCTAssertEqual(encodedRestTimer as? Double, 90)
        XCTAssertFalse(encodedRestTimer is Int)
    }

    func testFetchChangesArgsEncodeLimitAsDouble() throws {
        let args = ConvexSyncArgumentMapper.fetchChangesArgs(
            cursors: SyncChangeCursors(userSettings: 1, exercises: 2),
            limit: 100
        )

        let encodedLimit = try XCTUnwrap(try XCTUnwrap(args["limit"]))

        XCTAssertEqual(encodedLimit as? Double, 100)
        XCTAssertFalse(encodedLimit is Int)
    }
}
