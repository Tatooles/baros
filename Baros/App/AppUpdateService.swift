import Foundation
import Observation
import StoreKit

/// Strict numeric marketing/OS versions. Missing trailing components compare as zero.
struct UpdateVersion: Comparable, Equatable {
    private let components: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 8 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        while numbers.last == 0 { numbers.removeLast() }
        components = numbers
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct AppUpdateOffer: Codable, Equatable {
    let version: String
    let country: String
    var url: URL { URL(string: "https://apps.apple.com/\(country.lowercased())/app/id6782692304")! }
}

@MainActor @Observable
final class AppUpdateService {
    static let interval: TimeInterval = 24 * 60 * 60
    private(set) var offer: AppUpdateOffer?
    private let defaults: UserDefaults
    private let installedVersion: String
    private let osVersion: String
    private let context: () async -> String?
    private let lookup: (String) async throws -> Data
    private let now: () -> Date
    private var checking = false
    private static let attemptKey = "appUpdate.lastAttempt"
    private static let dismissedKey = "appUpdate.dismissedVersions"

    init(defaults: UserDefaults, installedVersion: String, osVersion: String,
         now: @escaping () -> Date = Date.init,
         context: @escaping () async -> String?,
         lookup: @escaping (String) async throws -> Data) {
        self.defaults = defaults
        self.installedVersion = installedVersion
        self.osVersion = osVersion
        self.now = now
        self.context = context
        self.lookup = lookup
    }

    func check() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        // Do not retain a deferred recommendation across foreground/storefront changes.
        offer = nil
        let throttled: Bool
        if let last = defaults.object(forKey: Self.attemptKey) as? Date,
           now().timeIntervalSince(last) < Self.interval { throttled = true }
        else { throttled = false }
        // Persist before any asynchronous work, including failures and missing storefront.
        if !throttled {
            defaults.set(now(), forKey: Self.attemptKey)
            defaults.removeObject(forKey: "appUpdate.cachedResponse")
        }
        guard let country = await context() else { return }
        do {
            let data: Data
            if throttled {
                guard defaults.string(forKey: "appUpdate.cachedCountry") == country,
                      let cached = defaults.data(forKey: "appUpdate.cachedResponse") else { return }
                data = cached
            } else {
                data = try await lookup(country)
                defaults.set(data, forKey: "appUpdate.cachedResponse")
                defaults.set(country, forKey: "appUpdate.cachedCountry")
            }
            guard let version = Self.compatibleVersion(data: data, installed: installedVersion, os: osVersion),
                  !isDismissed(version) else { return }
            offer = AppUpdateOffer(version: version, country: country)
        } catch { /* Optional discovery must remain silent offline. */ }
    }

    func later(_ offer: AppUpdateOffer) {
        var dismissed = defaults.stringArray(forKey: Self.dismissedKey) ?? []
        if !isDismissed(offer.version) { dismissed.append(offer.version) }
        defaults.set(dismissed, forKey: Self.dismissedKey)
        self.offer = nil
    }

    func didChooseUpdate() { offer = nil }

    private func isDismissed(_ version: String) -> Bool {
        (defaults.stringArray(forKey: Self.dismissedKey) ?? []).contains {
            UpdateVersion($0) == UpdateVersion(version)
        }
    }

    static func compatibleVersion(data: Data, installed: String, os: String) -> String? {
        struct Response: Decodable {
            struct Item: Decodable {
                let trackId: Int64
                let bundleId: String
                let version: String
                let minimumOsVersion: String
            }
            let resultCount: Int
            let results: [Item]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.resultCount == 1, response.results.count == 1,
              let item = response.results.first, item.trackId == 6782692304,
              item.bundleId == "com.kevintatooles.LiftingLog",
              let latest = UpdateVersion(item.version), let installed = UpdateVersion(installed),
              let minimum = UpdateVersion(item.minimumOsVersion), let os = UpdateVersion(os),
              latest > installed, minimum <= os else { return nil }
        return item.version
    }

    static func lookupURL(country: String) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [URLQueryItem(name: "id", value: "6782692304"),
                                 URLQueryItem(name: "country", value: country),
                                 URLQueryItem(name: "entity", value: "software")]
        return components.url!
    }

    static func countryCode(_ alpha3: String) -> String? {
        guard alpha3.count == 3, alpha3.utf8.allSatisfy({ (65...90).contains($0) }),
              let region = Locale(identifier: "und_\(alpha3)").region?.identifier,
              region.count == 2, Locale.Region.isoRegions.contains(where: { $0.identifier == region }) else { return nil }
        return region
    }

    #if DEBUG
    private static var didResetVisualFixture = false
    #endif

    static func live() -> AppUpdateService {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-update-available") {
            let defaults = UserDefaults(suiteName: "appUpdate.visualFixture")!
            if ProcessInfo.processInfo.arguments.contains("--uitest-update-reset"), !didResetVisualFixture {
                didResetVisualFixture = true
                defaults.removePersistentDomain(forName: "appUpdate.visualFixture")
            }
            return AppUpdateService(defaults: defaults, installedVersion: "1.5", osVersion: "26.4.1",
                context: { "US" }, lookup: { _ in
                    if ProcessInfo.processInfo.arguments.contains("--uitest-update-delayed") {
                        try await Task.sleep(for: .seconds(4))
                    }
                    return Data(#"{"resultCount":1,"results":[{"trackId":6782692304,"bundleId":"com.kevintatooles.LiftingLog","version":"1.10","minimumOsVersion":"26.0"}]}"#.utf8)
                })
        }
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return AppUpdateService(defaults: .standard,
            installedVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", context: {
                #if DEBUG || targetEnvironment(simulator)
                return nil
                #else
                // A verified production app transaction excludes TestFlight, Xcode and ad hoc builds.
                guard Bundle.main.bundleIdentifier == "com.kevintatooles.LiftingLog",
                      let result = try? await AppTransaction.shared,
                      case .verified(let transaction) = result, transaction.environment == .production,
                      let storefront = await Storefront.current else { return nil }
                return countryCode(storefront.countryCode)
                #endif
            }, lookup: { country in
                var request = URLRequest(url: lookupURL(country: country))
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return data
            })
    }
}
