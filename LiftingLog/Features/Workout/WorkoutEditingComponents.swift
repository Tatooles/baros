import SwiftUI

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
        HStack(spacing: 12) {
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
                    .lineLimit(1)
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
                .foregroundStyle(progress.isComplete ? AppTheme.accentBright : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    progress.isComplete ? AnyShapeStyle(AppTheme.accentMuted) : AnyShapeStyle(AppTheme.surfaceMuted),
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
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous))
            .onTapGesture {
                focusedField.wrappedValue = focusTarget
            }
            .background(
                isFocused ? AnyShapeStyle(AppTheme.fieldFill) : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? AppTheme.accentBright.opacity(0.7) : .clear, lineWidth: 1.5)
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
                        .foregroundStyle(isFocused ? AppTheme.accentBright : AppTheme.textSecondary)
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
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous))
            .onTapGesture {
                focusedField.wrappedValue = focusTarget
            }
            .background(
                AppTheme.fieldFill,
                in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? AppTheme.accentBright.opacity(0.7) : .clear, lineWidth: 1.5)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .id(focusTarget)
        }
    }

    private var isFocused: Bool {
        focusedField.wrappedValue == focusTarget
    }
}

struct WorkoutNumericTextField<Focus: Hashable>: View {
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let focusTarget: Focus
    var focusedField: FocusState<Focus?>.Binding
    let accessibilityIdentifier: String
    var verticalPadding: CGFloat = 12

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.body.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(AppTheme.textPrimary)
            .focused(focusedField, equals: focusTarget)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity)
            .background(
                AppTheme.fieldFill,
                in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                    .strokeBorder(
                        focusedField.wrappedValue == focusTarget ? AppTheme.accentBright.opacity(0.7) : .clear,
                        lineWidth: 1.5
                    )
            )
            .animation(.easeOut(duration: 0.15), value: focusedField.wrappedValue == focusTarget)
            .accessibilityIdentifier(accessibilityIdentifier)
            .id(focusTarget)
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
                    .background(
                        AppTheme.fieldFill,
                        in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                            .strokeBorder(
                                focusedField.wrappedValue == focusTarget ? AppTheme.accentBright.opacity(0.7) : .clear,
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
                .foregroundStyle(AppTheme.accentBright)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
