import SwiftUI

struct ExerciseHistoryRecordsCard: View {
    let records: ExerciseHistoryRecords
    let weightUnit: MeasurementUnit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsInformation = false

    var body: some View {
        journalRecords
            .sheet(isPresented: $showsInformation) {
                StrengthRecordsInformationView()
            }
    }

    private var journalRecords: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Records").font(.headline)
                Spacer()
                Button { showsInformation = true } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("About strength records")
                .accessibilityIdentifier("AboutStrengthRecordsButton")
            }
            .padding(.vertical, -8)

            if records.hasMixedEquipment {
                Text("\(records.equipment.displayName) records")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            if let heaviest = records.heaviestRep {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
                layout {
                    recordTile { journalRecord(heaviest, kind: .heaviestRep) }
                    recordTile {
                        if let estimated = records.estimated1RM {
                            journalRecord(estimated, kind: .estimated1RM)
                        } else {
                            estimatedRecord
                        }
                    }
                }
            } else {
                recordTile {
                    emptyState(title: "No records yet", message: "Requires a completed set with weight and reps in a finished workout.")
                }
            }
        }
    }

    private func recordTile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(AppTheme.groupedSurface, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    private func journalRecord(_ record: ExerciseHistoryRecord, kind: ExerciseHistoryRecordKind) -> some View {
        let displayValue = weightUnit.displayWeight(fromCanonicalPounds: record.value) ?? 0
        let value = WorkoutFormatters.number(kind == .estimated1RM ? displayValue.rounded() : displayValue)
        let unit = weightUnit.fieldLabel.lowercased()
        let weight = WorkoutFormatters.number(weightUnit.displayWeight(fromCanonicalPounds: record.weight) ?? 0)
        let date = record.workoutDate.formatted(.dateTime.month(.abbreviated).day())
        let number = Text("\(kind == .estimated1RM ? "≈ " : "")\(value)")
            .font(.title.bold().monospacedDigit())
            .foregroundColor(AppTheme.textPrimary)
        let unitLabel = Text(unit).font(.caption).foregroundColor(AppTheme.textSecondary)
        return VStack(alignment: .leading, spacing: 8) {
            Text(kind.title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Text("\(number) \(unitLabel)")
                .fixedSize(horizontal: false, vertical: true)
            Text("\(weight) × \(record.reps) · \(record.workoutTitle) · \(date)")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(kind.title), \(value) \(unit), from \(weight) \(unit) for \(record.reps) reps, "
                + "Set \(record.displaySetNumber), \(record.workoutTitle), \(WorkoutFormatters.compactDate(record.workoutDate))"
        )
        .accessibilityIdentifier("ExerciseRecord-\(kind.rawValue)")
    }

    private var estimatedRecord: some View {
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
