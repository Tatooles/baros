import BarosCore
import SwiftUI
import UIKit

/// The time being chosen for one set while its wheels are the keyboard.
struct SetTimeEntry: Equatable {
    let setID: UUID
    /// What the wheels read; zero is no time.
    var seconds: Int

    init(setID: UUID, startingSeconds: Int) {
        self.setID = setID
        seconds = Self.clamped(startingSeconds)
    }

    static func clamped(_ seconds: Int) -> Int {
        min(max(0, seconds), WorkoutNumericInputPolicy.durationSecondsRange.upperBound)
    }
}

/// What a time cell asks of the screen that owns the set being timed.
enum SetTimeEdit {
    /// Open the wheels on this time.
    case open(Int)
    /// The wheels settled on this time; zero is no time.
    case change(Int)
    /// The wheels are closing.
    case close
}

extension View {
    /// Makes a time cell an input whose keyboard is minutes and seconds
    /// wheels. While `isEditing`, the cell holds the keyboard as a text field
    /// would, so the system docks, draws and animates the wheels.
    func setTimeInput(
        isEditing: Bool,
        startingSeconds: Int,
        onChange: @escaping (Int) -> Void,
        onEnd: @escaping () -> Void
    ) -> some View {
        background {
            SetTimeInput(isEditing: isEditing, startingSeconds: startingSeconds, onChange: onChange, onEnd: onEnd)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background {
            if isEditing {
                GeometryReader { proxy in
                    Color.clear.preference(key: SetTimeCellBottomKey.self, value: proxy.frame(in: .global).maxY)
                }
            }
        }
    }

    /// On a scroll view: when the wheels open on a cell they would cover,
    /// scrolls just far enough to bring the cell above them, as the system
    /// does for a text field and its keyboard. `editing` names the cell.
    func revealsSetTimeCell(editing: AnyHashable?) -> some View {
        modifier(SetTimeCellReveal(editing: editing))
    }
}

private struct SetTimeInput: UIViewRepresentable {
    let isEditing: Bool
    let startingSeconds: Int
    let onChange: (Int) -> Void
    let onEnd: () -> Void

    func makeUIView(context: Context) -> SetTimeResponder {
        SetTimeResponder()
    }

    func updateUIView(_ view: SetTimeResponder, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
        view.startingSeconds = startingSeconds
        view.wantsKeyboard = isEditing
        guard isEditing != view.isFirstResponder else { return }
        // Taking or giving up the keyboard changes focus elsewhere, which
        // must not happen in the middle of a view update.
        DispatchQueue.main.async {
            guard view.wantsKeyboard != view.isFirstResponder else { return }
            if view.wantsKeyboard {
                view.takeKeyboard()
            } else {
                _ = view.resignFirstResponder()
            }
        }
    }
}

/// Holds the keyboard for a time cell. It draws nothing; the cell does.
private final class SetTimeResponder: UIView {
    var startingSeconds = 0
    var wantsKeyboard = false
    var onChange: ((Int) -> Void)?
    var onEnd: (() -> Void)?
    private var wheels: SetTimeWheelsInputView?

    /// The time cell whose wheels are up, if any.
    private static weak var holder: SetTimeResponder?

    /// Only the owning screen brings up the wheels; UIKit restoring a first
    /// responder after a sheet would show them with no set to write to.
    override var canBecomeFirstResponder: Bool { window != nil && wantsKeyboard }

    /// Brings up the wheels. A text field's keyboard is dismissed first:
    /// swapped in place for the shorter wheels, it would leave the screen
    /// laid out for the keyboard's height.
    func takeKeyboard() {
        guard Self.holder?.isFirstResponder != true else {
            if !becomeFirstResponder() { onEnd?() }
            return
        }
        window?.endEditing(true)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsKeyboard, !self.isFirstResponder else { return }
            if !self.becomeFirstResponder() { self.onEnd?() }
        }
    }

    override var inputView: UIView? { wheels }

    override func becomeFirstResponder() -> Bool {
        wheels = SetTimeWheelsInputView(
            startingSeconds: startingSeconds,
            bottomInset: window?.safeAreaInsets.bottom ?? 0
        ) { [weak self] seconds in
            self?.onChange?(seconds)
        }
        let became = super.becomeFirstResponder()
        if became { Self.holder = self } else { wheels = nil }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            wheels = nil
            // Another field may be taking the keyboard inside a view update.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isFirstResponder else { return }
                self.onEnd?()
            }
        }
        return resigned
    }
}

/// Minutes and seconds wheels in the system keyboard's own container, with
/// seconds in steps of five.
private final class SetTimeWheelsInputView: UIInputView, UIPickerViewDataSource, UIPickerViewDelegate,
    UIPickerViewAccessibilityDelegate {
    private static let wheelsHeight: CGFloat = 216
    private static let columnWidth: CGFloat = 130

    private let picker = UIPickerView()
    private let minuteChoices = Array(0..<60)
    /// Every fifth second, plus the starting second when it falls between
    /// steps, so opening the wheels never changes a time already recorded.
    private let secondChoices: [Int]
    private let onChange: (Int) -> Void

    init(startingSeconds: Int, bottomInset: CGFloat, onChange: @escaping (Int) -> Void) {
        let start = SetTimeEntry.clamped(startingSeconds)
        secondChoices = Set(stride(from: 0, to: 60, by: 5)).union([start % 60]).sorted()
        self.onChange = onChange
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: Self.wheelsHeight + bottomInset),
            inputViewStyle: .keyboard
        )
        autoresizingMask = .flexibleWidth

        picker.dataSource = self
        picker.delegate = self
        picker.accessibilityIdentifier = "SetTimeWheels"
        picker.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: topAnchor),
            picker.heightAnchor.constraint(equalToConstant: Self.wheelsHeight),
            picker.centerXAnchor.constraint(equalTo: centerXAnchor),
            picker.widthAnchor.constraint(equalToConstant: Self.columnWidth * 2 + 10),
        ])
        addUnitLabel("min", column: 0)
        addUnitLabel("sec", column: 1)

        picker.selectRow(start / 60, inComponent: 0, animated: false)
        picker.selectRow(secondChoices.firstIndex(of: start % 60) ?? 0, inComponent: 1, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The unit sits beside the selected row, right of its digits.
    private func addUnitLabel(_ text: String, column: Int) {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.isAccessibilityElement = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let columnCenter = (CGFloat(column) - 0.5) * (Self.columnWidth + 5)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: picker.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: picker.centerXAnchor, constant: columnCenter + 20),
        ])
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? minuteChoices.count : secondChoices.count
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        Self.columnWidth
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        "\(component == 0 ? minuteChoices[row] : secondChoices[row])"
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        let minutes = minuteChoices[pickerView.selectedRow(inComponent: 0)]
        let seconds = secondChoices[pickerView.selectedRow(inComponent: 1)]
        onChange(minutes * 60 + seconds)
    }

    func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
        component == 0 ? "Minutes" : "Seconds"
    }
}

/// The bottom edge, on screen, of the time cell the wheels are open on.
private struct SetTimeCellBottomKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
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
        /// Where the list ends on screen: the top of the keyboard and its bar.
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
                // The keyboard arrives after the cell is chosen, and the list
                // may still be settling from a keyboard that just left.
                guard editing != nil else { return }
                reveal()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    reveal()
                }
            }
            .onPreferenceChange(SetTimeCellBottomKey.self) { [geometry] bottom in
                geometry.cellBottom = bottom.map { $0 + geometry.offset }
            }
            .onChange(of: editing) { _, editing in
                guard editing != nil else { return }
                Task { @MainActor in
                    // Let the cell report where it is first.
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
