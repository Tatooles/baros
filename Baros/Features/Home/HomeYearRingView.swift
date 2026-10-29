import SwiftUI

/// A finite animation. Only the fixed-size Canvas interpolates each frame.
struct HomeYearRingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @AppStorage("HomeRingHasAppeared") private var hasAppeared = false
    @State private var progress: Double = 1
    @State private var drawsTrack = false
    @State private var scrubReady = false
    @State private var selectedIndex: Int?
    @State private var touch: ScrubTouch?
    @State private var clearSelection: Task<Void, Never>?
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 58
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 13

    let model: HomeRingModel
    let period: HomeRingPeriod
    let diameter: CGFloat
    let replayID: Int
    /// Loads one workout's logged exercises; called only for the slot being previewed.
    let exerciseCount: (UUID) -> Int?
    let open: ([UUID]) -> Void

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
                           period: period, progress: progress, drawsTrack: drawsTrack, selectedIndex: selectedIndex)
            if let preview {
                // The list's widest rows sit mid-height, where the circle inside the tree rings is widest.
                previewText(preview)
                    .frame(width: diameter * (innerLapCount > 0 ? 0.46 : 0.58))
            } else {
                summaryText
                    .frame(width: diameter * (innerLapCount > 0 ? 0.40 : 0.56))
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
        .onChange(of: period) { _, _ in selectedIndex = nil }
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
                    // One size for every row: long names truncate rather than shrinking unevenly.
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

    // MARK: Scrubbing

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
                    touch = ScrubTouch(startedInCenter: distance(value.startLocation, center) < diameter * 0.22)
                }
                if hypot(value.translation.width, value.translation.height) > 8 { touch?.moved = true }
                // A touch that starts in the center stays a tap until it moves.
                guard touch?.startedInCenter == false || touch?.moved == true,
                      distance(value.location, center) > 12 else { return }
                selectedIndex = HomeRingScrubGeometry.slotIndex(at: value.location, center: center,
                                                                slotCount: period.slotCount)
            }
            .onEnded { _ in
                let ended = touch
                touch = nil
                guard let ended else { return }
                // Dragging only browses; the preview lingers so a tap on it (or a spoke) can open.
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
            selectedIndex = nil
        }
    }

    private func openSelection() {
        guard let preview, !preview.workoutIDs.isEmpty else { return }
        clearSelection?.cancel()
        open(preview.workoutIDs)
        // Clear behind the pushed detail so Home returns to its summary.
        scheduleClear(after: 0.6)
    }

    /// Up moves toward today; down moves back in time. The first swipe lands on today or this week.
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        clearSelection?.cancel()
        guard model.totalWorkouts > 0 else { return }
        guard let index = selectedIndex else {
            selectedIndex = 0
            return
        }
        switch direction {
        case .increment: selectedIndex = max(0, index - 1)
        case .decrement: selectedIndex = min(period.slotCount - 1, index + 1)
        @unknown default: break
        }
    }

    // MARK: Sweep

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
            scrubReady = reduceMotion
        }
        guard !reduceMotion else {
            hasAppeared = true
            return
        }
        // Let SwiftUI commit the reset before interpolating the Canvas. Start is never gated.
        try? await Task.sleep(for: .milliseconds(25))
        guard !Task.isCancelled else { return }
        hasAppeared = true
        let duration = drawsTrack ? (firstEmptyAppearance ? 1.55 : 0.65) : 0.95
        withAnimation(drawsTrack ? .linear(duration: duration) : .easeOut(duration: duration)) {
            progress = 1
        }
        // Scrubbing waits for the sweep so a touch never fights the animation.
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
    let selectedIndex: Int?

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            // Longer Month spokes grow outward; the center and dial's bounds stay clear.
            let radius = side * (period == .month ? 0.308 : 0.345)
            let trackProgress = drawsTrack ? min(1, progress / 0.78) : 1
            // While scrubbing, everything but the selected slot steps back.
            let dim = selectedIndex == nil ? 1 : 0.32
            var track = Path()
            track.addArc(center: center, radius: radius,
                         startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * trackProgress), clockwise: false)
            context.stroke(track, with: .color(Color(.separator).opacity(0.65)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))

            for index in emptySlots {
                let growth = revealedGrowth(at: index)
                guard growth > 0 else { continue }
                let selected = index == selectedIndex
                let angle = slotAngle(index)
                let startRadius = radius + 6
                let endRadius = startRadius + (selected ? 10 : 7.5) * growth
                var tick = Path()
                tick.move(to: point(center, startRadius, angle))
                tick.addLine(to: point(center, endRadius, angle))
                let restColor = selected ? AppTheme.textPrimary
                    : (colorScheme == .dark ? Color.white.opacity(0.40) : Color.black.opacity(0.35)).opacity(dim)
                context.stroke(tick, with: .color(restColor),
                               style: StrokeStyle(lineWidth: selected ? 2.5 : 1.5, lineCap: .round))
            }

            for spoke in spokes {
                let easedGrowth = revealedGrowth(at: spoke.angleIndex)
                guard easedGrowth > 0 else { continue }
                let angle = slotAngle(spoke.angleIndex)
                let inner = spoke.lap > 0
                let selected = !inner && spoke.angleIndex == selectedIndex
                let startRadius = inner ? radius - 7 - CGFloat(spoke.lap - 1) * side * 0.049 : radius + 6
                let length = inner ? (3 + CGFloat(spoke.normalizedLength) * side * 0.034)
                    : (period == .month ? CGFloat(spoke.monthLengthFraction) * side
                       : 8 + CGFloat(spoke.normalizedLength) * side * 0.112)
                let endRadius = startRadius + (inner ? -1 : 1) * length * easedGrowth
                var line = Path()
                line.move(to: point(center, startRadius, angle))
                line.addLine(to: point(center, endRadius, angle))
                let color = inner ? Color(.secondaryLabel).opacity(0.45 * dim)
                    : selected ? Color.accentColor
                    : Color.accentColor.opacity((0.5 + spoke.normalizedLength * 0.5) * dim)
                let width: CGFloat = inner ? 1.8 : (period == .month ? 5.5 : 3.25)
                context.stroke(line, with: .color(color), style: StrokeStyle(
                    lineWidth: selected ? width + 1.5 : width, lineCap: .round))
            }

            let dotOpacity = (drawsTrack ? min(1, max(0, (progress - 0.78) / 0.12)) : 1) * (selectedIndex == nil ? 1 : 0.4)
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
