import Foundation

struct SyncStatusDisplayState {
    enum Kind: Equatable {
        case localOnly
        case syncing
        case waiting
        case upToDate
        case needsAttention
    }

    enum Tint: Equatable {
        case secondary
        case attention
        case success
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let detailText: String?
    let trailingText: String
    let systemImage: String
    let tint: Tint
    let canRetry: Bool
    let showsGlobalFailureNotice: Bool
    let failureNoticeTitle: String?
    let failureNoticeMessage: String?
    let userVisibleFailureMessage: String?

    static func make(
        ownerTokenIdentifier: String?,
        isSyncing: Bool,
        lastSyncedAt: Date?,
        lastFailureMessage: String?,
        lastFailureReason: SyncScheduler.FailureReason? = nil,
        pendingCount: Int,
        failedCount: Int,
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

        if isSyncing {
            return SyncStatusDisplayState(
                kind: .syncing,
                title: "Sync Status",
                subtitle: "Sending and receiving changes.",
                detailText: countsText(pendingCount: pendingCount, failedCount: failedCount, lastSyncedAt: lastSyncedAt, now: now),
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
                tint: .attention,
                canRetry: true,
                showsGlobalFailureNotice: true,
                failureNoticeTitle: failureCopy.noticeTitle,
                failureNoticeMessage: failureCopy.noticeMessage,
                userVisibleFailureMessage: failureCopy.userVisibleFailureMessage
            )
        }

        if pendingCount > 0 {
            return SyncStatusDisplayState(
                kind: .waiting,
                title: "Sync Status",
                subtitle: "\(pendingCount) \(pendingCount == 1 ? "change" : "changes") waiting for cloud sync.",
                detailText: lastSyncedText(lastSyncedAt, now: now).map { "Last synced \($0)." },
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

    private static func countsText(
        pendingCount: Int,
        failedCount: Int,
        lastSyncedAt: Date?,
        now: Date
    ) -> String? {
        var workParts: [String] = []
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

struct SyncFailureNoticePresentation {
    func shouldShowNotice(
        showsGlobalFailureNotice: Bool,
        currentFailureSignature: String?,
        dismissedFailureSignature: String?
    ) -> Bool {
        guard showsGlobalFailureNotice, let currentFailureSignature else {
            return false
        }
        return currentFailureSignature != dismissedFailureSignature
    }

    func dismissedSignature(
        currentFailureSignature: String?,
        dismissedFailureSignature: String?
    ) -> String? {
        currentFailureSignature ?? dismissedFailureSignature
    }
}

struct SyncDiagnosticsEntry {
    let entityKind: String
    let operation: String
    let status: String
    let ownerTokenIdentifier: String?
    let attemptCount: Int
    let updatedAt: Date
    let lastErrorMessage: String?
}

struct SyncDiagnosticsSnapshot {
    let summary: String

    static func make(
        ownerTokenIdentifier: String?,
        isSyncing: Bool,
        lastFailureMessage: String?,
        entries: [SyncDiagnosticsEntry]
    ) -> SyncDiagnosticsSnapshot {
        let failedCount = entries.filter { $0.status == SyncOutboxStatus.failed.rawValue }.count
        let pendingCount = entries.filter { $0.status == SyncOutboxStatus.pending.rawValue }.count
        let inFlightCount = entries.filter { $0.status == SyncOutboxStatus.inFlight.rawValue }.count

        var lines = [
            "owner: \(ownerTokenIdentifier ?? "nil")",
            "isSyncing: \(isSyncing)",
            "lastFailure: \(lastFailureMessage ?? "nil")",
            "pending: \(pendingCount)",
            "inFlight: \(inFlightCount)",
            "failed: \(failedCount)",
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
