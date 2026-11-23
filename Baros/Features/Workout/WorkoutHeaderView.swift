import BarosCore
import SwiftUI

struct WorkoutHeaderView: View {
    let workoutID: UUID
    let startedAt: Date
    let completedSets: Int
    let totalSets: Int
    let restTimer: RestTimerCoordinator
    let onFinish: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                WorkoutHeaderMetrics(workoutID: workoutID, startedAt: startedAt, completedSets: completedSets,
                                     totalSets: totalSets, timer: restTimer)

                Button(action: onFinish) {
                    ViewThatFits(in: .horizontal) {
                        Label {
                            Text("Finish")
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .font(.subheadline.weight(.semibold))

                        Image(systemName: "checkmark.circle.fill")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("Finish workout")
                .accessibilityIdentifier("FinishWorkoutButton")
            }
        }
        .padding(.horizontal, AppTheme.shellPadding)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

private struct WorkoutHeaderMetrics: View {
    let workoutID: UUID
    let startedAt: Date
    let completedSets: Int
    let totalSets: Int
    let timer: RestTimerCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppleHealthController.self) private var appleHealth: AppleHealthController?

    var body: some View {
        Group {
            if timer.showsHeaderFallback, let period = timer.current, period.controlsExpanded {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        RestTimerBadge(period: period, timer: timer, showsHourglass: true)
                        RestExpandedControls(period: period, timer: timer, usesGlass: true)
                        heartRate
                    }
                    .fixedSize()
                    HStack(spacing: 10) {
                        RestTimerBadge(period: period, timer: timer, showsHourglass: true)
                        RestExpandedControls(period: period, timer: timer, usesGlass: true)
                    }
                    .fixedSize()
                    RestExpandedControls(period: period, timer: timer, usesGlass: true)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                // The heart-rate pill steps aside when the row can't fit it (large text sizes); the
                // existing metrics never shrink or wrap for it.
                ViewThatFits(in: .horizontal) {
                    collapsedRow(showsHeartRate: true)
                    collapsedRow(showsHeartRate: false)
                }
            }
        }
        .animation(.easeOut(duration: reducesMotion ? 0.15 : 0.2), value: timer.showsHeaderFallback)
        .animation(reducesMotion ? nil : restControlsAnimation(reducesMotion: false), value: timer.current?.controlsExpanded)
    }

    private var reducesMotion: Bool { restTimerReducesMotion(reduceMotion) }

    private func collapsedRow(showsHeartRate: Bool) -> some View {
        HStack(spacing: 10) {
            if timer.showsHeaderFallback, let period = timer.current {
                RestTimerBadge(period: period, timer: timer, showsHourglass: true)
                    .transition(.opacity)
            } else {
                elapsedTime
                    .transition(.opacity)
            }
            if showsHeartRate {
                heartRate
            }
            setProgress(keepsCountOnOneLine: showsHeartRate)
        }
    }

    private var elapsedTime: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
            let elapsed = max(0, Int(timeline.date.timeIntervalSince(startedAt)))
            HStack(spacing: 7) {
                Circle().fill(AppTheme.brandAccentFill).frame(width: 7, height: 7)
                Text(AppTheme.formatDuration(elapsed))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .glassEffect(.regular)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Elapsed time \(AppTheme.formatDuration(elapsed))")
        }
    }

    /// Shown only while a sensor is sending readings (ADR 0005); otherwise the header has no slot for it.
    @ViewBuilder
    private var heartRate: some View {
        if let appleHealth {
            TimelineView(.periodic(from: .now, by: 5)) { timeline in
                if let beatsPerMinute = appleHealth.displayedHeartRate(for: workoutID, at: timeline.date) {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                        Text("\(beatsPerMinute)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.textPrimary)
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .glassEffect(.regular)
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Heart rate \(beatsPerMinute) beats per minute")
                    .accessibilityIdentifier("WorkoutHeaderHeartRate")
                    .transition(.opacity)
                }
            }
            .fixedSize()
        }
    }

    /// The heart-rate row keeps "12/20" on one line; without heart rate the row is unchanged.
    private func setProgress(keepsCountOnOneLine: Bool) -> some View {
        HStack(spacing: 10) {
            ProgressView(value: totalSets > 0 ? Double(completedSets) / Double(totalSets) : 0)
                .progressViewStyle(.linear)
                .tint(AppTheme.brandAccentFill)
            Text("\(completedSets)/\(totalSets)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
                .contentTransition(.numericText())
                .lineLimit(keepsCountOnOneLine ? 1 : nil)
                .fixedSize(horizontal: keepsCountOnOneLine, vertical: false)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44)
        .glassEffect(.regular)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completedSets) of \(totalSets) sets completed")
    }
}
