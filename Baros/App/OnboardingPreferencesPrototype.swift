#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (#358). Three variants of the onboarding workout
// preferences step, mounted between Welcome and Back up. Choose the starting
// variant with `--prototype-onboarding-prefs=A|B|C`; the floating bar cycles
// them. State lives in memory only: nothing here writes a setting.

enum OnboardingPreferencesPrototype {
    static var initialVariant: Variant? {
        let prefix = "--prototype-onboarding-prefs="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        return Variant(rawValue: String(argument.dropFirst(prefix.count))) ?? .a
    }

    enum Variant: String, CaseIterable {
        case a = "A", b = "B", c = "C"

        var name: String {
            switch self {
            case .a: "Settings-style list"
            case .b: "Choice cards"
            case .c: "One question per page"
            }
        }
    }

    struct Choices {
        var unit: MeasurementUnit = .pounds
        var restTimerEnabled = true
        var rpeEnabled = false
    }
}

struct OnboardingPreferencesPrototypePage: View {
    let onContinue: () -> Void

    @State private var variant = OnboardingPreferencesPrototype.initialVariant ?? .a
    @State private var choices = OnboardingPreferencesPrototype.Choices()

    var body: some View {
        Group {
            switch variant {
            case .a: VariantA(choices: $choices, onContinue: onContinue)
            case .b: VariantB(choices: $choices, onContinue: onContinue)
            case .c: VariantC(choices: $choices, onContinue: onContinue)
            }
        }
        .toolbar {
            if !ProcessInfo.processInfo.arguments.contains("--prototype-hide-switcher") {
                ToolbarItem(placement: .principal) {
                    PrototypeSwitcher(variant: $variant, choices: choices)
                }
            }
        }
    }
}

// MARK: - A: Settings-style list

private struct VariantA: View {
    @Binding var choices: OnboardingPreferencesPrototype.Choices
    let onContinue: () -> Void

