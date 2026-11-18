import BarosCore
import SwiftUI

/// Which set's time is being chosen. The sheet is keyed on it, so each
/// presentation starts from that set's own time.
struct SetTimePickerRequest: Identifiable {
    let id = UUID()
    /// Names the set, such as "Dead Hang, Set 2".
    let title: String
    /// Where the wheels start: the set's time, or the value it would be filled with.
    let startingSeconds: Int
    /// Whether the set has a time to clear.
    let hasTime: Bool
    /// Set to offer RPE under the wheels. A time cell opens no keyboard, so
    /// the keyboard bar's RPE chips cannot serve a timed set.
    var rpe: RPE?

    struct RPE {
        let selected: Double?
    }
}

/// Minutes and seconds wheels for one set's time, with seconds in steps of
/// five. Nothing is saved until Done or an RPE is chosen.
struct SetTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let request: SetTimePickerRequest
    /// The chosen time; nil clears it.
    let onSave: (Int?) -> Void
    /// The wheels' time with the tapped RPE, or nil RPE to clear it. As with
    /// the keyboard's chips, choosing an RPE finishes the set.
    var onSelectRPE: ((Int?, Double?) -> Void)?
    @State private var minutes: Int
    @State private var seconds: Int
    /// Every fifth second, plus the starting second when it falls between
    /// steps, so opening the picker never changes a time already recorded.
    private let secondChoices: [Int]

    init(
        request: SetTimePickerRequest,
        onSave: @escaping (Int?) -> Void,
        onSelectRPE: ((Int?, Double?) -> Void)? = nil
    ) {
        self.request = request
        self.onSave = onSave
        self.onSelectRPE = onSelectRPE
        let start = min(max(0, request.startingSeconds), 59 * 60 + 59)
        _minutes = State(initialValue: start / 60)
        _seconds = State(initialValue: start % 60)
        secondChoices = Set(stride(from: 0, to: 60, by: 5)).union([start % 60]).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        wheel($minutes, in: Array(0..<60), unit: "min", spokenUnit: "Minutes", identifier: "SetTimeMinutesWheel")
                        wheel($seconds, in: secondChoices, unit: "sec", spokenUnit: "Seconds", identifier: "SetTimeSecondsWheel")
                    }
                    .accessibilityElement(children: .contain)

                    if let rpe = request.rpe, let onSelectRPE {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("RPE")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.textSecondary)
                                .accessibilityAddTraits(.isHeader)
                            RPEChipRow(selected: rpe.selected) { value in
                                // An RPE completes the set, and zero is not a time to
                                // complete it with. Clearing one needs no time.
                                guard value == nil || chosenSeconds != nil else { return }
                                onSelectRPE(chosenSeconds, value)
                                dismiss()
                            }
                            // Nine chips share one row; past this size they truncate.
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .disabled(chosenSeconds == nil && rpe.selected == nil)
                            .opacity(chosenSeconds == nil && rpe.selected == nil ? 0.4 : 1)
                        }
                    }

                    if request.hasTime {
                        Button("Clear Time", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("ClearSetTimeButton")
                    }
                }
                .padding(.horizontal, AppTheme.shellPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("CancelSetTimeButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(chosenSeconds)
                        dismiss()
                    }
                    // Zero is not a time. Removing one is Clear Time's job.
                    .disabled(chosenSeconds == nil)
                    .accessibilityIdentifier("DoneSetTimeButton")
                }
            }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }

    private var chosenSeconds: Int? {
        let total = minutes * 60 + seconds
        return total > 0 ? total : nil
    }

    /// Standard sizes fit a short sheet that leaves the workout in view.
    /// Accessibility sizes stack the unit names over taller rows and scroll.
    private var detents: Set<PresentationDetent> {
        if dynamicTypeSize.isAccessibilitySize { return [.large] }
        var height: CGFloat = 296
        if request.hasTime { height += 44 }
        if request.rpe != nil { height += 72 }
        return [.height(height)]
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
