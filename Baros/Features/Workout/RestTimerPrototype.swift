// PROTOTYPE — throwaway. Answers one question for #114: where should the
// rest countdown live on Active Workout? Lives only on the
// `prototype/issue-114-rest-timer` branch; never merge.
//
// Three placements, switchable with the orange pill under the header:
//   A — Inline row:      a countdown row is inserted under the completed set.
//   B — Divider line:    the divider under the completed set becomes the
//                        countdown; nothing moves.
//   C — Bottom capsule:  a floating capsule at the bottom, hidden while the
//                        keyboard is up.
// A and B fall back to the header's elapsed pill when the inline countdown is
// scrolled off-screen or its exercise is collapsed.
//
// State is in memory only. Completing a set (checkmark or RPE) starts rest;
// un-completing that set cancels it. "10s" shortens rest to see the ending.

import SwiftUI
import UIKit

@Observable
@MainActor
final class RestTimerPrototype {
    static let shared = RestTimerPrototype()

    enum Variant: String, CaseIterable {
        case insertedRow = "A"
        case dividerLine = "B"
        case dividerCompact = "B2"
        case dividerGutter = "B3"
        case bottomCapsule = "C"

        var name: String {
            switch self {
            case .insertedRow: "Inline row"
            case .dividerLine: "Divider line"
            case .dividerCompact: "Divider, compact"
            case .dividerGutter: "Divider, gutter"
            case .bottomCapsule: "Bottom capsule"
            }
        }

        var usesInlineCountdown: Bool { self != .bottomCapsule }
        var drawsOnDivider: Bool { self == .dividerLine || self == .dividerCompact || self == .dividerGutter }
        var expandsControlsOnTap: Bool { self == .dividerCompact || self == .dividerGutter }
    }

    private static let variantKey = "RestTimerPrototype.variant"

    var variant: Variant {
        didSet { UserDefaults.standard.set(variant.rawValue, forKey: Self.variantKey) }
    }
    var usesShortRest = false

    /// B3 only: how the tappable time is drawn, to test discoverability.
    enum ChipStyle: String, CaseIterable {
        case plain = "Plain"
        case badge = "Badge"
        case badgeAdjust = "Badge ±"

        /// Width reserved in the gutter so the bar starts after the chip.
        var gutterWidth: CGFloat {
            switch self {
            case .plain: 36
            case .badge: 44
            case .badgeAdjust: 58
            }
        }
    }

    var chipStyle: ChipStyle = .badge

    func cycleChipStyle() {
        let all = ChipStyle.allCases
        let index = all.firstIndex(of: chipStyle) ?? 0
        withAnimation(.snappy) { chipStyle = all[(index + 1) % all.count] }
    }
    private(set) var restingSetID: UUID?
    private(set) var startedAt: Date = .now
    private(set) var endsAt: Date = .now
    private(set) var isFinished = false
    /// Whether the inline countdown (A/B) is on screen. Drives the header fallback.
    var isInlineVisible = false
    /// B2/B3: the transient control pill opened by tapping the time.
    private(set) var areControlsExpanded = false
    private var endTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    /// Screenshot hook: --rest-proto-autostart starts rest after the given set
    /// at launch; --rest-proto-expanded also opens the control pill.
    func autostartIfRequested(after setID: UUID) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--rest-proto-autostart"), !isResting else { return }
        start(after: setID)
        if arguments.contains("--rest-proto-expanded") {
            areControlsExpanded = true
        }
    }

    func toggleControls() {
        withAnimation(.snappy(duration: 0.25)) { areControlsExpanded.toggle() }
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        guard areControlsExpanded else { return }
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ProcessInfo.processInfo.arguments.contains("--rest-proto-sticky-controls") ? 600 : 6))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.snappy(duration: 0.25)) { self.areControlsExpanded = false }
        }
    }

    private init() {
        variant = UserDefaults.standard.string(forKey: Self.variantKey)
            .flatMap(Variant.init(rawValue:)) ?? .dividerGutter
        // Screenshot hooks: --rest-proto-chip <Plain|Badge|Badge ±>
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--rest-proto-chip"), index + 1 < arguments.count,
           let style = ChipStyle(rawValue: arguments[index + 1]) {
            chipStyle = style
        }
    }

    var isResting: Bool { restingSetID != nil }

    var showsHeaderFallback: Bool {
        isResting && variant.usesInlineCountdown && !isInlineVisible
    }

    var interval: ClosedRange<Date> { startedAt...max(startedAt, endsAt) }

    func remainingFraction(at date: Date) -> CGFloat {
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 0 }
        return CGFloat(min(1, max(0, endsAt.timeIntervalSince(date) / total)))
    }

    func cycle(by step: Int) {
        let all = Variant.allCases
        let index = all.firstIndex(of: variant) ?? 0
        withAnimation(.snappy) {
            variant = all[(index + step + all.count) % all.count]
        }
    }

    func start(after setID: UUID) {
        let now = Date.now
        withAnimation(.snappy) {
            restingSetID = setID
            startedAt = now
            endsAt = now.addingTimeInterval(usesShortRest ? 10 : 90)
            isFinished = false
            areControlsExpanded = false
        }
        scheduleEnd()
    }

    func adjust(by seconds: TimeInterval) {
        guard isResting, !isFinished else { return }
        endsAt = max(Date.now.addingTimeInterval(1), endsAt.addingTimeInterval(seconds))
        scheduleEnd()
        scheduleCollapse()
    }

    func skip() {
        endTask?.cancel()
        withAnimation(.snappy) {
            restingSetID = nil
            isFinished = false
            areControlsExpanded = false
        }
    }

    func cancel(ifTriggeredBy setID: UUID) {
        guard restingSetID == setID else { return }
        skip()
    }

    private func scheduleEnd() {
        endTask?.cancel()
        let setID = restingSetID
        let delay = endsAt.timeIntervalSinceNow
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, delay)))
            guard !Task.isCancelled, let self, self.restingSetID == setID else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.snappy) { self.isFinished = true }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self.restingSetID == setID else { return }
            self.skip()
        }
    }
}

