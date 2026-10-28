import XCTest
@testable import Baros

@MainActor
final class AppUpdateServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        try await super.setUp()
        suite = "AppUpdateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        try await super.tearDown()
    }

    private func response(_ version: String = "1.10", minimum: String = "26.0",
                          bundle: String = "com.kevintatooles.LiftingLog", id: Int64 = 6782692304) -> Data {
        Data("""
        {"resultCount":1,"results":[{"trackId":\(id),"bundleId":"\(bundle)","version":"\(version)","minimumOsVersion":"\(minimum)"}]}
        """.utf8)
    }

    func testNumericVersionsAndMalformedInput() {
        XCTAssertGreaterThan(UpdateVersion("1.10")!, UpdateVersion("1.9")!)
        XCTAssertEqual(UpdateVersion("1.5"), UpdateVersion("1.5.0"))
        XCTAssertEqual(UpdateVersion("0"), UpdateVersion("0.0"))
        XCTAssertLessThan(UpdateVersion("1.9.99")!, UpdateVersion("1.10")!)
        for value in ["", ".", "1.", ".1", "1..2", "1.5b1", "-1", " 1.5", "１.５", String(repeating: "9", count: 40)] {
            XCTAssertNil(UpdateVersion(value), value)
        }
    }

    func testOnlyNewerCompatibleCorrectProductIsOffered() {
        func version(_ data: Data) -> String? {
            AppUpdateService.compatibleVersion(data: data, installed: "1.5", os: "26.4.1")
        }
        XCTAssertEqual(version(response()), "1.10")
        for data in [response("1.5"), response("1.5.0"), response("1.4"), response(minimum: "27.0"),
                     response(minimum: "bad"), response("1.6-beta"), response(bundle: "other"), response(id: 1),
                     Data("{}".utf8), Data("{\"resultCount\":0,\"results\":[]}".utf8), Data("offline".utf8)] {
            XCTAssertNil(version(data))
        }
    }

    func testThrottleRestartDeferredOfferAndLaterRelease() async {
        var date = Date(timeIntervalSince1970: 1_000_000)
        var calls = 0
        var advertised = "1.10"
        func make() -> AppUpdateService {
            AppUpdateService(defaults: defaults, installedVersion: "1.5", osVersion: "26.4.1", now: { date },
                context: { "US" }, lookup: { _ in calls += 1; return self.response(advertised) })
        }
        let first = make()
        await first.check()
        XCTAssertEqual(first.offer?.version, "1.10")
        let restarted = make()
        await restarted.check()
        XCTAssertEqual(restarted.offer, first.offer, "Deferred result survives process restart")
        XCTAssertEqual(calls, 1)
        restarted.later(restarted.offer!)
        let dismissedRestart = make()
        await dismissedRestart.check()
        XCTAssertNil(dismissedRestart.offer)
        date.addTimeInterval(AppUpdateService.interval - 1)
        await dismissedRestart.check()
        XCTAssertEqual(calls, 1)
        date.addTimeInterval(1)
        await dismissedRestart.check()
        XCTAssertEqual(calls, 2)
        XCTAssertNil(dismissedRestart.offer)
        advertised = "1.11"
        date.addTimeInterval(AppUpdateService.interval)
        await dismissedRestart.check()
        XCTAssertEqual(dismissedRestart.offer?.version, "1.11")
        XCTAssertEqual(calls, 3)
    }

    func testOfflineFailureThrottlesAndClearsOldOffer() async {
        var date = Date(timeIntervalSince1970: 1_000_000)
        var fails = false
        var calls = 0
        let service = AppUpdateService(defaults: defaults, installedVersion: "1.5", osVersion: "26.4.1", now: { date },
            context: { "US" }, lookup: { _ in
                calls += 1
                if fails { throw URLError(.notConnectedToInternet) }
                return self.response()
            })
        await service.check()
        XCTAssertNotNil(service.offer)
        fails = true
        date.addTimeInterval(AppUpdateService.interval)
        await service.check()
        XCTAssertNil(service.offer)
        await service.check()
        XCTAssertNil(service.offer)
        XCTAssertEqual(calls, 2)
    }

    func testUnknownOrChangedStorefrontNeverUsesAnotherCountriesCache() async {
        var country: String? = "US"
        var calls = 0
        let service = AppUpdateService(defaults: defaults, installedVersion: "1.5", osVersion: "26.4.1",
            context: { country }, lookup: { _ in calls += 1; return self.response() })
        await service.check()
        XCTAssertNotNil(service.offer)
        country = "GB"
        await service.check()
        XCTAssertNil(service.offer)
        country = nil
        await service.check()
        XCTAssertNil(service.offer)
        XCTAssertEqual(calls, 1)
    }

    func testDisabledContextNeverLooksUpAndMalformedResultIsSilent() async {
        var calls = 0
        let disabled = AppUpdateService(defaults: defaults, installedVersion: "1.5", osVersion: "26",
            context: { nil }, lookup: { _ in calls += 1; return self.response() })
        await disabled.check()
        XCTAssertEqual(calls, 0)
        XCTAssertNil(disabled.offer)
        let malformed = AppUpdateService(defaults: UserDefaults(suiteName: suite + ".malformed")!,
            installedVersion: "1.5", osVersion: "26", context: { "US" }, lookup: { _ in Data("not JSON".utf8) })
        await malformed.check()
        XCTAssertNil(malformed.offer)
        UserDefaults().removePersistentDomain(forName: suite + ".malformed")
    }

    func testStorefrontConversionAndURLs() {
        XCTAssertEqual(AppUpdateService.countryCode("USA"), "US")
        XCTAssertEqual(AppUpdateService.countryCode("GBR"), "GB")
        XCTAssertEqual(AppUpdateService.countryCode("CAN"), "CA")
        XCTAssertEqual(AppUpdateService.countryCode("JPN"), "JP")
        XCTAssertNil(AppUpdateService.countryCode("ZZZ"))
        XCTAssertNil(AppUpdateService.countryCode("US"))
        let url = AppUpdateService.lookupURL(country: "GB")
        XCTAssertEqual(url.host, "itunes.apple.com")
        XCTAssertTrue(url.query!.contains("country=GB"))
        XCTAssertTrue(url.query!.contains("id=6782692304"))
        XCTAssertEqual(AppUpdateOffer(version: "1.10", country: "GB").url.absoluteString,
                       "https://apps.apple.com/gb/app/id6782692304")
    }
}
