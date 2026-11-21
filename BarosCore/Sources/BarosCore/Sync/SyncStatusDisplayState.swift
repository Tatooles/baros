import Foundation

public struct SyncStatusDisplayState {
    enum Kind: Equatable {
        case localOnly
        case syncing
        case waitingForConnection
        case waiting
        case upToDate
        case needsAttention
        case blocked
    }

    public enum Tint: Equatable {
        case secondary
        case attention
        case destructive
        case success
    }

    let kind: Kind
    public let title: String
    public let subtitle: String
    public let detailText: String?
    public let trailingText: String
    public let systemImage: String
    public let tint: Tint
    public let canRetry: Bool
    public let showsGlobalFailureNotice: Bool
    public let failureNoticeTitle: String?
    public let failureNoticeMessage: String?
    let userVisibleFailureMessage: String?

    public static func make(
        ownerTokenIdentifier: String?,
        isSyncing: Bool,
        networkAvailability: NetworkAvailability = .unknown,
        transientCondition: SyncStableErrorCode? = nil,
        hasQueuedSyncRequest: Bool = false,
        lastSyncedAt: Date?,
        lastFailureMessage: String?,
        lastFailureReason: SyncScheduler.FailureReason? = nil,
        pendingCount: Int,
        failedCount: Int,
        blockedEntityKinds: [SyncEntityKind] = [],
        now: Date = .now
    ) -> SyncStatusDisplayState {
        guard ownerTokenIdentifier != nil else {
            return SyncStatusDisplayState(
                kind: .localOnly,
                title: "Sync Status",
                subtitle: "Cloud sync starts after you sign in.",
                detailText: nil,
                trailingText: "Local only",
                systemImage: "icloud.slash",
                tint: .secondary,
                canRetry: false,
                showsGlobalFailureNotice: false,
                failureNoticeTitle: nil,
                failureNoticeMessage: nil,
                userVisibleFailureMessage: nil
            )
        }

        if networkAvailability == .unavailable || networkAvailability == .requiresConnection,
           lastFailureMessage == nil,
           failedCount == 0,
           blockedEntityKinds.isEmpty {
            let canRetry = networkAvailability == .requiresConnection
            return SyncStatusDisplayState(
                kind: .waitingForConnection,
                title: "Sync Status",
                subtitle: "Waiting for connection. Your data is saved on this iPhone.",
                detailText: countsText(
                    pendingCount: pendingCount,
                    failedCount: failedCount,
                    lastSyncedAt: lastSyncedAt,
                    now: now
                ),
                trailingText: canRetry ? "Retry" : "Offline",
                systemImage: "icloud.slash",
                tint: .secondary,
                canRetry: canRetry,
                showsGlobalFailureNotice: false,
                failureNoticeTitle: nil,
                failureNoticeMessage: nil,
                userVisibleFailureMessage: nil
            )
        }

        if isSyncing,
           networkAvailability != .unavailable,
           networkAvailability != .requiresConnection {
            return SyncStatusDisplayState(
                kind: .syncing,
                title: "Sync Status",
                subtitle: "Sending and receiving changes.",
                detailText: nil,
                trailingText: "Syncing",
                systemImage: "arrow.triangle.2.circlepath.icloud",
                tint: .attention,
                canRetry: false,
                showsGlobalFailureNotice: false,
                failureNoticeTitle: nil,
                failureNoticeMessage: nil,
                userVisibleFailureMessage: nil
            )
        }

        // Dead-lettered changes wait for the person: say what they are, and
        // that Retry sends them again.
        if !blockedEntityKinds.isEmpty {
            let what = blockedChangesDescription(blockedEntityKinds)
            let title = "Some changes can't sync"
            let subtitle = "The cloud turned down \(what). \(blockedEntityKinds.count == 1 ? "It's" : "They're") still saved on this iPhone."
            return SyncStatusDisplayState(
                kind: .blocked,
                title: title,
                subtitle: subtitle,
                detailText: countsText(
                    pendingCount: pendingCount,
                    failedCount: failedCount,
                    blockedCount: blockedEntityKinds.count,
                    lastSyncedAt: lastSyncedAt,
                    now: now
                ),
                trailingText: "Retry",
                systemImage: "exclamationmark.icloud",
                tint: .destructive,
                canRetry: true,
                showsGlobalFailureNotice: true,
                failureNoticeTitle: title,
                failureNoticeMessage: "The cloud turned down \(what). Retry to send \(blockedEntityKinds.count == 1 ? "it" : "them") again.",
                userVisibleFailureMessage: subtitle
            )
        }

        if failedCount > 0 || lastFailureMessage != nil {
            let failureCopy = displayCopy(forFailureReason: lastFailureReason)
            let fallbackDetailText: String? = failureCopy.suppressesDetailFallback
                ? nil
                : sanitizedFailureReason(from: lastFailureMessage ?? "")
            return SyncStatusDisplayState(
                kind: .needsAttention,
                title: failureCopy.statusTitle,
                subtitle: failureCopy.statusMessage,
                detailText: countsText(pendingCount: pendingCount, failedCount: failedCount, lastSyncedAt: lastSyncedAt, now: now)
                    ?? fallbackDetailText,
                trailingText: "Retry",
                systemImage: "exclamationmark.icloud",
                tint: .destructive,
                canRetry: true,
                showsGlobalFailureNotice: true,
                failureNoticeTitle: failureCopy.noticeTitle,
                failureNoticeMessage: failureCopy.noticeMessage,
                userVisibleFailureMessage: failureCopy.userVisibleFailureMessage
            )
        }

        if transientCondition == .networkUnavailable {
            let isKnownOffline = networkAvailability == .unavailable
            return SyncStatusDisplayState(
                kind: .waitingForConnection,
                title: "Sync Status",
                subtitle: "Waiting for connection. Your data is saved on this iPhone.",
                detailText: countsText(
                    pendingCount: pendingCount,
                    failedCount: failedCount,
                    lastSyncedAt: lastSyncedAt,
                    now: now
                ),
                trailingText: isKnownOffline ? "Offline" : "Retry",
                systemImage: "icloud.slash",
                tint: .secondary,
                canRetry: !isKnownOffline,
                showsGlobalFailureNotice: false,
                failureNoticeTitle: nil,
                failureNoticeMessage: nil,
                userVisibleFailureMessage: nil
            )
        }

        if transientCondition != nil {
            return SyncStatusDisplayState(
                kind: .waiting,
                title: "Sync Status",
                subtitle: "Cloud sync was interrupted. Your data is saved on this iPhone.",
                detailText: countsText(
                    pendingCount: pendingCount,
                    failedCount: failedCount,
                    lastSyncedAt: lastSyncedAt,
                    now: now
                ),
                trailingText: "Retry",
                systemImage: "icloud.and.arrow.up",
                tint: .secondary,
                canRetry: true,
                showsGlobalFailureNotice: false,
                failureNoticeTitle: nil,
                failureNoticeMessage: nil,
                userVisibleFailureMessage: nil
            )
        }

        if pendingCount > 0 || hasQueuedSyncRequest {
            let subtitle = if pendingCount > 0 {
                "\(pendingCount) \(pendingCount == 1 ? "change" : "changes") waiting for cloud sync."
            } else {
                "Cloud sync is waiting to resume."
            }
            return SyncStatusDisplayState(
                kind: .waiting,
                title: "Sync Status",
                subtitle: subtitle,
                detailText: nil,
                trailingText: "Waiting",
                systemImage: "icloud.and.arrow.up",
                tint: .secondary,
                canRetry: true,
                showsGlobalFailureNotice: false,
                failureNoticeTitle: nil,
                failureNoticeMessage: nil,
                userVisibleFailureMessage: nil
            )
        }

        return SyncStatusDisplayState(
            kind: .upToDate,
            title: "Sync Status",
            subtitle: lastSyncedText(lastSyncedAt, now: now).map { "Last synced \($0)." } ?? "Cloud sync is ready.",
            detailText: nil,
            trailingText: "Up to date",
            systemImage: "checkmark.icloud",
            tint: .success,
            canRetry: false,
            showsGlobalFailureNotice: false,
            failureNoticeTitle: nil,
            failureNoticeMessage: nil,
            userVisibleFailureMessage: nil
        )
    }

