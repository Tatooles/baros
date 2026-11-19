import XCTest
@testable import Baros
@testable import BarosCore

final class AppReleaseCatalogTests: XCTestCase {
    func testCurrentAppVersionIsCataloged() {
        XCTAssertNotNil(AppReleaseCatalog.release(for: AppBuildInfo.current.version))
    }
}
