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
}

/// Hours, minutes, and seconds wheels for one set's time, like the Clock
/// app's timer. Nothing is saved until Done; all zeros clears the time.
struct SetTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: SetTimePickerRequest
    let onSave: (Int?) -> Void
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int

    init(request: SetTimePickerRequest, onSave: @escaping (Int?) -> Void) {
        self.request = request
        self.onSave = onSave
        let start = max(0, request.startingSeconds)
        _hours = State(initialValue: min(23, start / 3_600))
        _minutes = State(initialValue: start % 3_600 / 60)
        _seconds = State(initialValue: start % 60)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    wheel($hours, in: 0..<24, unit: "hours", identifier: "SetTimeHoursWheel")
                    wheel($minutes, in: 0..<60, unit: "min", identifier: "SetTimeMinutesWheel")
                    wheel($seconds, in: 0..<60, unit: "sec", identifier: "SetTimeSecondsWheel")
                }
                .accessibilityElement(children: .contain)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        let total = hours * 3_600 + minutes * 60 + seconds
                        onSave(total > 0 ? total : nil)
                        dismiss()
                    }
                    .accessibilityIdentifier("DoneSetTimeButton")
                }
            }
        }
        .presentationDetents([.height(request.hasTime ? 340 : 296)])
        .presentationDragIndicator(.visible)
    }

    private func wheel(
        _ selection: Binding<Int>,
        in range: Range<Int>,
        unit: String,
        identifier: String
    ) -> some View {
        HStack(spacing: 2) {
            Picker(unit, selection: selection) {
                ForEach(range, id: \.self) { value in
                    Text("\(value)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            // Neighbouring wheels otherwise take each other's touches.
            .clipped()
            .contentShape(Rectangle())
            .accessibilityLabel(unit)
            .accessibilityIdentifier(identifier)

            Text(unit)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}