    private static func displayCopy(forFailureReason reason: SyncScheduler.FailureReason?) -> (
        statusTitle: String,
        statusMessage: String,
        noticeTitle: String,
        noticeMessage: String,
        userVisibleFailureMessage: String,
        suppressesDetailFallback: Bool
    ) {
        if reason == .incompleteRemotePull {
            let title = "Cloud sync could not finish"
            let message = "Some cloud workout data is incomplete. Your local data is still available."
            return (
                statusTitle: title,
                statusMessage: message,
                noticeTitle: title,
                noticeMessage: message,
                userVisibleFailureMessage: message,
                suppressesDetailFallback: true
            )
        }

        let statusMessage = "Cloud sync could not finish. Your data is saved on this iPhone."
        return (
            statusTitle: "Sync Status",
            statusMessage: statusMessage,
            noticeTitle: "Cloud sync failed",
            noticeMessage: "Your data is saved on this iPhone.",
            userVisibleFailureMessage: statusMessage,
            suppressesDetailFallback: false
        )
    }

    static func sanitizedFailureReason(from message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("offline") || lowercased.contains("internet connection") || lowercased.contains("network") {
            return "The network appears to be offline."
        }
        if lowercased.contains("unauthorized") || lowercased.contains("auth") || lowercased.contains("sign in") {
            return "Sign in again to continue syncing."
        }
        if lowercased.contains("timed out") || lowercased.contains("could not connect") || lowercased.contains("service") {
            return "The service could not be reached."
        }
        return "Cloud sync could not finish. Your data is saved on this iPhone."
    }

