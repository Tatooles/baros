import SwiftUI

struct RestGutterAnchorKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Always occupies the existing divider position. Its observation is confined
/// to one slot; opening a gutter doesn't rebuild the surrounding card or rows.
struct RestSetDivider: View {
    let slot: RestTimerSlot
    let timer: RestTimerCoordinator
    @ScaledMetric(relativeTo: .caption2) private var gutterHeight = 18
    @ScaledMetric(relativeTo: .caption2) private var badgeWidth = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let period = slot.period {
                RestGutter(period: period, timer: timer, height: max(18, gutterHeight), badgeWidth: badgeWidth)
                    .id(period.rest.id)
                    .transition(.opacity)
            } else {
                Divider().overlay(AppTheme.subtleBorder)
            }
        }
        .animation(restTimerReducesMotion(reduceMotion) ? nil : .snappy(duration: 0.25), value: slot.period?.rest.id)
    }
}

private struct RestGutter: View {
    let period: RestTimerPeriod
    let timer: RestTimerCoordinator
    let height: CGFloat
    let badgeWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: badgeWidth)
            RestProgressBar(period: period)
        }
        .frame(height: height)
        .opacity(restTimerReducesMotion(reduceMotion) && !hasAppeared ? 0 : 1)
        .onAppear {
            withAnimation(restTimerReducesMotion(reduceMotion) ? .easeOut(duration: 0.15) : nil) { hasAppeared = true }
        }
        .anchorPreference(key: RestGutterAnchorKey.self, value: .bounds) { [period.rest.setID: $0] }
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            timer.reportInlineVisibility(visible, restID: period.rest.id)
        }
        .onDisappear { timer.reportInlineVisibility(false, restID: period.rest.id) }
    }
}

private struct RestProgressBar: View {
    let period: RestTimerPeriod

    var body: some View {
        TimelineView(.periodic(from: period.rest.startedAt, by: 1)) { timeline in
            Capsule()
                .fill(AppTheme.subtleBorder)
                .overlay {
                    Capsule()
                        .fill(AppTheme.brandAccentFill)
                        .scaleEffect(
                            x: period.isFinished ? 0 : period.rest.remainingFraction(at: timeline.date), y: 1,
                            anchor: .leading)
                }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// Floats the 44pt hit target and controls on the whole set list. Putting them
/// inside the short gutter clips hit testing to the divider's bounds.
struct RestGutterOverlay: View {
    let anchors: [UUID: Anchor<CGRect>]
    let slots: [(UUID, RestTimerSlot)]
    let timer: RestTimerCoordinator

    var body: some View {
        GeometryReader { proxy in
            ForEach(slots, id: \.0) { setID, slot in
                if let period = slot.period, let anchor = anchors[setID] {
                    let rect = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        RestInlineControls(period: period, timer: timer)
                            .fixedSize()
                            .alignmentGuide(.leading) { _ in -rect.minX }
                            .alignmentGuide(.top) { dimensions in
                                dimensions[VerticalAlignment.center] - rect.midY
                            }
                    }
                }
            }
        }
    }
}

private struct RestInlineControls: View {
    let period: RestTimerPeriod
    let timer: RestTimerCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            if period.controlsExpanded {
                RestExpandedControls(period: period, timer: timer)
                    .transition(.opacity)
            } else {
                RestTimerBadge(period: period, timer: timer)
                    .transition(.opacity)
            }
        }
        .animation(
            .easeOut(duration: restTimerReducesMotion(reduceMotion) ? 0.15 : 0.25), value: period.controlsExpanded)
    }
}

struct RestTimerBadge: View {
    let period: RestTimerPeriod
    let timer: RestTimerCoordinator
    var showsHourglass = false

