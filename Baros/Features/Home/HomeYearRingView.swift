import BarosCore
import SwiftUI

struct HomeYearRingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @AppStorage("HomeRingHasAppeared") private var hasAppeared = false
    @State private var progress: Double = 1
    @State private var drawsTrack = false
    @State private var scrubReady = false
    @State private var selectedIndex: Int?
    @State private var highlightIndex: Int?
    @State private var emphasis: Double = 0
    @State private var touch: ScrubTouch?
    @State private var clearSelection: Task<Void, Never>?
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 58
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 13

    let model: HomeRingModel
    let period: HomeRingPeriod
    let diameter: CGFloat
    let replayID: Int
    let exerciseCount: (UUID) -> Int?
    let open: ([UUID]) -> Bool
    let holdsSelection: Bool

    private var innerLapCount: Int {
        period == .year ? model.yearSpokes.map(\.lap).max() ?? 0 : 0
    }

    private var preview: HomeRingSlotPreview? {
        selectedIndex.map { HomeRingSlotPreview(model: model, period: period, index: $0, calendar: calendar,
                                                exerciseCount: exerciseCount) }
    }

    private var scrubs: Bool { scrubReady && model.totalWorkouts > 0 }

    var body: some View {
        ZStack {
            HomeRingCanvas(spokes: model.spokes(for: period), emptySlots: model.emptySlotIndices(for: period),
                           period: period, progress: progress, drawsTrack: drawsTrack,
                           highlightIndex: highlightIndex, emphasis: emphasis)
            if let preview {
                previewText(preview)
                    .frame(width: diameter * (innerLapCount > 0 ? 0.46 : 0.58))
                    .transition(centerTransition)
            } else {
                summaryText
                    .frame(width: diameter * (innerLapCount > 0 ? 0.40 : 0.56))
                    .transition(centerTransition)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(scrubGesture, isEnabled: scrubs)
        .sensoryFeedback(trigger: selectedIndex) { _, index in
            guard let index else { return nil }
            return model.workouts(for: period, at: index).isEmpty ? .selection : .impact(weight: .light)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilitySummary(period: period))
        .accessibilityValue(preview?.accessibilityValue ?? "")
        .accessibilityHint(model.totalWorkouts > 0
                           ? "Swipe up or down to move through \(period == .month ? "days" : "weeks")." : "")
        .accessibilityAdjustableAction(adjust)
        .accessibilityAction { openSelection() }
        .accessibilityIdentifier("HomeYearRing")
        .task(id: SweepTrigger(replayID: replayID, reduceMotion: reduceMotion)) { await sweep() }
        .onChange(of: period) { _, _ in clear(animated: false) }
        .onChange(of: holdsSelection) { _, holds in
            if !holds { clear(animated: true) }
        }
    }

    private var centerTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(BlurReplaceTransition(configuration: .downUp))
    }

    @ViewBuilder private var summaryText: some View {
        VStack(spacing: 5) {
            if model.totalWorkouts > 0 {
                Text(model.workoutCount(for: period).formatted())
                    .font(.system(size: min(numberSize, innerLapCount > 0 ? (innerLapCount == 3 ? 48 : 54) : 76), weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .tracking(-2)
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.workoutCount(for: period))))
                    .animation(reduceMotion ? nil : .snappy, value: period)
                Text(model.countCaption(for: period).replacingOccurrences(of: " in the ", with: "\nin the "))
                    .font(.system(size: min(captionSize, innerLapCount > 0 ? 15 : 19), weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Each \(period == .month ? "day" : "week") you train\nadds a line here.")
                    .font(.system(size: min(captionSize + 2, 21), weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }

    private func previewText(_ preview: HomeRingSlotPreview) -> some View {
        VStack(spacing: 4) {
            Text(preview.dateText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            if let title = preview.title {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            if !preview.rows.isEmpty {
                VStack(spacing: 3) {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 6, verticalSpacing: 3) {
                        ForEach(Array(preview.rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                if let label = row.label {
                                    Text(label)
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                                Text(row.title)
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .frame(maxWidth: row.label == nil ? .infinity : nil,
                                           alignment: row.label == nil ? .center : .leading)
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    if preview.hiddenCount > 0 {
                        Text("+\(preview.hiddenCount) more")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.top, 2)
            }
            if let detail = preview.detail {
                Text(detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(preview.title == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .monospacedDigit()
            }
        }
        .multilineTextAlignment(.center)
    }

    private struct ScrubTouch {
        let startedInCenter: Bool
        var moved = false
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                if touch == nil {
                    clearSelection?.cancel()
                    let tapRadius = HomeRingCanvas.trackRadius(side: diameter, period: period) - 4
                    touch = ScrubTouch(startedInCenter: distance(value.startLocation, center) < tapRadius)
                }
                if hypot(value.translation.width, value.translation.height) > 8 { touch?.moved = true }
                guard touch?.startedInCenter == false || touch?.moved == true,
                      distance(value.location, center) > 12 else { return }
                select(HomeRingScrubGeometry.slotIndex(at: value.location, center: center,
                                                       slotCount: period.slotCount))
            }
            .onEnded { _ in
                let ended = touch
                touch = nil
                guard let ended else { return }
                if ended.moved || selectedIndex.map({ model.workouts(for: period, at: $0).isEmpty }) ?? true {
                    scheduleClear(after: 2.5)
                } else {
                    openSelection()
                }
            }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func scheduleClear(after seconds: Double) {
        clearSelection?.cancel()
        clearSelection = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            clear(animated: true)
        }
    }

    private func select(_ index: Int) {
        selectedIndex = index
        highlightIndex = index
        emphasis = 1
    }

    private func clear(animated: Bool) {
        let animation: Animation? = animated ? (reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.45)) : nil
        withAnimation(animation) {
            selectedIndex = nil
            emphasis = 0
        }
    }

    private func openSelection() {
        guard let preview, !preview.workoutIDs.isEmpty else { return }
        clearSelection?.cancel()
        if !open(preview.workoutIDs) { scheduleClear(after: 0.6) }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        clearSelection?.cancel()
        guard model.totalWorkouts > 0 else { return }
        guard let index = selectedIndex else {
            select(0)
            return
        }
        switch direction {
        case .increment: select(max(0, index - 1))
        case .decrement: select(min(period.slotCount - 1, index + 1))
        @unknown default: break
        }
    }

    private struct SweepTrigger: Equatable {
        let replayID: Int
        let reduceMotion: Bool
    }

    @MainActor private func sweep() async {
        let firstEmptyAppearance = model.totalWorkouts == 0 && !hasAppeared
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) {
            drawsTrack = model.totalWorkouts == 0
            progress = reduceMotion ? 1 : 0
            selectedIndex = nil
            highlightIndex = nil
            emphasis = 0
            scrubReady = reduceMotion
        }
        guard !reduceMotion else {
            hasAppeared = true
            return
        }
        try? await Task.sleep(for: .milliseconds(25))
        guard !Task.isCancelled else { return }
        hasAppeared = true
        let duration = drawsTrack ? (firstEmptyAppearance ? 1.55 : 0.65) : 0.95
        withAnimation(drawsTrack ? .linear(duration: duration) : .easeOut(duration: duration)) {
            progress = 1
        }
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled else { return }
        scrubReady = true
    }
}

private struct HomeRingCanvas: View, Animatable {
    @Environment(\.colorScheme) private var colorScheme
    let spokes: [HomeRingSpoke]
    let emptySlots: [Int]
    let period: HomeRingPeriod
    var progress: Double
    let drawsTrack: Bool
    let highlightIndex: Int?
    var emphasis: Double

    static func trackRadius(side: CGFloat, period: HomeRingPeriod) -> CGFloat {
        side * (period == .month ? 0.308 : 0.345)
    }

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, emphasis) }
        set { (progress, emphasis) = (newValue.first, newValue.second) }
    }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = Self.trackRadius(side: side, period: period)
            let trackProgress = drawsTrack ? min(1, progress / 0.78) : 1
            let dim = 1 - 0.68 * emphasis
            var track = Path()
            track.addArc(center: center, radius: radius,
                         startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * trackProgress), clockwise: false)
            context.stroke(track, with: .color(Color(.separator).opacity(0.65)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))

            for index in emptySlots {
                let growth = revealedGrowth(at: index)
                guard growth > 0 else { continue }
                let lift = index == highlightIndex ? emphasis : 0
                let angle = slotAngle(index)
                let startRadius = radius + 6
                let endRadius = startRadius + (7.5 + 2.5 * lift) * growth
                var tick = Path()
                tick.move(to: point(center, startRadius, angle))
                tick.addLine(to: point(center, endRadius, angle))
                let restColor = (colorScheme == .dark ? Color.white.opacity(0.40) : Color.black.opacity(0.35))
                    .opacity(lift > 0 ? 1 - lift : dim)
                context.stroke(tick, with: .color(restColor), style: StrokeStyle(lineWidth: 1.5 + lift, lineCap: .round))
                if lift > 0 {
                    context.stroke(tick, with: .color(AppTheme.textPrimary.opacity(lift)),
                                   style: StrokeStyle(lineWidth: 1.5 + lift, lineCap: .round))
                }
            }

            for spoke in spokes {
                let easedGrowth = revealedGrowth(at: spoke.angleIndex)
                guard easedGrowth > 0 else { continue }
                let angle = slotAngle(spoke.angleIndex)
                let inner = spoke.lap > 0
                let lift = !inner && spoke.angleIndex == highlightIndex ? emphasis : 0
                let startRadius = inner ? radius - 7 - CGFloat(spoke.lap - 1) * side * 0.049 : radius + 6
                let length = inner ? (3 + CGFloat(spoke.normalizedLength) * side * 0.034)
                    : (period == .month ? CGFloat(spoke.monthLengthFraction) * side
                       : 8 + CGFloat(spoke.normalizedLength) * side * 0.112)
                let endRadius = startRadius + (inner ? -1 : 1) * length * easedGrowth
                var line = Path()
                line.move(to: point(center, startRadius, angle))
                line.addLine(to: point(center, endRadius, angle))
                let resting = 0.5 + spoke.normalizedLength * 0.5
                let color = inner ? Color(.secondaryLabel).opacity(0.45 * dim)
                    : Color.accentColor.opacity(lift > 0 ? resting + (1 - resting) * lift : resting * dim)
                let width: CGFloat = inner ? 1.8 : (period == .month ? 5.5 : 3.25)
                context.stroke(line, with: .color(color), style: StrokeStyle(
                    lineWidth: width + 1.5 * lift, lineCap: .round))
            }

            let dotOpacity = (drawsTrack ? min(1, max(0, (progress - 0.78) / 0.12)) : 1) * (1 - 0.6 * emphasis)
            let pulsePhase = min(1, max(0, (progress - 0.84) / 0.16))
            let pulse = sin(pulsePhase * .pi)
            let dot = CGPoint(x: center.x, y: center.y - radius)
            let glowRadius = 11 + pulse * 8
            context.fill(Path(ellipseIn: CGRect(x: dot.x - glowRadius, y: dot.y - glowRadius,
                                                width: glowRadius * 2, height: glowRadius * 2)),
                         with: .radialGradient(Gradient(colors: [AppTheme.textPrimary.opacity((0.17 + pulse * 0.15) * dotOpacity), .clear]),
                                               center: dot, startRadius: 0, endRadius: glowRadius))
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)),
                         with: .color(AppTheme.textPrimary.opacity(dotOpacity)))
        }
        .allowsHitTesting(false)
    }

    private func slotAngle(_ index: Int) -> Double {
        (-Double.pi / 2) - Double(index) / Double(period.slotCount) * 2 * .pi
    }

    private func point(_ center: CGPoint, _ radius: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private func revealedGrowth(at index: Int) -> Double {
        let arrival = Double(period.slotCount - 1 - index) / Double(period.slotCount - 1) * 0.82
        let growth = min(1, max(0, (progress - arrival) / 0.13))
        return growth * growth * (3 - 2 * growth)
    }
}
