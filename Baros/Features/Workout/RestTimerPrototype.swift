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
        case bottomCapsule = "C"

        var name: String {
            switch self {
            case .insertedRow: "Inline row"
            case .dividerLine: "Divider line"
            case .bottomCapsule: "Bottom capsule"
            }
        }

        var usesInlineCountdown: Bool { self != .bottomCapsule }
    }

    private static let variantKey = "RestTimerPrototype.variant"

    var variant: Variant {
        didSet { UserDefaults.standard.set(variant.rawValue, forKey: Self.variantKey) }
    }
    var usesShortRest = false
    private(set) var restingSetID: UUID?
    private(set) var startedAt: Date = .now
    private(set) var endsAt: Date = .now
    private(set) var isFinished = false
    /// Whether the inline countdown (A/B) is on screen. Drives the header fallback.
    var isInlineVisible = false
    private var endTask: Task<Void, Never>?

    private init() {
        variant = UserDefaults.standard.string(forKey: Self.variantKey)
            .flatMap(Variant.init(rawValue:)) ?? .insertedRow
    }

    var isResting: Bool { restingSetID != nil }

    var showsHeaderFallback: Bool {
        isResting && variant.usesInlineCountdown && !isInlineVisible
    }

    var interval: ClosedRange<Date> { startedAt...max(startedAt, endsAt) }

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
        }
        scheduleEnd()
    }

    func adjust(by seconds: TimeInterval) {
        guard isResting, !isFinished else { return }
        endsAt = max(Date.now.addingTimeInterval(1), endsAt.addingTimeInterval(seconds))
        scheduleEnd()
    }

    func skip() {
        endTask?.cancel()
        withAnimation(.snappy) {
            restingSetID = nil
            isFinished = false
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

private struct RestCountdownText: View {
    let timer: RestTimerPrototype
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        Group {
            if timer.isFinished {
                Text("Rest over")
            } else {
                Text(timerInterval: timer.interval, countsDown: true)
            }
        }
        .font(font.monospacedDigit())
        .foregroundStyle(AppTheme.brandAccentForeground)
    }
}

private struct RestProgressBar: View {
    let timer: RestTimerPrototype
    var height: CGFloat = 4

    var body: some View {
        Group {
            if timer.isFinished {
                Capsule().fill(AppTheme.brandAccentFill)
            } else {
                ProgressView(timerInterval: timer.interval, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(AppTheme.brandAccentFill)
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
