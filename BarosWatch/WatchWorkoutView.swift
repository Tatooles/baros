import SwiftUI

/// One screen: heart rate, elapsed time, and End. Nothing is logged here.
struct WatchWorkoutView: View {
    let manager: WatchWorkoutManager
    @State private var isConfirmingEnd = false

    var body: some View {
        switch manager.phase {
        case .idle:
            VStack(spacing: 6) {
                Text("Baros")
                    .font(.headline)
                Text("Start a workout on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityIdentifier("BarosWatchIdle")
        case .waitingForClaim:
            VStack(spacing: 8) {
                ProgressView()
                Text("Starting…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .recording, .ending:
            workout
        }
    }

    private var workout: some View {
        VStack(spacing: 10) {
            if let startDate = manager.startDate {
                TimelineView(.periodic(from: startDate, by: 1)) { timeline in
                    Text(Self.elapsed(from: startDate, to: timeline.date))
                        .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                        .accessibilityLabel("Elapsed time \(Self.elapsed(from: startDate, to: timeline.date))")
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text(manager.heartRate.map(String.init) ?? "--")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("BPM")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(manager.heartRate.map { "Heart rate \($0) beats per minute" } ?? "Heart rate unavailable")

            Button("End", role: .destructive) {
                isConfirmingEnd = true
            }
            .disabled(manager.phase == .ending)
            .accessibilityIdentifier("BarosWatchEnd")
        }
        .confirmationDialog(
            "End on Watch?",
            isPresented: $isConfirmingEnd
        ) {
            Button("End", role: .destructive) { manager.endFromWatch() }
        } message: {
            Text("Finish the workout on your iPhone to save it to Health. Ending here saves only if your iPhone has already finished it.")
        }
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}
