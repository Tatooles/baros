import XCTest
@testable import Baros

final class CurrentOwnerLaunchConfigurationTests: XCTestCase {
    func testNetworkPathMonitoringIsEnabledOnlyForLiveStartup() {
        XCTAssertTrue(CurrentOwnerLaunchConfiguration(arguments: []).observesNetworkRecovery)
        XCTAssertFalse(CurrentOwnerLaunchConfiguration(arguments: [
            "--uitest-sync-owner", "issuer|ui_owner",
        ]).observesNetworkRecovery)
        XCTAssertFalse(CurrentOwnerLaunchConfiguration(arguments: [
            "--uitest-restore-cached-sync-owner",
        ]).observesNetworkRecovery)
        XCTAssertFalse(CurrentOwnerLaunchConfiguration(arguments: [
            "--uitest-force-signed-out-auth",
        ]).observesNetworkRecovery)
    }
}
