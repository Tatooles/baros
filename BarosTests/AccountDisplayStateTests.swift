import XCTest
@testable import Baros
@testable import BarosCore

final class AccountDisplayStateTests: XCTestCase {
    func testPrivacyDeletionActionPrefersAccountDeletionWhenAuthenticatedWithoutOwner() {
        let action = PrivacyDataDeletionAction.resolve(isAuthenticated: true)

        XCTAssertEqual(action, .account)
    }

    func testPrivacyDeletionActionUsesLocalDeletionWhenSignedOut() {
        let action = PrivacyDataDeletionAction.resolve(isAuthenticated: false)

        XCTAssertEqual(action, .localData)
    }
}