    var body: some View {
        TimelineView(.periodic(from: period.rest.startedAt, by: 1)) { timeline in
            Button {
                timer.toggleControls()
            } label: {
                HStack(spacing: 6) {
                    if showsHourglass { Image(systemName: "hourglass") }
                    RestTimeText(period: period, compact: !showsHourglass)
                }
                .foregroundStyle(AppTheme.brandAccentForeground)
                .padding(.horizontal, showsHourglass ? 14 : 6)
                .padding(.vertical, showsHourglass ? 10 : 2)
                .background(AppTheme.brandAccentMuted, in: Capsule())
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(showsHourglass ? "RestTimerHeaderBadge" : "RestTimerBadge")
            .accessibilityLabel("Rest timer")
            .accessibilityHint("Shows controls to adjust or skip rest.")
            .accessibilityValue(restSpokenValue(period, at: timeline.date))
        }
    }
}

private func restSpokenValue(_ period: RestTimerPeriod, at date: Date) -> String {
    period.isFinished
        ? "Rest over"
        : Duration.seconds(period.rest.remainingSeconds(at: date))
            .formatted(.units(allowed: [.minutes, .seconds], width: .wide))
}

private struct RestTimeText: View {
    let period: RestTimerPeriod
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: period.rest.startedAt, by: 1)) { timeline in
            if period.isFinished {
                Image(systemName: "checkmark")
            } else {
                let seconds = period.rest.remainingSeconds(at: timeline.date)
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .monospacedDigit()
            }
        }
        .font(compact ? .caption2.weight(.bold) : .subheadline.weight(.semibold))
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct RestExpandedControls: View {
    let period: RestTimerPeriod
    let timer: RestTimerCoordinator

    var body: some View {
        HStack(spacing: 2) {
            adjustButton("−15", label: "Subtract 15 seconds", seconds: -15)
            TimelineView(.periodic(from: period.rest.startedAt, by: 1)) { timeline in
                Button {
                    timer.toggleControls()
                } label: {
                    RestTimeText(period: period)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Rest timer")
                .accessibilityValue(restSpokenValue(period, at: timeline.date))
                .accessibilityHint("Hides rest controls.")
            }
            adjustButton("+15", label: "Add 15 seconds", seconds: 15)
            Button("Skip") { timer.skip() }
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Skip rest")
                .accessibilityIdentifier("SkipRestButton")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.brandAccentForeground)
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .background(AppTheme.groupedSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.brandAccentFill.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    }

    private func adjustButton(_ title: String, label: String, seconds: TimeInterval) -> some View {
        Button(title) { timer.adjust(by: seconds) }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }
}

/// Owns model observation for rest eligibility, including sync writes while
/// the workout is minimized. None of these reads belongs in card/row bodies.
struct RestTimerLifecycleObserver: View {
    let session: WorkoutSession?
    let timer: RestTimerCoordinator
    let ownerState: CurrentOwnerCoordinator.State

    var body: some View {
        let state = RestTimerLifecycleState(session: session, rest: timer.restForReconciliation, ownerState: ownerState)
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: state, initial: true) { _, _ in
                timer.reconcile(with: session, ownerState: ownerState)
            }
    }
}

struct RestTimerLifecycleState: Equatable {
    let restID: UUID?
    let sessionID: UUID?
    let ownerState: CurrentOwnerCoordinator.State
    let starterIsEligible: Bool

    init(session: WorkoutSession?, rest: WorkoutRest?, ownerState: CurrentOwnerCoordinator.State) {
        restID = rest?.id
        sessionID = session?.id
        self.ownerState = ownerState
        starterIsEligible =
            session?.sortedLoggedExercises.contains { exercise in
                exercise.sortedSets.contains { $0.id == rest?.setID && $0.isCompleted }
            } ?? false
    }
}

/// The system environment value is read-only. This Debug-only launch hook lets
/// UI tests exercise the same motion policy without changing Simulator settings.
func restTimerReducesMotion(_ systemValue: Bool) -> Bool {
    #if DEBUG
        systemValue || ProcessInfo.processInfo.arguments.contains("--uitest-reduce-motion")
    #else
        systemValue
    #endif
}