    /// Names blocked changes by what a person calls them, such as "1 set" or
    /// "1 workout and 2 sets".
    static func blockedChangesDescription(_ kinds: [SyncEntityKind]) -> String {
        let order: [SyncEntityKind] = [.workoutSession, .loggedExercise, .loggedSet, .exercise, .workoutTemplate, .userSettings]
        let counts = Dictionary(kinds.map { ($0, 1) }, uniquingKeysWith: +)
        let parts = order.compactMap { kind -> String? in
            guard let count = counts[kind] else { return nil }
            let (singular, plural) = switch kind {
            case .workoutSession: ("workout", "workouts")
            case .loggedExercise: ("exercise in a workout", "exercises in workouts")
            case .loggedSet: ("set", "sets")
            case .exercise: ("exercise", "exercises")
            case .workoutTemplate: ("template", "templates")
            case .userSettings: ("settings change", "settings changes")
            case .healthDataLink, .seedMetadata: ("change", "changes")
            }
            return "\(count) \(count == 1 ? singular : plural)"
        }
        switch parts.count {
        case 0: return "\(kinds.count) \(kinds.count == 1 ? "change" : "changes")"
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }

    private static func countsText(
        pendingCount: Int,
        failedCount: Int,
        blockedCount: Int = 0,
        lastSyncedAt: Date?,
        now: Date
    ) -> String? {
        var workParts: [String] = []
        if blockedCount > 0 {
            workParts.append("\(blockedCount) blocked")
        }
        if failedCount > 0 {
            workParts.append("\(failedCount) failed")
        }
        if pendingCount > 0 {
            workParts.append("\(pendingCount) waiting")
        }
        var sentences: [String] = []
        if !workParts.isEmpty {
            sentences.append(workParts.joined(separator: ", "))
        }
        if let lastSynced = lastSyncedText(lastSyncedAt, now: now) {
            sentences.append("Last synced \(lastSynced)")
        }
        guard !sentences.isEmpty else { return nil }
        return sentences.joined(separator: ". ") + "."
    }

    private static func lastSyncedText(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        let days = hours / 24
        return "\(days) d ago"
    }
}

public struct SyncFailureNoticePresentation {
    public init() {}

    public func shouldShowNotice(
        showsGlobalFailureNotice: Bool,
        currentFailureSignature: String?,
        dismissedFailureSignature: String?
    ) -> Bool {
        guard showsGlobalFailureNotice, let currentFailureSignature else {
            return false
        }
        return currentFailureSignature != dismissedFailureSignature
    }

    public func dismissedSignature(
        currentFailureSignature: String?,
        dismissedFailureSignature: String?
    ) -> String? {
        currentFailureSignature ?? dismissedFailureSignature
    }
}

public struct SyncDiagnosticsEntry {
    let entityKind: String
    let operation: String
    let status: String
    let ownerTokenIdentifier: String?
    let attemptCount: Int
    let updatedAt: Date
    let lastErrorMessage: String?

    public init(
        entityKind: String,
        operation: String,
        status: String,
        ownerTokenIdentifier: String?,
        attemptCount: Int,
        updatedAt: Date,
        lastErrorMessage: String?
    ) {
        self.entityKind = entityKind
        self.operation = operation
        self.status = status
        self.ownerTokenIdentifier = ownerTokenIdentifier
        self.attemptCount = attemptCount
        self.updatedAt = updatedAt
        self.lastErrorMessage = lastErrorMessage
    }
}

public struct SyncDiagnosticsSnapshot {
    public let summary: String

    public static func make(
        ownerTokenIdentifier: String?,
        isSyncing: Bool,
        lastFailureMessage: String?,
        entries: [SyncDiagnosticsEntry]
    ) -> SyncDiagnosticsSnapshot {
        let failedCount = entries.filter { $0.status == SyncOutboxStatus.failed.rawValue }.count
        let pendingCount = entries.filter { $0.status == SyncOutboxStatus.pending.rawValue }.count
        let inFlightCount = entries.filter { $0.status == SyncOutboxStatus.inFlight.rawValue }.count
        let blockedCount = entries.filter { $0.status == SyncOutboxStatus.blocked.rawValue }.count

        var lines = [
            "owner: \(ownerTokenIdentifier ?? "nil")",
            "isSyncing: \(isSyncing)",
            "lastFailure: \(lastFailureMessage ?? "nil")",
            "pending: \(pendingCount)",
            "inFlight: \(inFlightCount)",
            "failed: \(failedCount)",
            "blocked: \(blockedCount)",
        ]

        guard !entries.isEmpty else {
            lines.append("activeOutbox: none")
            return SyncDiagnosticsSnapshot(summary: lines.joined(separator: "\n"))
        }

        lines.append("activeOutbox:")
        for entry in entries {
            var line = "- \(entry.entityKind) \(entry.operation) \(entry.status) attempts=\(entry.attemptCount)"
            line += " owner=\(entry.ownerTokenIdentifier ?? "nil")"
            line += " updatedAt=\(Int(entry.updatedAt.timeIntervalSince1970))"
            if let lastErrorMessage = entry.lastErrorMessage, !lastErrorMessage.isEmpty {
                line += " error=\(lastErrorMessage)"
            }
            lines.append(line)
        }

        return SyncDiagnosticsSnapshot(summary: lines.joined(separator: "\n"))
    }
}
