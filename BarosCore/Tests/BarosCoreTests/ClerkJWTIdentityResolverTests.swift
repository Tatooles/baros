import XCTest
@testable import BarosCore

final class ClerkJWTIdentityResolverTests: XCTestCase {
    func testOwnerTokenIdentifierUsesIssuerAndSubjectClaims() {
        let jwt = makeJWT(payload: #"{"iss":"https://clerk.baros.fit","sub":"user_123"}"#)

        XCTAssertEqual(
            ClerkJWTIdentityResolver.ownerTokenIdentifier(from: jwt),
            "https://clerk.baros.fit|user_123"
        )
    }

    func testOwnerTokenIdentifierRejectsMalformedToken() {
        XCTAssertNil(ClerkJWTIdentityResolver.ownerTokenIdentifier(from: "not-a-jwt"))
    }

    func testOwnerTokenIdentifierRejectsMissingRequiredClaims() {
        let jwt = makeJWT(payload: #"{"iss":"https://clerk.baros.fit"}"#)

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
                fromPublishableKey: "pk_live_Y2xlcmsuYmFyb3MuZml0JA"
            ),
            "https://clerk.baros.fit"
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
