import Foundation
import SwiftData

/// The save-and-roll-back mechanics for the Unclaimed Local Data path, which
/// has no owner destination and therefore records no outbox intent. ADR 0002
/// deliberately keeps this path in the domain modules rather than behind a
/// second shared transaction; this type only fixes rollback ownership.
///
/// Whichever layer performs the save owns the matching rollback:
/// `SyncOutboxTransaction` rolls back the owner-scoped path and restores the
/// unsaved in-flight outbox bookkeeping it found, and this type rolls back the
/// local-only path. Callers must not roll back on top of either, because a
/// second `rollback()` discards that restored bookkeeping and can resurrect an
/// already-completed intent or push an in-flight one twice.
@MainActor
struct LocalOnlyMutation {
    private let save: @MainActor (ModelContext) throws -> Void

    init(save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() }) {
        self.save = save
    }

    func perform(in context: ModelContext, mutation: () throws -> Void) throws {
        do {
            try mutation()
            try save(context)
        } catch {
            // Unclaimed Local Data records no outbox intents, so any outbox
            // bookkeeping in the shared context belongs to a suspended sync and
            // must survive this rollback.
            OutboxBookkeepingSnapshot.rollbackPreservingBookkeeping(in: context)
            throw error
        }
    }
}
