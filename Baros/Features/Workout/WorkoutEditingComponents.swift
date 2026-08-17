import SwiftUI

extension View {
    func workoutInputTapTarget<Focus: Hashable>(
        _ focusedField: FocusState<Focus?>.Binding,
        equals focusTarget: Focus
    ) -> some View {
        contentShape(
            RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
        )
        .onTapGesture {
            guard focusedField.wrappedValue != focusTarget else { return }
            focusedField.wrappedValue = focusTarget
        }
    }
}

struct WorkoutProgressiveNoteAddButton<Focus: Hashable>: View {
    let title: String
    let accessibilityIdentifier: String
    let focusTarget: Focus
    @Binding var isRevealed: Bool
    var focusedField: FocusState<Focus?>.Binding

    var body: some View {
        Button {
            isRevealed = true
            Task { @MainActor in
                await Task.yield()
                focusedField.wrappedValue = focusTarget
            }
        } label: {
            Label(title, systemImage: "note.text.badge.plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.brandAccentForeground)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct WorkoutProgressiveNoteDraftField<Focus: Hashable>: View {
    let notes: String
    let placeholder: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let focusTarget: Focus
    @Binding var isRevealed: Bool
    var focusedField: FocusState<Focus?>.Binding
    let commit: (String) -> Void
    @State private var draft: String?

    var body: some View {
        TextField(
            placeholder,
            text: Binding(
                get: { draft ?? notes },
                set: { draft = $0 }
            ),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.body)
        .foregroundStyle(AppTheme.textPrimary)
        .lineLimit(1...6)
        .focused(focusedField, equals: focusTarget)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(minHeight: 44, alignment: .topLeading)
        .workoutInputTapTarget(focusedField, equals: focusTarget)
        .background(
            isFocused ? AnyShapeStyle(AppTheme.brandAccentMuted) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityIdentifier(accessibilityIdentifier)
        .id(focusTarget)
        .onChange(of: focusedField.wrappedValue) { previousField, newField in
            if previousField == focusTarget, newField != focusTarget {
                commitAndUpdateDisclosure()
            }
        }
        .onDisappear {
            commitAndUpdateDisclosure()
        }
    }

    private func commitIfNeeded() {
        guard let draft else { return }
        commit(draft)
        self.draft = nil
    }

    private func commitAndUpdateDisclosure() {
        let shouldHide = currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        commitIfNeeded()
        if shouldHide {
            isRevealed = false
        }
    }

    private var currentText: String {
        draft ?? notes
    }

    private var isFocused: Bool {
        focusedField.wrappedValue == focusTarget
    }
}

struct WorkoutExerciseProgress {
    var completed: Int
    var total: Int

    var isComplete: Bool {
        completed == total && total > 0
    }
}

struct WorkoutExerciseHeaderContent: View {
    let title: String
    let metadata: String?
    let progress: WorkoutExerciseProgress
    var isCollapsed: Bool?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let isCollapsed {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(isCollapsed == true ? 1 : nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let metadata {
                    Text(metadata)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(progress.completed)/\(progress.total)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(progress.isComplete ? AppTheme.brandAccentForeground : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    progress.isComplete ? AnyShapeStyle(AppTheme.brandAccentMuted) : AnyShapeStyle(AppTheme.recessedSurface),
                    in: Capsule()
                )
        }
    }
}

struct WorkoutSetColumnHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(AppTheme.textTertiary)
            .frame(maxWidth: .infinity)
    }
}

struct WorkoutTitleField<Focus: Hashable>: View {
    let placeholder: String
    @Binding var text: String
    let focusTarget: Focus
    var focusedField: FocusState<Focus?>.Binding
    let accessibilityIdentifier: String

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.title.weight(.bold))
            .foregroundStyle(AppTheme.textPrimary)
            .lineLimit(1)
            .focused(focusedField, equals: focusTarget)
            .submitLabel(.done)
            .accessibilityHint("Double-tap to edit the workout name")
            .accessibilityIdentifier(accessibilityIdentifier)
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .workoutInputTapTarget(focusedField, equals: focusTarget)
            .background(
                isFocused ? AnyShapeStyle(AppTheme.fieldSurface) : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? AppTheme.brandFocus : .clear, lineWidth: 1.5)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .id(focusTarget)
    }

    private var isFocused: Bool {
        focusedField.wrappedValue == focusTarget
    }
}

struct LabeledWorkoutTitleField<Focus: Hashable>: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let focusTarget: Focus
    var focusedField: FocusState<Focus?>.Binding
    let accessibilityIdentifier: String
    let labelIdentifier: String
    let editAffordanceIdentifier: String
    var titleFont: Font = .title.weight(.bold)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier(labelIdentifier)

            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .font(titleFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .focused(focusedField, equals: focusTarget)
                    .submitLabel(.done)
                    .accessibilityHint("Double-tap to edit the workout name")
                    .accessibilityIdentifier(accessibilityIdentifier)

                Button {
                    focusedField.wrappedValue = focusTarget
                } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isFocused ? AppTheme.brandAccentForeground : AppTheme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier(editAffordanceIdentifier)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Edit workout name")
                .accessibilityIdentifier(editAffordanceIdentifier)
            }
            .padding(.leading, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .workoutInputTapTarget(focusedField, equals: focusTarget)
            .background(
                AppTheme.fieldSurface,
                in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? AppTheme.brandFocus : .clear, lineWidth: 1.5)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .id(focusTarget)
        }
    }

    private var isFocused: Bool {
        focusedField.wrappedValue == focusTarget
    }
}

