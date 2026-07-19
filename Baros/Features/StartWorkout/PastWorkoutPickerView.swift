import SwiftUI

struct PastWorkoutPickerView: View {
    let sessions: [WorkoutSession]
    let onSelect: (WorkoutSession) -> Void

    var body: some View {
        if sessions.isEmpty {
            EmptyStateView(
                title: "No Past Workouts",
                message: "Finished workouts will appear here as reusable starting points."
            )
        } else {
            VStack(spacing: 10) {
                ForEach(Array(sessions.prefix(10).enumerated()), id: \.element.id) { index, session in
                    Button {
                        onSelect(session)
                    } label: {
                        WorkoutHistoryRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("PastWorkoutButton-\(index)")
                }
            }
        }
    }
}
