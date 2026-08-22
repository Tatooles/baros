import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(context: context)
                .widgetURL(WorkoutLiveActivityLink.url(for: context.attributes.workoutID))
                .activityBackgroundTint(WorkoutLiveActivityStyle.blueBlack)
                .activitySystemActionForegroundColor(WorkoutLiveActivityStyle.warmSilver)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        WorkoutLiveActivityMark(size: 28)
                        Text(context.state.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WorkoutLiveActivityStyle.warmSilver)
                            .lineLimit(1)
                    }
                    .accessibilityHidden(true)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutLiveActivityProgressDial(
                        completed: context.state.completedSetCount,
                        total: context.state.totalSetCount,
                        diameter: 38
                    )
                    .accessibilityHidden(true)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        Text(
                            timerInterval: context.attributes.startedAt...Date.distantFuture,
                            countsDown: false,
                            showsHours: true
                        )
                            .font(.title2.monospacedDigit().weight(.bold))
                            .foregroundStyle(WorkoutLiveActivityStyle.warmSilver)
                        Text("ELAPSED TIME")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(WorkoutLiveActivityStyle.warmSilver.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity)
                    .workoutLiveActivityActionAccessibility(context: context)
                }
            } compactLeading: {
                WorkoutLiveActivityMark(size: 22)
                    .accessibilityHidden(true)
            } compactTrailing: {
                Text(
                    timerInterval: context.attributes.startedAt...Date.distantFuture,
                    countsDown: false,
                    showsHours: true
                )
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(WorkoutLiveActivityStyle.warmSilver)
                    .frame(maxWidth: 52)
                    .workoutLiveActivityActionAccessibility(context: context)
            } minimal: {
                ZStack {
                    WorkoutLiveActivityMark(size: 22)
                }
                .workoutLiveActivityActionAccessibility(context: context)
            }
            .widgetURL(WorkoutLiveActivityLink.url(for: context.attributes.workoutID))
            .keylineTint(WorkoutLiveActivityStyle.cobalt)
        }
    }
}

private struct WorkoutLiveActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        ZStack {
            Rectangle()
                .fill(WorkoutLiveActivityStyle.blueBlack)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            WorkoutLiveActivityStyle.cobalt.opacity(
                                isLuminanceReduced ? 0.12 : 0.24
                            ),
                            WorkoutLiveActivityStyle.cobalt.opacity(0.04),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 250, height: 42)
                .rotationEffect(.degrees(-8))
                .blur(radius: 9)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    WorkoutLiveActivityMark(size: 30)
                    Text(context.state.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(WorkoutLiveActivityStyle.warmSilver)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            timerInterval: context.attributes.startedAt...Date.distantFuture,
                            countsDown: false,
                            showsHours: true
                        )
                            .font(.system(.title, design: .rounded).monospacedDigit().weight(.bold))
                            .foregroundStyle(WorkoutLiveActivityStyle.warmSilver)
                            .minimumScaleFactor(1)

                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("ELAPSED TIME")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(WorkoutLiveActivityStyle.warmSilver.opacity(0.62))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if context.state.totalSetCount == 0 {
                        Text("No sets yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WorkoutLiveActivityStyle.warmSilver.opacity(0.8))
                            .frame(width: 92)
                            .frame(minHeight: 64)
                    } else {
                        WorkoutLiveActivityProgressDial(
                            completed: context.state.completedSetCount,
                            total: context.state.totalSetCount,
                            diameter: 68,
                            showsCaption: !dynamicTypeSize.isAccessibilitySize
                        )
                        .frame(width: 92)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)

            ContainerRelativeShape()
                .strokeBorder(BarosBrand.cobalt, lineWidth: 2)
                .shadow(
                    color: BarosBrand.cobalt.opacity(
                        isLuminanceReduced ? 0 : 0.42
                    ),
                    radius: 10
                )
                .accessibilityHidden(true)
        }
        .workoutLiveActivityActionAccessibility(context: context)
    }
}

private struct WorkoutLiveActivityMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Image("BarosPlates")
                .resizable()
                .scaledToFit()
            Image("BarosMark")
                .resizable()
                .scaledToFit()
        }
        .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct WorkoutLiveActivityProgressDial: View {
    let completed: Int
    let total: Int
    let diameter: CGFloat
    var showsCaption = false

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(WorkoutLiveActivityStyle.warmSilver.opacity(0.18), lineWidth: 4)
                .accessibilityHidden(true)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    WorkoutLiveActivityStyle.cobalt,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Text("\(completed)/\(total)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(WorkoutLiveActivityStyle.warmSilver)
                if showsCaption {
                    Text("SETS")
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(WorkoutLiveActivityStyle.warmSilver.opacity(0.62))
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private enum WorkoutLiveActivityAccessibility {
    static func value(context: ActivityViewContext<WorkoutLiveActivityAttributes>) -> Text {
        Text("\(context.state.title), elapsed time \(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false, showsHours: true), \(context.state.completedSetCount) of \(context.state.totalSetCount) sets complete")
    }
}

private extension View {
    func workoutLiveActivityActionAccessibility(
        context: ActivityViewContext<WorkoutLiveActivityAttributes>
    ) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel("Return to Workout")
            .accessibilityValue(WorkoutLiveActivityAccessibility.value(context: context))
            .accessibilityAddTraits(.isButton)
    }
}

private enum WorkoutLiveActivityStyle {
    static let blueBlack = BarosBrand.blueBlack
    static let cobalt = BarosBrand.cobalt
    static let warmSilver = BarosBrand.foreground
}
