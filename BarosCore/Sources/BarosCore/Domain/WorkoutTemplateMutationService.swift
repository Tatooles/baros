import Foundation
import SwiftData

@MainActor
public struct WorkoutTemplateMutationService {
    private let recorder = SyncOutboxRecorder()
    private let syncScheduler: SyncScheduler?

    public init(syncScheduler: SyncScheduler? = nil) {
        self.syncScheduler = syncScheduler
    }

    @discardableResult
    public func createTemplate(
        name: String,
        entries: [WorkoutTemplateEntry],
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws -> WorkoutTemplate {
        let effectiveOwner = ownerTokenIdentifier ?? syncScheduler?.currentOwnerTokenIdentifier
        let template = WorkoutTemplate(
            name: name,
            entries: Self.normalized(entries),
            syncOwnerTokenIdentifier: effectiveOwner,
            createdAt: now,
            updatedAt: now
        )
        context.insert(template)
        try recorder.recordCreate(
            entityKind: .workoutTemplate,
            entityID: template.id,
            ownerTokenIdentifier: effectiveOwner,
            context: context,
            now: now
        )
        try context.save()
        syncScheduler?.requestSync()
        return template
    }

    public func updateTemplate(
        _ template: WorkoutTemplate,
        name: String,
        entries: [WorkoutTemplateEntry],
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        let entries = Self.normalized(entries)
        guard template.name != name || template.entries != entries else { return }

        let effectiveOwner = try mutationOwner(
            currentOwner: template.syncOwnerTokenIdentifier,
            requestedOwner: ownerTokenIdentifier ?? syncScheduler?.currentOwnerTokenIdentifier
        )
        template.syncOwnerTokenIdentifier = effectiveOwner ?? template.syncOwnerTokenIdentifier
        template.name = name
        template.entries = entries
        template.updatedAt = now
        try recorder.recordUpdate(
            entityKind: .workoutTemplate,
            entityID: template.id,
            ownerTokenIdentifier: effectiveOwner,
            context: context,
            now: now
        )
        try context.save()
        syncScheduler?.requestSync()
    }

    public func deleteTemplate(
        _ template: WorkoutTemplate,
        ownerTokenIdentifier: String? = nil,
        context: ModelContext,
        now: Date = .now
    ) throws {
        guard !template.isDeleted else { return }

        let effectiveOwner = try mutationOwner(
            currentOwner: template.syncOwnerTokenIdentifier,
            requestedOwner: ownerTokenIdentifier ?? syncScheduler?.currentOwnerTokenIdentifier
        )
        template.syncOwnerTokenIdentifier = effectiveOwner ?? template.syncOwnerTokenIdentifier
        template.deletedAt = now
        template.updatedAt = now
        try recorder.recordDelete(
            entityKind: .workoutTemplate,
            entityID: template.id,
            ownerTokenIdentifier: effectiveOwner,
            context: context,
            now: now
        )
        try context.save()
        syncScheduler?.requestSync()
    }

    private static func normalized(_ entries: [WorkoutTemplateEntry]) -> [WorkoutTemplateEntry] {
        let groupIDs = SupersetGrouping.normalized(entries.map(\.supersetGroupID))
        return zip(entries, groupIDs).map { entry, groupID in
            var entry = entry
            entry.supersetGroupID = groupID
            return entry
        }
    }

    private func mutationOwner(currentOwner: String?, requestedOwner: String?) throws -> String? {
        guard let currentOwner else { return requestedOwner }
        guard let requestedOwner, requestedOwner != currentOwner else { return currentOwner }
        throw SyncMutationOwnershipError.ownerMismatch
    }
}
