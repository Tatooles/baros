import XCTest
@testable import Baros

final class AccountDisplayStateTests: XCTestCase {
    func testSignedOutStateUsesLocalModeCopy() {
        let state = AccountDisplayState.signedOut

        XCTAssertEqual(state.title, "Local workout data")
        XCTAssertEqual(state.subtitle, "Sign in to keep your workouts backed up.")
        XCTAssertEqual(state.actionTitle, "Sign in")
        XCTAssertFalse(state.isSignedIn)
        XCTAssertEqual(state.accessibilityLabel, "Local workout data, Sign in to keep your workouts backed up.")
    }

    func testSignedInStatePrefersFullNameOverEmail() {
        let state = AccountDisplayState.signedIn(fullName: "Kevin Tatooles", email: "kevin@example.com")

        XCTAssertEqual(state.title, "Kevin Tatooles")
        XCTAssertEqual(state.subtitle, "kevin@example.com")
        XCTAssertEqual(state.actionTitle, "Manage account")
        XCTAssertTrue(state.isSignedIn)
        XCTAssertEqual(state.accessibilityLabel, "Kevin Tatooles, kevin@example.com")
    }

    func testSignedInStateFallsBackToEmail() {
        let state = AccountDisplayState.signedIn(fullName: "  ", email: "kevin@example.com")

        XCTAssertEqual(state.title, "kevin@example.com")
        XCTAssertEqual(state.subtitle, "Signed in")
        XCTAssertEqual(state.actionTitle, "Manage account")
        XCTAssertTrue(state.isSignedIn)
    }

    func testSignedInStateFallsBackToGenericAccountName() {
        let state = AccountDisplayState.signedIn(fullName: nil, email: nil)

        XCTAssertEqual(state.title, "Signed in")
        XCTAssertEqual(state.subtitle, "Account connected")
        XCTAssertEqual(state.actionTitle, "Manage account")
        XCTAssertTrue(state.isSignedIn)
    }

    func testPrivacyDeletionActionPrefersAccountDeletionWhenAuthenticatedWithoutOwner() {
        let action = PrivacyDataDeletionAction.resolve(isAuthenticated: true)

        XCTAssertEqual(action, .account)
    }

    func testPrivacyDeletionActionUsesLocalDeletionWhenSignedOut() {
        let action = PrivacyDataDeletionAction.resolve(isAuthenticated: false)

        XCTAssertEqual(action, .localData)
    }
}
