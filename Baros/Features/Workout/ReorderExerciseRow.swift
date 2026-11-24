import BarosCore
import SwiftUI

/// An exercise's name, details and progress, as drawn on its card in the edit list.
struct ReorderExerciseRow: View {
    static let cornerRadius: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize = 13
    let exercise: any ReorderListExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if dynamicTypeSize.isAccessibilitySize {
                if let metadata = exercise.metadata { detail(metadata) }
                trailing
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let metadata = exercise.metadata { detail(metadata).lineLimit(1) }
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
    }

    /// Darker than the system secondary label in light mode, for 4.5:1 on the card.
    static let detailColor = BarosAdaptiveColor.dynamic(light: 0x66666C, dark: 0x9A9AA1)

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: detailSize, weight: .medium))
            .foregroundStyle(Self.detailColor)
    }

    @ViewBuilder
    private var trailing: some View {
        if let text = exercise.trailingDetail {
            detail(exercise.isNew ? "New · \(text)" : text)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// The handle that drags an exercise, or a whole superset from its label. It sits
/// inside what it moves, at 3:1 or better against the card.
struct ReorderGrip: View {
    static let color = BarosAdaptiveColor.dynamic(light: 0x76767C, dark: 0x8E8E95)
    var height: CGFloat = 48
    var color: Color = Self.color

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 48, height: height)
            .contentShape(Rectangle())
    }
}

/// A single exercise's card surface.
struct ReorderCardSurface: View {
    var isNew = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
        shape
            .fill(isNew ? AppTheme.brandAccentMuted : AppTheme.groupedSurface)
            .overlay(shape.stroke(isNew ? AppTheme.brandAccentForeground : AppTheme.subtleBorder))
    }
}

/// The one card a superset's members share in the edit list. The accent border and
/// faint wash set it apart from single cards in both appearances.
struct SupersetContainerSurface: View {
    private static let border = BarosAdaptiveColor.dynamic(
        light: 0x1C66C7, lightAlpha: 0.58, dark: 0x4D94FF, darkAlpha: 0.7
    )
    private static let wash = BarosAdaptiveColor.dynamic(
        light: 0x1C66C7, lightAlpha: 0.05, dark: 0x4D94FF, darkAlpha: 0.07
    )
    static let borderWidth: CGFloat = 1.5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
        shape
            .fill(AppTheme.groupedSurface)
            .overlay(shape.fill(Self.wash))
            .overlay(shape.strokeBorder(Self.border, lineWidth: Self.borderWidth))
    }
}

/// The label at the top of a superset container.
struct SupersetContainerHeader: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
            Text("SUPERSET")
                .tracking(0.8)
            Text("· \(count)")
                .fontWeight(.regular)
                .foregroundStyle(ReorderExerciseRow.detailColor)
                .monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AppTheme.brandAccentForeground)
        .lineLimit(1)
        // Stops growing at accessibility2, like the bottom bar, so the label stays inside the
        // container's outline; it shrinks before it truncates beside the block grip.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
    }
}

/// The hairline between two members of a superset container.
struct SupersetMemberDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 1 / displayScale)
            .padding(.horizontal, 16)
            .accessibilityHidden(true)
    }
}

/// A short message about the last edit, such as what a removal took with it.
struct ReorderNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    var detail: String?
    /// Said after the title to VoiceOver, such as what saving will now delete.
    var spoken: String?
}

/// Shows a notice above the bottom bar for a few seconds. Undo lives in the bar and
/// lasts until Save, so the notice only says what happened and can go on its own.
struct ReorderNoticeToast: View {
    @Binding var notice: ReorderNotice?

    var body: some View {
        ZStack {
            if let current = notice {
                VStack(alignment: .leading, spacing: 1) {
                    Text(current.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if let detail = current.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(ReorderExerciseRow.detailColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ReorderNotice")
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: current.id) {
                    AccessibilityNotification.Announcement(
                        [current.title, current.detail, current.spoken].compactMap { $0 }.joined(separator: ". ")
                    ).post()
                    try? await Task.sleep(for: .seconds(4))
                    if notice?.id == current.id { notice = nil }
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: notice?.id)
    }
}
