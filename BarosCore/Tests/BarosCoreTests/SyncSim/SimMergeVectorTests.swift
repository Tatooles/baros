import Foundation
import XCTest

/// Checks the simulator's port of the server rule against the vectors
/// `convex/syncMergeVectors.test.ts` generates from `convex/sync/merge.ts`.
final class SimMergeVectorTests: XCTestCase {
    private typealias Rule = SimMergeRule

    func testSwiftPortMatchesTheServerRule() throws {
        let vectors = try loadVectors()
        let now = try XCTUnwrap(vectors["nowSeconds"] as? Double)
        let storedCases = try XCTUnwrap(vectors["storedCases"] as? [String: Any])
        func stored(_ name: String) throws -> Rule.StoredVersion? {
            guard let row = storedCases[name] as? [String: Any] else { return nil }
            return Rule.StoredVersion(
                createdAt: row["createdAt"] as? Double,
                updatedAt: try XCTUnwrap(row["updatedAt"] as? Double),
                deletedAt: row["deletedAt"] as? Double,
                serverUpdatedAt: try XCTUnwrap(row["serverUpdatedAt"] as? Double),
                syncOrder: row["syncOrder"] as? Double
            )
        }

        let upserts = try XCTUnwrap(vectors["upsert"] as? [[Any]])
        XCTAssertGreaterThan(upserts.count, 1000)
        for vector in upserts {
            let base: Rule.Base = switch vector[3] {
            case let value as Double: .value(value)
            case is NSNull: .null
            default: .absent
            }
            let decision = Rule.decideUpsert(
                try stored(try XCTUnwrap(vector[0] as? String)),
                Rule.IncomingVersion(updatedAt: try XCTUnwrap(vector[1] as? Double), deletedAt: vector[2] as? Double, base: base),
                nowSeconds: now,
                sameContent: try XCTUnwrap(vector[4] as? Bool),
                parentDeletedAt: vector[5] as? Double
            )
            let expected = try XCTUnwrap(vector[6] as? [Any])
            XCTAssertTrue(matches(decision, expected), "upsert \(vector): Swift decided \(decision)")
        }

        for vector in try XCTUnwrap(vectors["tombstone"] as? [[Any]]) {
            let decision = Rule.decideTombstone(
                try stored(try XCTUnwrap(vector[0] as? String)),
                deletedAt: try XCTUnwrap(vector[1] as? Double),
                nowSeconds: now
            )
            let expected = try XCTUnwrap(vector[2] as? [Any])
            let actual: [Any] = switch decision {
            case let .insertPlaceholder(updatedAt, deletedAt): ["insertPlaceholder", updatedAt, deletedAt]
            case .alreadyDeleted: ["alreadyDeleted", NSNull(), NSNull()]
            case let .tombstone(updatedAt, deletedAt): ["tombstone", updatedAt, deletedAt]
            }
            XCTAssertTrue(same(actual, expected), "tombstone \(vector): Swift decided \(decision)")
        }

        for vector in try XCTUnwrap(vectors["cascade"] as? [[Double]]) {
            let result = Rule.cascadedChildVersion(childUpdatedAt: vector[0], parentUpdatedAt: vector[1], parentDeletedAt: vector[2])
            XCTAssertEqual(result.updatedAt, vector[3], accuracy: 1e-9)
            XCTAssertEqual(result.deletedAt, vector[4], accuracy: 1e-9)
        }
    }

    private func matches(_ decision: Rule.UpsertDecision, _ expected: [Any]) -> Bool {
        let actual: [Any] = switch decision {
        case .ignore:
            ["ignore", NSNull(), NSNull(), NSNull(), NSNull(), NSNull()]
        case let .insert(updatedAt, deletedAt, syncOrder, accepted):
            ["insert", updatedAt, deletedAt ?? NSNull(), syncOrder, accepted, NSNull()]
        case let .patch(takeIncomingFields, updatedAt, deletedAt, syncOrder, accepted):
            ["patch", updatedAt, deletedAt ?? NSNull(), syncOrder ?? NSNull(), accepted, takeIncomingFields]
        }
        return same(actual, expected)
    }

    private func same(_ lhs: [Any], _ rhs: [Any]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            switch (left, right) {
            case let (left as String, right as String): left == right
            case let (left as Bool, right as Bool): left == right
            case let (left as Double, right as NSNumber): abs(left - right.doubleValue) <= 1e-9
            case (is NSNull, is NSNull): true
            default: false
            }
        }
    }

    private func loadVectors() throws -> [String: Any] {
        // BarosCore/Tests/BarosCoreTests/SyncSim/<this file> -> repository root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("convex/syncSim/merge-vectors.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
