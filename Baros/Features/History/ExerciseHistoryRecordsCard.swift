import SwiftUI

struct ExerciseHistoryRecordsCard: View {
    let records: ExerciseHistoryRecords
    let weightUnit: MeasurementUnit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsInformation = false

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 0) {
                    Text("Records")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(BarosAdaptiveColor.dynamic(light: 0x594115, dark: 0xD8B764))
                    Button { showsInformation = true } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityLabel("About strength records")
                    .accessibilityIdentifier("AboutStrengthRecordsButton")
                    .padding(.vertical, -10)
                    Spacer()
                }

                if records.hasMixedEquipment {
                    Text("\(records.equipment.displayName) records")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if let heaviest = records.heaviestRep {
                    if dynamicTypeSize.isAccessibilitySize {
                        stackedRecords(heaviest)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 20) {
                                recordRow(heaviest, kind: .heaviestRep)
                                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                                estimatedRecord
                                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                            }
                            stackedRecords(heaviest)
                        }
                    }
                } else {
                    emptyState(
                        title: "No records yet",
                        message: "Requires a completed set with weight and reps in a finished workout."
                    )
                }
            }
            .foregroundStyle(AppTheme.textPrimary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
                .strokeBorder(
                    BarosAdaptiveColor.dynamic(light: 0xB98A2E, dark: 0xD8B764)
                        .opacity(colorScheme == .dark ? 0.35 : 0.30),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .sheet(isPresented: $showsInformation) {
            StrengthRecordsInformationView()
        }
    }

    private func stackedRecords(_ heaviest: ExerciseHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            recordRow(heaviest, kind: .heaviestRep)
            Divider()
            estimatedRecord
        }
    }

    @ViewBuilder
    private var estimatedRecord: some View {
        if let estimated = records.estimated1RM {
            recordRow(estimated, kind: .estimated1RM)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Estimated 1RM")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                emptyState(
                    title: "No estimate yet",
                    message: "Requires a completed working or failure set of 1–10 reps with weight."
                )
            }
        }
    }

    private func recordRow(_ record: ExerciseHistoryRecord, kind: ExerciseHistoryRecordKind) -> some View {
        let unit = weightUnit.fieldLabel.lowercased()
        let value = WorkoutFormatters.number(weightUnit.displayWeight(fromCanonicalPounds: record.value) ?? 0)
        let weight = WorkoutFormatters.number(weightUnit.displayWeight(fromCanonicalPounds: record.weight) ?? 0)
        let reps = record.reps == 1 ? "1 rep" : "\(record.reps) reps"
        let date = WorkoutFormatters.compactDate(record.workoutDate)
        return VStack(alignment: .leading, spacing: 6) {
            Text(kind.title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
            Text("\(kind == .estimated1RM ? "≈ " : "")\(value) \(unit)")
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: true, vertical: false)
                .monospacedDigit()
            Text("\(weight) \(unit) × \(reps)")
                .font(.footnote.weight(.medium))
            Text("Set \(record.displaySetNumber) · \(date)")
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
            Text(record.workoutTitle)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(kind.title), \(value) \(unit), from \(weight) \(unit) for \(reps), "
                + "Set \(record.displaySetNumber), \(record.workoutTitle), \(date)"
        )
        .accessibilityIdentifier("ExerciseRecord-\(kind.rawValue)")
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct StrengthRecordsInformationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section("Heaviest Rep") {
                        Text("Your heaviest recorded weight for at least one completed rep in a finished workout. Includes warmup, working, drop, and failure sets.")
                    }
                    section("Estimated 1RM") {
                        Text("An estimate from completed working and failure sets of 1–10 reps. For 2–10 reps, we use the Epley formula:")
                        Text("Weight × (1 + reps ÷ 30)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(AppTheme.textPrimary)
                        Text("A single rep uses its recorded weight.")
                        Text("The estimate does not account for effort.")
                    }
                    section("Matching equipment") {
                        Text("Records use matching equipment. Bodyweight and resistance-band exercises are not included. Weight means the load you recorded.")
                    }
                    section("Find the set in your history") {
                        Text("Badges mark the sets behind your current records. One set can hold both. For equal records, the most recent workout is shown. Records and badges update when your saved workouts change.")
                    }
                }
                .padding(AppTheme.shellPadding)
            }
            .background(AppTheme.canvasBackground)
            .navigationTitle("About strength records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
            content()
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ExerciseHistoryRecordBadges: View {
    let kinds: [ExerciseHistoryRecordKind]
    let setID: UUID

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { badges }
                .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .trailing, spacing: 4) { badges }
        }
    }

    private var badges: some View {
        ForEach(kinds, id: \.self) { kind in
            Text(kind.badgeTitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(BarosAdaptiveColor.dynamic(light: 0x594115, dark: 0x342809))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    BarosAdaptiveColor.dynamic(light: 0xF2D786, dark: 0xD8B764),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(kind.title)
                .accessibilityIdentifier("ExerciseRecordBadge-\(kind.rawValue)-\(setID.uuidString)")
        }
    }
}
