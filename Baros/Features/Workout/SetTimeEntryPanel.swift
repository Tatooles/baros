import BarosCore
import SwiftUI

/// The time being chosen for one set while the wheels are docked.
struct SetTimeEntry: Equatable {
    let setID: UUID
    /// What the wheels read; zero is no time.
    var seconds: Int

    init(setID: UUID, startingSeconds: Int) {
        self.setID = setID
        seconds = SetTimeWheels.clamped(startingSeconds)
    }
}

/// Docks the time wheels at the bottom of the screen the way a keyboard
/// docks, under a bar of the screen's own buttons. Used as a bottom
/// safe-area inset, so the list scrolls clear of it and the set being
/// timed stays in view.
struct SetTimeEntryPanel<Bar: View>: View {
    let startingSeconds: Int
    /// Called when a wheel settles on a new time; zero is no time.
    let onChange: (Int) -> Void
    @ViewBuilder let bar: Bar

    var body: some View {
        VStack(spacing: 0) {
            bar
            SetTimeWheels(startingSeconds: startingSeconds, onChange: onChange)
                .padding(.horizontal, AppTheme.shellPadding)
                .background {
                    AppTheme.keyboardBandFill
                        .shadow(color: AppTheme.keyboardBandShadow, radius: 10, y: -2)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("SetTimeEntryPanel")
    }
}

/// Minutes and seconds wheels, with seconds in steps of five.
struct SetTimeWheels: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onChange: (Int) -> Void
    @State private var minutes: Int
    @State private var seconds: Int
    /// Every fifth second, plus the starting second when it falls between
    /// steps, so opening the wheels never changes a time already recorded.
    private let secondChoices: [Int]

    nonisolated static func clamped(_ seconds: Int) -> Int {
        min(max(0, seconds), WorkoutNumericInputPolicy.durationSecondsRange.upperBound)
    }

    init(startingSeconds: Int, onChange: @escaping (Int) -> Void) {
        self.onChange = onChange
        let start = Self.clamped(startingSeconds)
        _minutes = State(initialValue: start / 60)
        _seconds = State(initialValue: start % 60)
        secondChoices = Set(stride(from: 0, to: 60, by: 5)).union([start % 60]).sorted()
    }

    var body: some View {
        HStack(spacing: 0) {
            wheel($minutes, in: Array(0..<60), unit: "min", spokenUnit: "Minutes", identifier: "SetTimeMinutesWheel")
            wheel($seconds, in: secondChoices, unit: "sec", spokenUnit: "Seconds", identifier: "SetTimeSecondsWheel")
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 216 : 180)
        .accessibilityElement(children: .contain)
        .onChange(of: minutes * 60 + seconds) { _, total in
            onChange(total)
        }
    }

    private func wheel(
        _ selection: Binding<Int>,
        in choices: [Int],
        unit: String,
        spokenUnit: String,
        identifier: String
    ) -> some View {
        let picker = Picker(spokenUnit, selection: selection) {
            ForEach(choices, id: \.self) { value in
                Text("\(value)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        // A wheel's rows keep one height, so larger digits would overlap.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(maxWidth: .infinity)
        // Neighbouring wheels otherwise take each other's touches.
        .clipped()
        .contentShape(Rectangle())
        .accessibilityLabel(spokenUnit)
        .accessibilityIdentifier(identifier)

        let label = Text(unit)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize()
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .accessibilityHidden(true)

        // Beside the wheel the name would squeeze large digits, so it goes above.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            if dynamicTypeSize.isAccessibilitySize {
                label
                picker
            } else {
                picker
                label
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The bottom edge, on screen, of the time cell the wheels are open on.
private struct SetTimeCellBottomKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

extension View {
    /// Marks a time cell so its list can scroll it clear of the docked wheels.
    func setTimeCell(isEditing: Bool) -> some View {
        background {
            if isEditing {
                GeometryReader { proxy in
                    Color.clear.preference(key: SetTimeCellBottomKey.self, value: proxy.frame(in: .global).maxY)
                }
            }
        }
    }

    /// On a scroll view: when the wheels open on a cell they would cover,
    /// scrolls just far enough to bring the cell above them, as the system
    /// does for a text field and the keyboard. `editing` names the cell.
    func revealsSetTimeCell(editing: AnyHashable?) -> some View {
        modifier(SetTimeCellReveal(editing: editing))
    }
}

private struct SetTimeCellReveal: ViewModifier {
    let editing: AnyHashable?
    @State private var position = ScrollPosition()
    @State private var geometry = Geometry()

    /// Kept out of view state: it changes on every scrolled frame and
    /// nothing draws from it.
    private final class Geometry: @unchecked Sendable {
        var offset: CGFloat = 0
        var topInset: CGFloat = 0
        /// Where the list ends on screen: the top of the wheels once they dock.
        var visibleBottom: CGFloat = 0
        /// The bottom edge of the cell within the scrolled content.
        var cellBottom: CGFloat?
    }

    private struct Scroll: Equatable {
        let offset: CGFloat
        let topInset: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: Scroll.self) {
                Scroll(offset: $0.contentOffset.y, topInset: $0.contentInsets.top)
            } action: { _, scroll in
                geometry.offset = scroll.offset
                geometry.topInset = scroll.topInset
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                geometry.visibleBottom = $0
            }
            .onPreferenceChange(SetTimeCellBottomKey.self) { [geometry] bottom in
                geometry.cellBottom = bottom.map { $0 + geometry.offset }
            }
            .onChange(of: editing) { _, editing in
                guard editing != nil else { return }
                Task { @MainActor in
                    // Let the wheels take their room first.
                    try? await Task.sleep(for: .milliseconds(80))
                    reveal()
                }
            }
    }

    private func reveal() {
        guard let cellBottom = geometry.cellBottom else { return }
        let covered = cellBottom - geometry.offset + 12 - geometry.visibleBottom
        guard covered > 0 else { return }
        withAnimation(.smooth(duration: 0.25)) {
            // The offset counts from under the top bars; a scroll target counts from below them.
            position.scrollTo(y: geometry.offset + geometry.topInset + covered)
        }
    }
}