// MARK: - Shared pieces

/// Once-per-second countdown. `Text(timerInterval:)` redraws on a display
/// link every frame; a 1s timeline lets the UI go idle between ticks.
private struct RestRemainingText: View {
    let timer: RestTimerPrototype

    var body: some View {
        TimelineView(.periodic(from: timer.startedAt, by: 1)) { context in
            let remaining = Int(max(0, timer.endsAt.timeIntervalSince(context.date)).rounded(.up))
            Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
        }
    }
}

private struct RestCountdownText: View {
    let timer: RestTimerPrototype
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        Group {
            if timer.isFinished {
                Text("Rest over")
            } else {
                RestRemainingText(timer: timer)
            }
        }
        .font(font.monospacedDigit())
        .foregroundStyle(AppTheme.brandAccentForeground)
    }
}

/// Draining bar. `ProgressView(timerInterval:)` re-ran layout for the whole
/// Active Workout page every frame (~30% CPU, swallowed taps), so the fill is
/// a render-only horizontal scale driven by a coarse timeline instead.
private struct RestProgressBar: View {
    let timer: RestTimerPrototype
    var height: CGFloat = 4

    var body: some View {
        TimelineView(.periodic(from: timer.startedAt, by: 1)) { context in
            let fraction = timer.isFinished ? 1 : timer.remainingFraction(at: context.date)
            Capsule()
                .fill(AppTheme.subtleBorder)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.brandAccentFill)
                        .scaleEffect(x: fraction, y: 1, anchor: .leading)
                }
        }
        .frame(height: height)
    }
}

private struct RestAdjustButtons: View {
    let timer: RestTimerPrototype

    var body: some View {
        HStack(spacing: 4) {
            if !timer.isFinished {
                button("−15") { timer.adjust(by: -15) }
                button("+15") { timer.adjust(by: 15) }
            }
            Button {
                timer.skip()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.textSecondary)
            .accessibilityLabel("Skip rest")
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(minWidth: 36, minHeight: 32)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.brandAccentForeground)
    }
}

/// A/B only: report whether the inline countdown is on screen.
private struct InlineVisibilityReporter: ViewModifier {
    let timer: RestTimerPrototype

    func body(content: Content) -> some View {
        content
            .onScrollVisibilityChange(threshold: 0.6) { isVisible in
                timer.isInlineVisible = isVisible
            }
            .onDisappear { timer.isInlineVisible = false }
    }
}

// MARK: - A: inserted row

