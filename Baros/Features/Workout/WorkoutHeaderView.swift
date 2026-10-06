import SwiftUI

struct WorkoutHeaderView: View {
    let startedAt: Date
    let completedSets: Int
    let totalSets: Int
    let restTimer: RestTimerCoordinator
    let onFinish: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                WorkoutHeaderMetrics(startedAt: startedAt, completedSets: completedSets,
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

/// Timer state and ticks stay below WorkoutHeaderView's observation boundary.
private struct WorkoutHeaderMetrics: View {
    let startedAt: Date
    let completedSets: Int
    let totalSets: Int
    let timer: RestTimerCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if timer.showsHeaderFallback, let period = timer.current, period.controlsExpanded {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        RestTimerBadge(period: period, timer: timer, showsHourglass: true)
                        RestExpandedControls(period: period, timer: timer)
                    }
                    .fixedSize()
                    RestExpandedControls(period: period, timer: timer)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            } else {
                HStack(spacing: 10) {
                    if timer.showsHeaderFallback, let period = timer.current {
                        RestTimerBadge(period: period, timer: timer, showsHourglass: true)
                            .transition(.opacity)
                    } else {
                        elapsedTime
                            .transition(.opacity)
                    }
                    setProgress
                }
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.2), value: timer.showsHeaderFallback)
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

    private var setProgress: some View {
        HStack(spacing: 10) {
            ProgressView(value: totalSets > 0 ? Double(completedSets) / Double(totalSets) : 0)
                .progressViewStyle(.linear)
                .tint(AppTheme.brandAccentFill)
            Text("\(completedSets)/\(totalSets)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 44)
        .glassEffect(.regular)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(completedSets) of \(totalSets) sets completed")
    }
}
