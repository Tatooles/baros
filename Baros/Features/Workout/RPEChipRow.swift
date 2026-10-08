import SwiftData
import SwiftUI

// PROTOTYPE — throwaway. Answers one question: how should the RPE quick-pick
// row reach the high values (9–10) without a scroll? Lives only on a
// prototype branch; never merge.
//
// Five rows, switchable with the orange pill under the Active Workout header:
//   A — Fit all:        6–10 in equal-width chips, no Clear chip. Tap the
//                       selected chip again to clear.
//   B — Opens high:     today's scrolling row, opened at the 10 end (or
//                       centered on the set's current RPE).
//   C — 7–10 only:      Clear + 7…10 fit without scrolling; 6/6.5 dropped.
//   D — Descending:     today's scrolling row reversed: 10 first, Clear last.
//   E — Whole + ½:      6…10 plus a ½ toggle that turns them into 6.5…9.5.
//                       Tap the selected chip again to clear.
@Observable
@MainActor
final class RPEChipRowPrototype {
    static let shared = RPEChipRowPrototype()

    enum Variant: String, CaseIterable {
        case fitAll = "A"
        case opensHigh = "B"
        case narrowRange = "C"
        case descending = "D"
        case halfToggle = "E"

        var name: String {
            switch self {
            case .fitAll: "Fit all, tap to clear"
            case .opensHigh: "Scroll opens at 10"
            case .narrowRange: "7–10 only"
            case .descending: "Descending 10→6"
            case .halfToggle: "Whole + ½ toggle"
            }
        }
    }

    private static let variantKey = "RPEChipRowPrototype.variant"

    var variant: Variant {
        didSet { UserDefaults.standard.set(variant.rawValue, forKey: Self.variantKey) }
    }

    private init() {
        variant = UserDefaults.standard.string(forKey: Self.variantKey)
            .flatMap(Variant.init(rawValue:)) ?? .fitAll
    }

    func cycle(by step: Int) {
        let all = Variant.allCases
        let index = all.firstIndex(of: variant) ?? 0
        withAnimation(.snappy) {
            variant = all[(index + step + all.count) % all.count]
        }
    }
}

struct RPEChipRowPrototypeSwitcher: View {
    @Bindable var prototype = RPEChipRowPrototype.shared

    var body: some View {
        HStack(spacing: 2) {
            Button { prototype.cycle(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 30, height: 30)
            }
            Text("\(prototype.variant.rawValue) · \(prototype.variant.name)")
                .frame(minWidth: 160)
            Button { prototype.cycle(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 30, height: 30)
            }
        }
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(.black)
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .background(.orange, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityIdentifier("RPEChipRowPrototypeSwitcher")
    }
}

struct RPEChipRow: View {
    static let values: [Double] = [6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10]
    let selected: Double?
    let onSelect: (Double?) -> Void

    private var prototype: RPEChipRowPrototype { .shared }

    var body: some View {
        switch prototype.variant {
        case .fitAll:
            fittedRow(values: Self.values, showsClear: false)
        case .opensHigh:
            opensHighRow
        case .narrowRange:
            fittedRow(values: Self.values.filter { $0 >= 7 }, showsClear: true)
        case .descending:
            scrollingRow(values: Self.values.reversed(), clearIsLeading: false)
        case .halfToggle:
            HalfToggleRow(selected: selected, onSelect: onSelect)
        }
    }

    // MARK: Fitted (A, C)