struct RestInlineRowPrototype: View {
    let timer = RestTimerPrototype.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: timer.isFinished ? "checkmark" : "hourglass")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.brandAccentForeground)
                .frame(width: 28)
            RestCountdownText(timer: timer)
                .frame(minWidth: 72, alignment: .leading)
            RestProgressBar(timer: timer)
            RestAdjustButtons(timer: timer)
        }
        .padding(.leading, 4)
        .frame(minHeight: 44)
        .background(AppTheme.brandAccentMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .padding(.vertical, 4)
        .modifier(InlineVisibilityReporter(timer: timer))
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }
}

// MARK: - B: divider line

struct RestDividerLinePrototype: View {
    let timer = RestTimerPrototype.shared

    var body: some View {
        RestProgressBar(timer: timer, height: 3)
            .overlay(alignment: .leading) {
                Menu {
                    if !timer.isFinished {
                        Button("Add 15 seconds", systemImage: "plus") { timer.adjust(by: 15) }
                        Button("Subtract 15 seconds", systemImage: "minus") { timer.adjust(by: -15) }
                    }
                    Button("Skip Rest", systemImage: "forward.end") { timer.skip() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: timer.isFinished ? "checkmark" : "hourglass")
                        RestCountdownText(timer: timer, font: .caption.weight(.bold))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(AppTheme.canvasBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(AppTheme.brandAccentFill, lineWidth: 1))
                }
                .padding(.leading, 38)
            }
            .zIndex(1)
            .modifier(InlineVisibilityReporter(timer: timer))
    }
}

// MARK: - B2 / B3: divider with a compact time chip and tap-to-expand controls

/// Short time label that fits the 28pt set-number column plus its spacing.
private struct RestCompactTime: View {
    let timer: RestTimerPrototype

    var body: some View {
        Group {
            if timer.isFinished {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.heavy))
            } else {
                RestRemainingText(timer: timer)
                    .font(.caption2.weight(.bold).monospacedDigit())
            }
        }
        .lineLimit(1)
    }
}

/// The transient control pill: −15 · time · +15 · Skip.
private struct RestExpandedControls: View {
    let timer: RestTimerPrototype

    var body: some View {
        HStack(spacing: 2) {
            if !timer.isFinished {
                pillButton("−15") { timer.adjust(by: -15) }
            }
            Button { timer.toggleControls() } label: {
                RestCountdownText(timer: timer, font: .subheadline.weight(.bold))
                    .padding(.horizontal, 6)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.plain)
            if !timer.isFinished {
                pillButton("+15") { timer.adjust(by: 15) }
            }
            Button("Skip") { timer.skip() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minWidth: 44, minHeight: 36)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .background(AppTheme.groupedSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.brandAccentFill.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold).monospacedDigit())
                .frame(minWidth: 40, minHeight: 36)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.brandAccentForeground)
    }
}

/// Where the resting divider sits, so the card can float tappable controls
/// over it. Controls drawn inside a 1pt divider overflow its bounds and miss
/// touches, so they live in an overlay on the whole set list instead.
struct RestDividerAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// B2: zero layout shift. Only the bar is drawn here; the chip comes from
/// `RestDividerControlsOverlay`.
struct RestDividerCompactPrototype: View {
    let timer = RestTimerPrototype.shared

    var body: some View {
        RestProgressBar(timer: timer, height: 3)
            .padding(.leading, 40)
            .frame(height: 1)
            .anchorPreference(key: RestDividerAnchorKey.self, value: .bounds) { $0 }
            .modifier(InlineVisibilityReporter(timer: timer))
    }
}

/// B3: the divider opens an 18pt gutter so the time never overlaps a row.
struct RestDividerGutterPrototype: View {
    let timer = RestTimerPrototype.shared

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: timer.chipStyle.gutterWidth) // the time button comes from the overlay
            RestProgressBar(timer: timer, height: 3)
        }
        .frame(height: 18)
        .anchorPreference(key: RestDividerAnchorKey.self, value: .bounds) { $0 }
        .modifier(InlineVisibilityReporter(timer: timer))
        .transition(.opacity)
    }
}

/// B2/B3 tappable layer: the time chip, or the expanded control pill, centered
/// vertically on the resting divider at its leading edge.
struct RestDividerControlsOverlay: View {
    let anchor: Anchor<CGRect>?
    let timer = RestTimerPrototype.shared

    var body: some View {
        GeometryReader { proxy in
            if let anchor, timer.isResting, timer.variant.expandsControlsOnTap {
                let rect = proxy[anchor]
                ZStack(alignment: .topLeading) {
                    Color.clear
                    Group {
                        if timer.areControlsExpanded {
                            RestExpandedControls(timer: timer)
                        } else {
                            chip
                        }
                    }
                    .fixedSize()
                    .alignmentGuide(.leading) { _ in -(rect.minX + 2) }
                    .alignmentGuide(.top) { d in d[VerticalAlignment.center] - rect.midY }
                }
            }
        }
    }

