import Foundation
import SwiftData

public struct PreviousSetsCacheSaveChanges: Sendable {
    public let insertedIDs: Set<PersistentIdentifier>
    public let updatedIDs: Set<PersistentIdentifier>
    public let deletedIDs: Set<PersistentIdentifier>
    public let invalidatedAllIdentifiers: Bool

    public var containsOnlySyncBookkeeping: Bool {
        guard !invalidatedAllIdentifiers else { return false }
        let identifiers = insertedIDs.union(updatedIDs).union(deletedIDs)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy {
            $0.entityName == String(describing: SyncOutboxEntry.self)
                || $0.entityName == String(describing: SyncCursorState.self)
        }
    }

    public init(notification: Notification) {
        insertedIDs = Self.identifiers(for: .insertedIdentifiers, in: notification)
        updatedIDs = Self.identifiers(for: .updatedIdentifiers, in: notification)
        deletedIDs = Self.identifiers(for: .deletedIdentifiers, in: notification)
        invalidatedAllIdentifiers = notification.userInfo?[
            ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue
        ] as? Bool ?? false
    }

    private init(
        insertedIDs: Set<PersistentIdentifier>,
        updatedIDs: Set<PersistentIdentifier>,
        deletedIDs: Set<PersistentIdentifier>,
        invalidatedAllIdentifiers: Bool
    ) {
        self.insertedIDs = insertedIDs
        self.updatedIDs = updatedIDs
        self.deletedIDs = deletedIDs
        self.invalidatedAllIdentifiers = invalidatedAllIdentifiers
    }

    func merging(_ other: Self) -> Self {
        Self(
            insertedIDs: insertedIDs.union(other.insertedIDs),
            updatedIDs: updatedIDs.union(other.updatedIDs),
            deletedIDs: deletedIDs.union(other.deletedIDs),
            invalidatedAllIdentifiers: invalidatedAllIdentifiers || other.invalidatedAllIdentifiers
        )
    }

    private static func identifiers(
        for key: ModelContext.NotificationKey,
        in notification: Notification
    ) -> Set<PersistentIdentifier> {
        let value = notification.userInfo?[key.rawValue]
        if let identifiers = value as? Set<PersistentIdentifier> {
            return identifiers
        }
        if let identifiers = value as? [PersistentIdentifier] {
            return Set(identifiers)
        }
        return []
    }
}

/// Hands `ModelContext.didSave` changes to a handler after the save that posted
/// them returns, merging a burst of saves into one call.
///
/// SwiftData posts `didSave` from inside `save()`, so a receiver that reads models
/// or fetches runs inside whoever saved. BAROS-IOS-1M: Sentry reported a main-thread
/// hang while the active workout reloaded Previous sets inside owner activation's
/// seed save.
@MainActor
public final class DeferredSaveChanges {
    private var pending: PreviousSetsCacheSaveChanges?
    private var handler: (@MainActor (PreviousSetsCacheSaveChanges) -> Void)?

    public init() {}

    /// Calls the latest `handler` once on a later main-actor turn with every change
    /// enqueued until then.
    public func enqueue(
        _ changes: PreviousSetsCacheSaveChanges,
        handler: @escaping @MainActor (PreviousSetsCacheSaveChanges) -> Void
    ) {
        self.handler = handler
        if let pending {
            self.pending = pending.merging(changes)
            return
        }
        pending = changes
        Task { @MainActor [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        guard let changes = pending, let handler else { return }
        pending = nil
        self.handler = nil
        handler(changes)
    }
}