enum WorkoutNumericFieldPresentation {
    case well
    case grid
}

struct WorkoutNumericTextField<Focus: Hashable>: View {
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let focusTarget: Focus
    var focusedField: FocusState<Focus?>.Binding
    let accessibilityIdentifier: String
    var verticalPadding: CGFloat = 12
    var presentation: WorkoutNumericFieldPresentation = .well

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(AppTheme.textPrimary)
            .focused(focusedField, equals: focusTarget)
            .padding(.horizontal, presentation == .grid ? 4 : 0)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, minHeight: 44)
            .workoutInputTapTarget(focusedField, equals: focusTarget)
            .background {
                switch presentation {
                case .well:
                    RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                        .fill(AppTheme.fieldSurface)
                case .grid:
                    Rectangle()
                        .fill(isFocused ? AppTheme.brandAccentMuted : .clear)
                }
            }
            .overlay(alignment: .bottom) {
                if presentation == .grid, isFocused {
                    Rectangle()
                        .fill(AppTheme.brandFocus)
                        .frame(height: 2)
                }
            }
            .overlay {
                if presentation == .well {
                    RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                        .strokeBorder(isFocused ? AppTheme.brandFocus : .clear, lineWidth: 1.5)
                }
            }
            .animation(.easeOut(duration: 0.15), value: focusedField.wrappedValue == focusTarget)
            .accessibilityIdentifier(accessibilityIdentifier)
            .id(focusTarget)
    }

    private var isFocused: Bool {
        focusedField.wrappedValue == focusTarget
    }
}

struct WorkoutNotesField<Focus: Hashable>: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let focusTarget: Focus
    var focusedField: FocusState<Focus?>.Binding
    let accessibilityIdentifier: String

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(AppTheme.textSecondary)
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(4...6)
                    .focused(focusedField, equals: focusTarget)
                    .padding(12)
                    .workoutInputTapTarget(focusedField, equals: focusTarget)
                    .background(
                        AppTheme.fieldSurface,
                        in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                            .strokeBorder(
                                focusedField.wrappedValue == focusTarget ? AppTheme.brandFocus : .clear,
                                lineWidth: 1.5
                            )
                    )
                    .animation(.easeOut(duration: 0.15), value: focusedField.wrappedValue == focusTarget)
                    .accessibilityIdentifier(accessibilityIdentifier)
                    .id(focusTarget)
            }
        }
    }
}

struct WorkoutAddRowButton: View {
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.brandAccentForeground)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