    private var chip: some View {
        Button { timer.toggleControls() } label: {
            Group {
                if timer.variant == .dividerGutter {
                    gutterChip
                } else {
                    RestCompactTime(timer: timer)
                        .foregroundStyle(timer.isFinished ? AppTheme.onBrandAccent : AppTheme.brandAccentForeground)
                        .frame(width: 36, height: 18)
                        .background(
                            timer.isFinished ? AnyShapeStyle(AppTheme.brandAccentFill) : AnyShapeStyle(AppTheme.canvasBackground),
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(AppTheme.brandAccentFill, lineWidth: 1))
                }
            }
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rest timer")
        .accessibilityHint("Shows controls to adjust or skip rest.")
    }

    /// B3's time, in the style picked on the switcher. The badge styles reuse
    /// the RPE badge's look (muted cobalt capsule), which already means "tap
    /// to edit" on this screen.
    @ViewBuilder
    private var gutterChip: some View {
        switch timer.chipStyle {
        case .plain:
            RestCompactTime(timer: timer)
                .foregroundStyle(AppTheme.brandAccentForeground)
                .frame(width: 36, height: 18)
        case .badge, .badgeAdjust:
            HStack(spacing: 3) {
                RestCompactTime(timer: timer)
                if timer.chipStyle == .badgeAdjust, !timer.isFinished {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundStyle(AppTheme.brandAccentForeground)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(AppTheme.brandAccentMuted, in: Capsule())
        }
    }
}

// MARK: - C: bottom capsule

struct RestBottomCapsulePrototype: View {
    let timer = RestTimerPrototype.shared

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("REST")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                RestCountdownText(timer: timer, font: .title3.weight(.semibold))
            }
            .frame(minWidth: 84, alignment: .leading)
            RestProgressBar(timer: timer)
            RestAdjustButtons(timer: timer)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(minHeight: 56)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, AppTheme.shellPadding)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Header fallback (A/B, inline countdown off-screen)

struct RestHeaderFallbackPrototype: View {
    let timer = RestTimerPrototype.shared

    var body: some View {
        if timer.variant.expandsControlsOnTap {
            if timer.areControlsExpanded {
                RestExpandedControls(timer: timer)
                    .frame(maxWidth: .infinity)
            } else {
                Button { timer.toggleControls() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: timer.isFinished ? "checkmark" : "hourglass")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.brandAccentForeground)
                        RestCountdownText(timer: timer)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(AppTheme.brandAccentMuted).interactive(), in: .capsule)
            }
        } else {
            menuFallback
        }
    }

    private var menuFallback: some View {
        Menu {
            if !timer.isFinished {
                Button("Add 15 seconds", systemImage: "plus") { timer.adjust(by: 15) }
                Button("Subtract 15 seconds", systemImage: "minus") { timer.adjust(by: -15) }
            }
            Button("Skip Rest", systemImage: "forward.end") { timer.skip() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: timer.isFinished ? "checkmark" : "hourglass")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                RestCountdownText(timer: timer)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(AppTheme.brandAccentMuted).interactive(), in: .capsule)
    }
}

// MARK: - Switcher (not part of any design)

struct RestTimerPrototypeSwitcher: View {
    @Bindable var timer = RestTimerPrototype.shared

    var body: some View {
        HStack(spacing: 2) {
            Button { timer.cycle(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 30, height: 30)
            }
            Text("\(timer.variant.rawValue) · \(timer.variant.name)")
                .frame(minWidth: 128)
            Button { timer.cycle(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 30, height: 30)
            }
            Divider().frame(height: 16).overlay(.black.opacity(0.3))
            Button(timer.usesShortRest ? "10s" : "90s") { timer.usesShortRest.toggle() }
                .frame(minWidth: 36, minHeight: 30)
            if timer.variant == .dividerGutter {
                Divider().frame(height: 16).overlay(.black.opacity(0.3))
                Button(timer.chipStyle.rawValue) { timer.cycleChipStyle() }
                    .frame(minWidth: 56, minHeight: 30)
            }
        }
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(.black)
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .background(.orange, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityIdentifier("RestTimerPrototypeSwitcher")
    }
}
