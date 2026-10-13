import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(context: context)
                .widgetURL(WorkoutLiveActivityLink.url(for: context.attributes.workoutID))
                .activityBackgroundTint(BarosBrand.brandBlueBlack)
                .activitySystemActionForegroundColor(BarosBrand.brandForeground)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        WorkoutLiveActivityMark(size: 24)

                        Text(context.state.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BarosBrand.brandForeground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)

                        HStack(spacing: 4) {
                            if context.isResting {
                                Image(systemName: "hourglass")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BarosBrand.brandCobalt)
                            }
                            WorkoutLiveActivityTimer(context: context)
                        }
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(BarosBrand.brandForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 66, alignment: .trailing)

                        WorkoutLiveActivityProgressDial(
                            completed: context.state.completedSetCount,
                            total: context.state.totalSetCount,
                            diameter: 40
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 2)
                    .workoutLiveActivityActionAccessibility(context: context)
                }
            } compactLeading: {
                WorkoutLiveActivityRestMark(context: context)
                    .accessibilityHidden(true)
            } compactTrailing: {
                WorkoutLiveActivityTimer(context: context)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(BarosBrand.brandForeground)
                    .frame(maxWidth: 52)
                    .workoutLiveActivityActionAccessibility(context: context)
            } minimal: {
                ZStack {
                    WorkoutLiveActivityRestMark(context: context)
                }
                .workoutLiveActivityActionAccessibility(context: context)
            }
            .widgetURL(WorkoutLiveActivityLink.url(for: context.attributes.workoutID))
            .keylineTint(BarosBrand.brandCobalt)
        }
    }
}

private struct WorkoutLiveActivityLockScreenView: View {
    private struct LayoutMetrics {
        let metricSpacing: CGFloat
        let trailingMetricWidth: CGFloat
        let elapsedTimerMinimumScaleFactor: CGFloat
        let showsSecondaryCaptions: Bool
    }

    let context: ActivityViewContext<WorkoutLiveActivityAttributes>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @ScaledMetric(relativeTo: .caption2) private var elapsedCaptionFontSize: CGFloat = 9