    private func fittedRow(values: [Double], showsClear: Bool) -> some View {
        HStack(spacing: 6) {
            if showsClear {
                chip(title: "Clear", value: nil, horizontalPadding: 10)
                    .accessibilityIdentifier("RPEChipClear")
            }
            ForEach(values, id: \.self) { value in
                chip(title: WorkoutFormatters.number(value), value: value, horizontalPadding: 0, fills: true, togglesOff: !showsClear)
                    .accessibilityIdentifier("RPEChip-\(WorkoutFormatters.number(value))")
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Scrolling (B, D)

    private var opensHighRow: some View {
        ScrollViewReader { proxy in
            scrollingContent(values: Self.values, clearIsLeading: true)
                .onAppear {
                    proxy.scrollTo(selected ?? 10, anchor: selected == nil ? .trailing : .center)
                }
        }
    }

    private func scrollingRow(values: [Double], clearIsLeading: Bool) -> some View {
        scrollingContent(values: values, clearIsLeading: clearIsLeading)
    }

    private func scrollingContent(values: [Double], clearIsLeading: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if clearIsLeading { clearChip }

                ForEach(values, id: \.self) { value in
                    chip(title: WorkoutFormatters.number(value), value: value)
                        .id(value)
                        .accessibilityIdentifier("RPEChip-\(WorkoutFormatters.number(value))")
                }

                if !clearIsLeading { clearChip }
            }
            .padding(.horizontal, 2)
        }
    }

    private var clearChip: some View {
        chip(title: "Clear", value: nil)
            .accessibilityIdentifier("RPEChipClear")
    }

    // MARK: Chip

    private func chip(
        title: String,
        value: Double?,
        horizontalPadding: CGFloat = 12,
        fills: Bool = false,
        togglesOff: Bool = false
    ) -> some View {
        let isSelected = selected == value

        return Button {
            onSelect(togglesOff && isSelected ? nil : value)
        } label: {
            RPEChipLabel(title: title, isSelected: isSelected, horizontalPadding: horizontalPadding, fills: fills)
        }
        .buttonStyle(.plain)
    }
}

private struct RPEChipLabel: View {
    let title: String
    let isSelected: Bool
    var horizontalPadding: CGFloat = 12
    var fills = false
    var isDimmed = false

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isSelected ? AppTheme.onBrandAccent : AppTheme.textPrimary)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 6)
            .frame(maxWidth: fills ? .infinity : nil)
            .background(
                isSelected ? AnyShapeStyle(AppTheme.brandAccentFill) : AnyShapeStyle(AppTheme.recessedSurface),
                in: Capsule()
            )
            .opacity(isDimmed ? 0.35 : 1)
            .contentShape(Capsule())
    }
}

// MARK: Half toggle (E)

private struct HalfToggleRow: View {
    let selected: Double?
    let onSelect: (Double?) -> Void

    @State private var isHalfArmed: Bool

    init(selected: Double?, onSelect: @escaping (Double?) -> Void) {
        self.selected = selected
        self.onSelect = onSelect
        _isHalfArmed = State(initialValue: selected.map { $0 != $0.rounded(.down) } ?? false)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach([6, 7, 8, 9, 10] as [Double], id: \.self) { whole in
                let value = isHalfArmed ? whole + 0.5 : whole
                let isUnavailable = value > 10
                let isSelected = selected == value

                Button {
                    onSelect(isSelected ? nil : value)
                } label: {
                    RPEChipLabel(
                        title: WorkoutFormatters.number(isUnavailable ? whole : value),
                        isSelected: isSelected,
                        horizontalPadding: 0,
                        fills: true,
                        isDimmed: isUnavailable
                    )
                }
                .buttonStyle(.plain)
                .disabled(isUnavailable)
                .accessibilityIdentifier("RPEChip-\(WorkoutFormatters.number(value))")
            }

            Button {
                withAnimation(.snappy(duration: 0.15)) { isHalfArmed.toggle() }
            } label: {
                Text("½")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isHalfArmed ? AppTheme.brandAccentFill : AppTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().strokeBorder(
                            isHalfArmed ? AnyShapeStyle(AppTheme.brandAccentFill) : AnyShapeStyle(AppTheme.textSecondary.opacity(0.4)),
                            lineWidth: 1.5
                        )
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("RPEChipHalfToggle")
        }
        .padding(.horizontal, 2)
    }
}

enum RPEChipSelectionAction {
    static func apply(
        value: Double?,
        preparedValues: ActiveWorkoutSetInput.Values? = nil,
        to set: LoggedSet,
        engine: ActiveWorkoutEngine,
        context: ModelContext,
        now: Date = .now
    ) throws {
        try engine.applyActiveSetRPESelection(
            set,
            rpe: value,
            preparedValues: preparedValues ?? .init(weight: set.weight, reps: set.reps),
            context: context,
            now: now
        )
    }
}
