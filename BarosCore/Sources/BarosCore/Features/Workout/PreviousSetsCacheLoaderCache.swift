import Foundation
import SwiftData

/// Keeps the active workout's Previous sets current without fetching history
/// for every save.
@MainActor
public final class PreviousSetsCacheLoaderCache {
    private struct ActiveStructureKey: Equatable {
        private struct ExerciseEntry: Equatable {
            let id: UUID
            let routeID: String
            let sourceLoggedExerciseID: UUID?
            let setIDs: [UUID]
        }

        let sessionID: UUID
        let sourceSessionID: UUID?
        private let exerciseEntries: [ExerciseEntry]

        init(session: WorkoutSession) {
            sessionID = session.id
            sourceSessionID = session.source == .pastWorkout ? session.sourceSessionID : nil
            exerciseEntries = session.sortedLoggedExercises.map { loggedExercise in
                ExerciseEntry(
                    id: loggedExercise.id,
                    routeID: ExerciseHistoryRoute(loggedExercise: loggedExercise).id,
                    sourceLoggedExerciseID: loggedExercise.sourceLoggedExerciseID,
                    setIDs: loggedExercise.sortedSets.map(\.id)
                )
            }
        }
    }

    private var activeStructureKey: ActiveStructureKey?
    /// Set before the fetch, so a failed fetch still records which workout is shown.
    private var loadedSessionID: UUID?
    private var cacheKey: PreviousSetPerformance.CacheKey?
    private let deferredSaves = DeferredSaveChanges()
    private let fetchSessions: @MainActor (ModelContext, String?) throws -> [WorkoutSession]

    public init(
        fetchSessions: (@MainActor (ModelContext, String?) throws -> [WorkoutSession])? = nil
    ) {
        self.fetchSessions = fetchSessions ?? Self.fetchCompletedHistory
    }

    /// Reads no models here: this runs inside the `save()` that posted the
    /// notification. The reload waits for a later main-actor turn.
    public func scheduleReload(
        after notification: Notification,
        context: ModelContext,
        reload: @escaping @MainActor (PreviousSetsCacheSaveChanges) -> Void
    ) {
        guard let changes = Self.relevantChanges(in: notification, for: context) else { return }
        deferredSaves.enqueue(changes, handler: reload)
    }

    public func reloadIfNeeded(
        for changes: PreviousSetsCacheSaveChanges,
        session: WorkoutSession,
        context: ModelContext,
        ownerTokenIdentifier: String?,
        lastSyncedAt: Date?,
        onUpdate: ([UUID: [PreviousSetPerformance]]) -> Void
    ) {
        // A queued reload can outlive the workout it was queued for: the workout
        // finished, or the sheet now shows another owner's workout, which its own
        // trigger reload already covered.
        guard isShown(session, ownerTokenIdentifier: ownerTokenIdentifier) else { return }
        guard PreviousSetsCacheReloadPolicy.shouldReload(
            insertedIDs: changes.insertedIDs,
            updatedIDs: changes.updatedIDs,
            deletedIDs: changes.deletedIDs,
            activeGraphIDs: activeGraphIDs(for: session),
            activeStructureChanged: activeStructureChanged(for: session),
            invalidatedAllIdentifiers: changes.invalidatedAllIdentifiers
        ) else { return }

        reload(
            session: session,
            context: context,
            ownerTokenIdentifier: ownerTokenIdentifier,
            lastSyncedAt: lastSyncedAt,
            onUpdate: onUpdate
        )
    }

    private func isShown(_ session: WorkoutSession, ownerTokenIdentifier: String?) -> Bool {
        if let loadedSessionID, loadedSessionID != session.id {
            return false
        }
        return !WorkoutSession.visibleActiveSessions(
            from: [session],
            ownerTokenIdentifier: ownerTokenIdentifier
        ).isEmpty
    }

    static func relevantChanges(
        in notification: Notification,
        for context: ModelContext
    ) -> PreviousSetsCacheSaveChanges? {
        if let savedContext = notification.object as? ModelContext,
           savedContext.container !== context.container {
            return nil
        }
        let changes = PreviousSetsCacheSaveChanges(notification: notification)
        return changes.containsOnlySyncBookkeeping ? nil : changes
    }

    static func fetchCompletedHistory(
        context: ModelContext,
        ownerTokenIdentifier: String?
    ) throws -> [WorkoutSession] {
        let completedStatus = WorkoutSessionStatus.completed.rawValue
        return try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.statusRaw == completedStatus
                    && session.deletedAt == nil
                    && (session.syncOwnerTokenIdentifier == ownerTokenIdentifier
                        || session.syncOwnerTokenIdentifier == nil)
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
    }

    func activeGraphIDs(for session: WorkoutSession) -> Set<PersistentIdentifier> {
        var identifiers: Set<PersistentIdentifier> = [session.persistentModelID]
        for loggedExercise in session.loggedExercises {
            identifiers.insert(loggedExercise.persistentModelID)
            identifiers.formUnion(loggedExercise.sets.map(\.persistentModelID))
        }
        return identifiers
    }

    func activeStructureChanged(for session: WorkoutSession) -> Bool {
        ActiveStructureKey(session: session) != activeStructureKey
    }

    public func reload(
        session: WorkoutSession,
        context: ModelContext,
        ownerTokenIdentifier: String?,
        lastSyncedAt: Date?,
        onUpdate: ([UUID: [PreviousSetPerformance]]) -> Void
    ) {
        loadedSessionID = session.id
        guard let sessions = try? fetchSessions(context, ownerTokenIdentifier) else { return }

        let nextActiveStructureKey = ActiveStructureKey(session: session)
        let nextCacheKey = PreviousSetPerformance.CacheKey(
            session: session,
            sessions: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier,
            lastSyncedAt: lastSyncedAt
        )
        activeStructureKey = nextActiveStructureKey
        guard nextCacheKey != cacheKey else { return }

        cacheKey = nextCacheKey
        onUpdate(
            PreviousSetPerformance.lastCompletedSetsByExerciseID(
                for: session.sortedLoggedExercises,
                in: sessions,
                ownerTokenIdentifier: ownerTokenIdentifier,
                sourceSessionID: session.source == .pastWorkout ? session.sourceSessionID : nil
            )
        )
    }
}