    private var layoutMetrics: LayoutMetrics {
        if dynamicTypeSize.isAccessibilitySize {
            LayoutMetrics(
                metricSpacing: 12,
                trailingMetricWidth: 76,
                elapsedTimerMinimumScaleFactor: 0.7,
                showsSecondaryCaptions: false
            )
        } else {
            LayoutMetrics(
                metricSpacing: 18,
                trailingMetricWidth: 92,
                elapsedTimerMinimumScaleFactor: 1,
                showsSecondaryCaptions: true
            )
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(BarosBrand.brandBlueBlack)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            BarosBrand.brandCobalt.opacity(
                                isLuminanceReduced ? 0.12 : 0.24
                            ),
                            BarosBrand.brandCobalt.opacity(0.04),
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
                        .foregroundStyle(BarosBrand.brandForeground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if context.isResting {
                        Text(
                            timerInterval: context.attributes.startedAt...Date.distantFuture,
                            countsDown: false,
                            showsHours: true
                        )
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(BarosBrand.brandForeground.opacity(0.62))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 64, alignment: .trailing)
                    }
                }

                HStack(alignment: .center, spacing: layoutMetrics.metricSpacing) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            if context.isResting {
                                Image(systemName: "hourglass")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(BarosBrand.brandCobalt)
                            }
                            WorkoutLiveActivityTimer(context: context)
                        }
                        .font(.system(.title, design: .rounded).monospacedDigit().weight(.bold))
                        .foregroundStyle(BarosBrand.brandForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(layoutMetrics.elapsedTimerMinimumScaleFactor)

                        if layoutMetrics.showsSecondaryCaptions {
                            Text(context.isResting ? "REST" : "ELAPSED TIME")
                                .font(.system(size: elapsedCaptionFontSize, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(BarosBrand.brandForeground.opacity(0.62))
                        }
                        Group {
                            if let interval = context.restInterval {
                                ProgressView(timerInterval: interval, countsDown: true) {
                                    EmptyView()
                                } currentValueLabel: {
                                    EmptyView()
                                }
                                .progressViewStyle(.linear)
                                .tint(BarosBrand.brandCobalt)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(height: 3)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    if context.state.totalSetCount == 0 {
                        Text("No sets yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BarosBrand.brandForeground.opacity(0.8))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .frame(width: layoutMetrics.trailingMetricWidth)
                            .frame(minHeight: 64)
                    } else {
                        WorkoutLiveActivityProgressDial(
                            completed: context.state.completedSetCount,
                            total: context.state.totalSetCount,
                            diameter: 68,
                            showsCaption: layoutMetrics.showsSecondaryCaptions
                        )
                        .frame(width: layoutMetrics.trailingMetricWidth)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)

            ContainerRelativeShape()
                .strokeBorder(BarosBrand.brandCobalt, lineWidth: 2)
                .shadow(
                    color: BarosBrand.brandCobalt.opacity(
                        isLuminanceReduced ? 0 : 0.42
                    ),
                    radius: 10
                )
                .accessibilityHidden(true)
        }
        .workoutLiveActivityActionAccessibility(context: context)
    }
}

private extension ActivityViewContext where Attributes == WorkoutLiveActivityAttributes {
    var isResting: Bool { state.restEndsAt != nil && !isStale }

    var restInterval: ClosedRange<Date>? {
        guard isResting, let start = state.restStartedAt, let end = state.restEndsAt else { return nil }
        return min(start, end)...end
    }
}

private struct WorkoutLiveActivityTimer: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>

    var body: some View {
        if context.isResting, let end = context.state.restEndsAt {
            Text(
                timerInterval: (context.state.restStartedAt ?? context.attributes.startedAt)...end,
                countsDown: true,
                showsHours: false
            )
        } else {
            Text(
                timerInterval: context.attributes.startedAt...Date.distantFuture,
                countsDown: false,
                showsHours: true
            )
        }
    }
}

private struct WorkoutLiveActivityRestMark: View {
    let context: ActivityViewContext<WorkoutLiveActivityAttributes>

    var body: some View {
        if let interval = context.restInterval {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(BarosBrand.brandCobalt)
            .frame(width: 22, height: 22)
            .overlay {
                Image(systemName: "hourglass")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BarosBrand.brandForeground)
            }
        } else {
            WorkoutLiveActivityMark(size: 22)
        }
    }
}

private struct WorkoutLiveActivityMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Image("BarosMark")
                .resizable()
                .scaledToFit()
            Image("BarosPlates")
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
    @ScaledMetric(relativeTo: .caption2) private var captionFontSize: CGFloat = 7

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    private var valueFont: Font {
        diameter <= 44
            ? .caption2.monospacedDigit().weight(.bold)
            : .caption.monospacedDigit().weight(.bold)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(BarosBrand.brandForeground.opacity(0.18), lineWidth: 4)
                .accessibilityHidden(true)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    BarosBrand.brandCobalt,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Text("\(completed)/\(total)")
                    .font(valueFont)
                    .foregroundStyle(BarosBrand.brandForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 5)
                if showsCaption {
                    Text("SETS")
                        .font(.system(size: captionFontSize, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(BarosBrand.brandForeground.opacity(0.62))
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private enum WorkoutLiveActivityAccessibility {
    static func value(context: ActivityViewContext<WorkoutLiveActivityAttributes>) -> Text {
        if context.isResting, let end = context.state.restEndsAt {
            return Text("\(context.state.title), rest time remaining \(timerInterval: (context.state.restStartedAt ?? context.attributes.startedAt)...end, countsDown: true, showsHours: false), \(context.state.completedSetCount) of \(context.state.totalSetCount) sets complete")
        }
        return Text("\(context.state.title), elapsed time \(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false, showsHours: true), \(context.state.completedSetCount) of \(context.state.totalSetCount) sets complete")
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