    var body: some View {
        LaunchExperiencePage(
            systemImage: "slider.horizontal.3",
            title: "Set up your workouts",
            summary: "You can change these anytime in Settings.",
            titleIdentifier: "OnboardingPreferencesTitle"
        ) {
            VStack(spacing: 0) {
                HStack {
                    Text("Weight unit")
                    Spacer()
                    Picker("Weight unit", selection: $choices.unit) {
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit == .pounds ? "lb" : "kg").tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                .padding(.vertical, 12)

                Divider()

                Toggle(isOn: $choices.restTimerEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rest timer")
                        Text("Counts down your rest after you complete a set.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.vertical, 12)

                Divider()

                Toggle(isOn: $choices.rpeEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("RPE")
                        Text("Rate how hard each set felt, from 6 to 10. A 10 means you couldn't do another rep.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .background(AppTheme.groupedSurface, in: RoundedRectangle(cornerRadius: 20))
        } actions: {
            ContinueButton(action: onContinue)
        }
    }
}

// MARK: - B: Choice cards

private struct VariantB: View {
    @Binding var choices: OnboardingPreferencesPrototype.Choices
    let onContinue: () -> Void

    var body: some View {
        LaunchExperiencePage(
            systemImage: "dumbbell",
            title: "How do you lift?",
            summary: "Pick what fits. You can change these anytime in Settings.",
            titleIdentifier: "OnboardingPreferencesTitle"
        ) {
            VStack(alignment: .leading, spacing: 24) {
                ChoiceQuestion(
                    title: "Weight unit",
                    detail: nil,
                    options: [("lb", MeasurementUnit.pounds), ("kg", .kilograms)],
                    selection: $choices.unit
                )
                ChoiceQuestion(
                    title: "Rest timer",
                    detail: "Counts down your rest after you complete a set.",
                    options: [("On", true), ("Off", false)],
                    selection: $choices.restTimerEnabled
                )
                ChoiceQuestion(
                    title: "Rate your effort (RPE)",
                    detail: "Rate how hard each set felt, from 6 to 10. A 10 means you couldn't do another rep.",
                    options: [("On", true), ("Off", false)],
                    selection: $choices.rpeEnabled
                )
            }
        } actions: {
            ContinueButton(action: onContinue)
        }
    }
}

private struct ChoiceQuestion<Value: Hashable>: View {
    let title: String
    let detail: String?
    let options: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                ForEach(options, id: \.1) { label, value in
                    let isSelected = selection == value
                    Button {
                        selection = value
                    } label: {
                        Text(label)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? AppTheme.onBrandAccent : AppTheme.textPrimary)
                    .background(
                        isSelected ? AnyShapeStyle(AppTheme.brandAccentFill) : AnyShapeStyle(AppTheme.groupedSurface),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - C: One question per page

private struct VariantC: View {
    @Binding var choices: OnboardingPreferencesPrototype.Choices
    let onContinue: () -> Void
    @State private var step = 0

    var body: some View {
        Group {
            switch step {
            case 0:
                question(
                    systemImage: "scalemass",
                    title: "Pounds or kilograms?",
                    summary: "Baros shows every weight in this unit.",
                    options: [("Pounds (lb)", MeasurementUnit.pounds), ("Kilograms (kg)", .kilograms)],
                    selection: $choices.unit
                )
            case 1:
                question(
                    systemImage: "timer",
                    title: "Use rest timers?",
                    summary: "When you complete a set, Baros counts down your rest.",
                    options: [("Use rest timers", true), ("No rest timers", false)],
                    selection: $choices.restTimerEnabled
                )
            default:
                question(
                    systemImage: "gauge.with.dots.needle.67percent",
                    title: "Rate your effort?",
                    summary: "RPE is a 6 to 10 rating of how hard a set felt. A 10 means you couldn't do another rep.",
                    options: [("Rate my sets", true), ("Skip RPE", false)],
                    selection: $choices.rpeEnabled
                )
            }
        }
        .id(step)
    }

    private func question<Value: Hashable>(
        systemImage: String,
        title: String,
        summary: String,
        options: [(String, Value)],
        selection: Binding<Value>
    ) -> some View {
        LaunchExperiencePage(
            systemImage: systemImage,
            title: title,
            summary: summary,
            titleIdentifier: "OnboardingPreferencesTitle"
        ) {
            VStack(spacing: 12) {
                ForEach(options, id: \.1) { label, value in
                    Button {
                        selection.wrappedValue = value
                    } label: {
                        HStack {
                            Text(label).font(.body.weight(.semibold))
                            Spacer()
                            Image(systemName: selection.wrappedValue == value ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(AppTheme.brandAccentForeground)
                        }
                        .padding(16)
                        .background(AppTheme.groupedSurface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textPrimary)
                }
                Text("Step \(step + 1) of 3 · Change it anytime in Settings.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 4)
            }
        } actions: {
            ContinueButton {
                if step < 2 { step += 1 } else { onContinue() }
            }
        }
    }
}

// MARK: - Shared prototype bits

private struct ContinueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Continue").frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(AppTheme.brandAccentFill)
        .accessibilityIdentifier("OnboardingPreferencesContinueButton")
    }
}

/// Visually distinct from the design under review: a yellow pill in the
/// navigation bar row.
private struct PrototypeSwitcher: View {
    @Binding var variant: OnboardingPreferencesPrototype.Variant
    let choices: OnboardingPreferencesPrototype.Choices

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 14) {
                Button { cycle(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityIdentifier("PrototypePreviousVariant")
                Text("\(variant.rawValue) — \(variant.name)")
                    .font(.caption.weight(.semibold))
                Button { cycle(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityIdentifier("PrototypeNextVariant")
            }
            Text("\(choices.unit == .pounds ? "lb" : "kg") · rest \(choices.restTimerEnabled ? "on" : "off") · RPE \(choices.rpeEnabled ? "on" : "off")")
                .font(.caption2.monospaced())
                .opacity(0.7)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(.yellow, in: Capsule())
    }

    private func cycle(_ delta: Int) {
        let all = OnboardingPreferencesPrototype.Variant.allCases
        let index = all.firstIndex(of: variant)!
        variant = all[(index + delta + all.count) % all.count]
    }
}
#endif
