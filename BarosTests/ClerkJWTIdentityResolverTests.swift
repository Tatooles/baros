import XCTest
@testable import Baros

final class ClerkJWTIdentityResolverTests: XCTestCase {
    func testOwnerTokenIdentifierUsesIssuerAndSubjectClaims() {
        let jwt = makeJWT(payload: #"{"iss":"https://clerk.auth.liftinglog.app","sub":"user_123"}"#)

        XCTAssertEqual(
            ClerkJWTIdentityResolver.ownerTokenIdentifier(from: jwt),
            "https://clerk.auth.liftinglog.app|user_123"
        )
    }

    func testOwnerTokenIdentifierRejectsMalformedToken() {
        XCTAssertNil(ClerkJWTIdentityResolver.ownerTokenIdentifier(from: "not-a-jwt"))
    }

    func testOwnerTokenIdentifierRejectsMissingRequiredClaims() {
        let jwt = makeJWT(payload: #"{"iss":"https://clerk.auth.liftinglog.app"}"#)

        XCTAssertNil(ClerkJWTIdentityResolver.ownerTokenIdentifier(from: jwt))
    }

    func testIssuerFromPublishableKeyUsesDecodedFrontendHost() {
        XCTAssertEqual(
            ClerkJWTIdentityResolver.issuer(
                fromPublishableKey: "pk_test_Z2xhZC1rcmlsbC0yMi5jbGVyay5hY2NvdW50cy5kZXYk"
            ),
            "https://glad-krill-22.clerk.accounts.dev"
        )
        XCTAssertEqual(
            ClerkJWTIdentityResolver.issuer(
                fromPublishableKey: "pk_live_Y2xlcmsuYXV0aC5saWZ0aW5nbG9nLmFwcCQ"
            ),
            "https://clerk.auth.liftinglog.app"
        )
    }

    func testIssuerFromPublishableKeyRejectsMalformedKeys() {
        XCTAssertNil(ClerkJWTIdentityResolver.issuer(fromPublishableKey: "not-a-key"))
        XCTAssertNil(ClerkJWTIdentityResolver.issuer(fromPublishableKey: "pk_test_"))
    }

    private func makeJWT(payload: String) -> String {
        [
            base64URL("{}"),
            base64URL(payload),
            "signature",
        ].joined(separator: ".")
    }

    private func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
