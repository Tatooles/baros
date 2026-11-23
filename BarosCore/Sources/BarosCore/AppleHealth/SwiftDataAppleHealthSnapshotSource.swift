import Foundation
import SwiftData

/// Reads committed workouts for the Apple Health recorder from a fresh `ModelContext`, so unsaved
/// edits in the main context are never seen (ADR 0005, "Committed state only").
@MainActor
public final class SwiftDataAppleHealthSnapshotSource: AppleHealthWorkoutSnapshotSource {
    public struct OwnerUnresolved: Error {}

    private let container: ModelContainer
    /// The Current Owner's token, or `.unresolved` while startup can't yet say who owns local data.
    private let currentOwner: () -> CurrentOwnerVisibility

    public enum CurrentOwnerVisibility: Equatable, Sendable {
        case unresolved
        case resolved(ownerTokenIdentifier: String?)
    }

    public init(container: ModelContainer, currentOwner: @escaping () -> CurrentOwnerVisibility) {
        self.container = container
        self.currentOwner = currentOwner
    }

    public func snapshots(includingWorkoutIDs workoutIDs: Set<UUID>) throws -> [AppleHealthWorkoutSnapshot] {
        // Visibility depends on the owner, so an unknown owner is "unknown", not "hidden".
        guard case let .resolved(ownerTokenIdentifier) = currentOwner() else { throw OwnerUnresolved() }
        let sessions = try ModelContext(container).fetch(FetchDescriptor<WorkoutSession>())
        return sessions
            .filter { $0.status == .active || workoutIDs.contains($0.id) }
            .map { session in
                AppleHealthWorkoutSnapshot(
                    workoutID: session.id,
                    status: Self.status(session.status),
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    updatedAt: session.updatedAt,
                    isDeleted: session.deletedAt != nil,
                    isVisible: !WorkoutSession.visibleActiveSessions(
                        from: [session],
                        ownerTokenIdentifier: ownerTokenIdentifier
                    ).isEmpty || session.status != .active
                )
            }
    }

    private static func status(_ status: WorkoutSessionStatus) -> AppleHealthWorkoutSnapshot.Status {
        switch status {
        case .active: .active
        case .completed: .completed
        case .discarded: .discarded
        }
    }
}
