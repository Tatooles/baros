import Foundation

struct WorkoutLiveActivitySnapshot: Equatable, Sendable {
    let workoutID: UUID
    let title: String
    let startedAt: Date
    let completedSetCount: Int
    let totalSetCount: Int

    init(session: WorkoutSession) {
        let metrics = WorkoutMetrics(session: session)
        workoutID = session.id
        title = session.title
        startedAt = session.startedAt
        completedSetCount = metrics.completedSetCount
        totalSetCount = metrics.totalSetCount
    }

    var attributes: WorkoutActivityAttributes {
        WorkoutActivityAttributes(workoutID: workoutID, startedAt: startedAt)
    }

    var contentState: WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            title: title,
            completedSetCount: completedSetCount,
            totalSetCount: totalSetCount
        )
    }
}
