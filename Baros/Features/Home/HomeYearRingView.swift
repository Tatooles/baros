import SwiftUI

/// A finite animation. Only the fixed-size Canvas interpolates each frame.
struct HomeYearRingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("HomeRingHasAppeared") private var hasAppeared = false
    @State private var progress: Double = 1
    @State private var drawsTrack = false
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 58
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 13

    let model: HomeRingModel
    let period: HomeRingPeriod
    let diameter: CGFloat
    let now: Date
    let replayID: Int

    private var innerLapCount: Int {
        period == .year ? model.yearSpokes.map(\.lap).max() ?? 0 : 0
    }

    private var centerCaption: String {
        let caption = model.sinceDescription(now: now, calendar: .current, abbreviated: true)
        return innerLapCount > 0 ? caption.replacingOccurrences(of: " since ", with: "\nsince ") : caption
    }

    var body: some View {
        ZStack {
            HomeRingCanvas(spokes: model.spokes(for: period), emptySlots: model.emptySlotIndices(for: period),
                           period: period, progress: progress, drawsTrack: drawsTrack)
            VStack(spacing: 5) {
                if model.totalWorkouts > 0 {
                    Text(model.totalWorkouts.formatted())
                        .font(.system(size: min(numberSize, innerLapCount > 0 ? (innerLapCount == 3 ? 48 : 54) : 76), weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .tracking(-2)
                        .foregroundStyle(AppTheme.textPrimary)
                        .monospacedDigit()
                    Text(centerCaption)
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
            .frame(width: diameter * (innerLapCount > 0 ? 0.40 : 0.56))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilitySummary(period: period, now: now, calendar: .current))
        .accessibilityIdentifier("HomeYearRing")
        .task(id: SweepTrigger(replayID: replayID, reduceMotion: reduceMotion)) { await sweep() }
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
        }
        guard !reduceMotion else {
            hasAppeared = true
            return
        }
        // Let SwiftUI commit the reset before interpolating the Canvas. No hit testing is gated.
        try? await Task.sleep(for: .milliseconds(25))
        guard !Task.isCancelled else { return }
        hasAppeared = true
        let duration = drawsTrack ? (firstEmptyAppearance ? 1.55 : 0.65) : 0.95
        withAnimation(drawsTrack ? .linear(duration: duration) : .easeOut(duration: duration)) {
            progress = 1
        }
    }
}

private struct HomeRingCanvas: View, Animatable {
    @Environment(\.colorScheme) private var colorScheme
    let spokes: [HomeRingSpoke]
    let emptySlots: [Int]
    let period: HomeRingPeriod
    var progress: Double
    let drawsTrack: Bool

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
            var track = Path()
            track.addArc(center: center, radius: radius,
                         startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * trackProgress), clockwise: false)
            context.stroke(track, with: .color(Color(.separator).opacity(0.65)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))

            for index in emptySlots {
                let growth = revealedGrowth(at: index)
                guard growth > 0 else { continue }
                let angle = (-Double.pi / 2) - Double(index) / Double(period.slotCount) * 2 * .pi
                let startRadius = radius + 6
                let endRadius = startRadius + 7.5 * growth
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + startRadius * cos(angle), y: center.y + startRadius * sin(angle)))
                tick.addLine(to: CGPoint(x: center.x + endRadius * cos(angle), y: center.y + endRadius * sin(angle)))
                let restColor = colorScheme == .dark ? Color.white.opacity(0.40) : Color.black.opacity(0.35)
                context.stroke(tick, with: .color(restColor),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            for spoke in spokes {
                let easedGrowth = revealedGrowth(at: spoke.angleIndex)
                guard easedGrowth > 0 else { continue }
                let angle = (-Double.pi / 2) - Double(spoke.angleIndex) / Double(period.slotCount) * 2 * .pi
                let inner = spoke.lap > 0
                let startRadius = inner ? radius - 7 - CGFloat(spoke.lap - 1) * side * 0.049 : radius + 6
                let length = inner ? (3 + CGFloat(spoke.normalizedLength) * side * 0.034)
                    : (period == .month ? CGFloat(spoke.monthLengthFraction) * side
                       : 8 + CGFloat(spoke.normalizedLength) * side * 0.112)
                let endRadius = startRadius + (inner ? -1 : 1) * length * easedGrowth
                var line = Path()
                line.move(to: CGPoint(x: center.x + startRadius * cos(angle), y: center.y + startRadius * sin(angle)))
                line.addLine(to: CGPoint(x: center.x + endRadius * cos(angle), y: center.y + endRadius * sin(angle)))
                let color = inner ? Color(.secondaryLabel).opacity(0.45) : Color.accentColor.opacity(0.5 + spoke.normalizedLength * 0.5)
                context.stroke(line, with: .color(color), style: StrokeStyle(
                    lineWidth: inner ? 1.8 : (period == .month ? 5.5 : 3.25), lineCap: .round))
            }

            let dotOpacity = drawsTrack ? min(1, max(0, (progress - 0.78) / 0.12)) : 1
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

    private func revealedGrowth(at index: Int) -> Double {
        let arrival = Double(period.slotCount - 1 - index) / Double(period.slotCount - 1) * 0.82
        let growth = min(1, max(0, (progress - arrival) / 0.13))
        return growth * growth * (3 - 2 * growth)
    }
}
