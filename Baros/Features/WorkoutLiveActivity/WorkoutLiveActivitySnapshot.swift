import Foundation

struct WorkoutLiveActivitySnapshot: Equatable, Sendable {
    let workoutID: UUID
    let title: String
    let startedAt: Date
    let completedSetCount: Int
    let totalSetCount: Int
    let restStartedAt: Date?
    let restEndsAt: Date?

    init(session: WorkoutSession, restPeriod: RestTimerPeriod? = nil) {
        let metrics = WorkoutMetrics(session: session)
        workoutID = session.id
        title = session.title
        startedAt = session.startedAt
        completedSetCount = metrics.completedSetCount
        totalSetCount = metrics.totalSetCount
        let rest = restPeriod.flatMap { period in
            !period.isFinished && !period.rest.wasSkipped && period.rest.sessionID == session.id
                ? period.rest : nil
        }
        restStartedAt = rest?.startedAt
        restEndsAt = rest?.endsAt
    }

    var attributes: WorkoutLiveActivityAttributes {
        WorkoutLiveActivityAttributes(workoutID: workoutID, startedAt: startedAt)
    }

    var contentState: WorkoutLiveActivityAttributes.ContentState {
        WorkoutLiveActivityAttributes.ContentState(
            title: title,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount,
            restStartedAt: restStartedAt,
            restEndsAt: restEndsAt
        )
    }
}
