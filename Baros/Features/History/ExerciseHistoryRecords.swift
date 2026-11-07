import Foundation

enum ExerciseHistoryRecordKind: String, CaseIterable {
    case heaviestRep
    case estimated1RM

    var title: String {
        switch self {
        case .heaviestRep: "Heaviest Rep"
        case .estimated1RM: "Estimated 1RM"
        }
    }

    var badgeTitle: String {
        switch self {
        case .heaviestRep: "Heaviest rep"
        case .estimated1RM: "Est. 1RM"
        }
    }
}

struct ExerciseHistoryRecord {
    let setID: UUID
    let workoutID: UUID
    let loggedExerciseID: UUID
    let workoutTitle: String
    let workoutDate: Date
    let exerciseOrder: Int
    let setOrder: Int
    let weight: Double
    let reps: Int
    var value: Double

    var displaySetNumber: Int { setOrder + 1 }

    fileprivate func isPreferred(over other: Self?) -> Bool {
        guard let other else { return true }
        if value != other.value { return value > other.value }
        if workoutDate != other.workoutDate { return workoutDate > other.workoutDate }
        if workoutID != other.workoutID { return workoutID.uuidString < other.workoutID.uuidString }
        if exerciseOrder != other.exerciseOrder { return exerciseOrder < other.exerciseOrder }
        if setOrder != other.setOrder { return setOrder < other.setOrder }
        if loggedExerciseID != other.loggedExerciseID {
            return loggedExerciseID.uuidString < other.loggedExerciseID.uuidString
        }
        return setID.uuidString < other.setID.uuidString
    }
}

/// The best Estimated 1RM within one workout, for the progression chart.
struct ExerciseHistoryEstimatePoint: Identifiable {
    let record: ExerciseHistoryRecord
    var id: UUID { record.workoutID }
    var date: Date { record.workoutDate }
    var value: Double { record.value }
}

struct ExerciseHistoryRecords {
    let equipment: ExerciseEquipment
    let hasMixedEquipment: Bool
    let heaviestRep: ExerciseHistoryRecord?
    let estimated1RM: ExerciseHistoryRecord?
    /// Chronological, one point per workout that has an eligible estimate set.
    var estimateHistory: [ExerciseHistoryEstimatePoint] = []

    /// True when one set is the source of both records.
    var recordsShareSource: Bool {
        guard let heaviestRep, let estimated1RM else { return false }
        return heaviestRep.setID == estimated1RM.setID
    }

    func kinds(for setID: UUID) -> [ExerciseHistoryRecordKind] {
        var kinds: [ExerciseHistoryRecordKind] = []
        if heaviestRep?.setID == setID { kinds.append(.heaviestRep) }
        if estimated1RM?.setID == setID { kinds.append(.estimated1RM) }
        return kinds
    }

    /// Uses the same owner-scoped, identity-resolved full history as the detail screen.
    static func make(
        from groups: [ExerciseHistorySessionGroup],
        equipmentRaw: String?
    ) -> ExerciseHistoryRecords? {
        guard let equipmentRaw, let equipment = ExerciseEquipment(rawValue: equipmentRaw),
              equipment != .bodyweight, equipment != .resistanceBand else { return nil }

        var heaviest: ExerciseHistoryRecord?
        var estimated: ExerciseHistoryRecord?
        var hasMixedEquipment = false
        var estimateHistory: [ExerciseHistoryEstimatePoint] = []
        for group in groups {
            var workoutEstimate: ExerciseHistoryRecord?
            defer {
                if let workoutEstimate {
                    estimateHistory.append(ExerciseHistoryEstimatePoint(record: workoutEstimate))
                }
            }
            for entry in group.setEntries {
                let occurrence = entry.loggedExercise
                guard occurrence.hasSnapshotMetadata
                    || occurrence.exerciseSnapshotEquipmentRaw != ExerciseEquipment.other.rawValue else { continue }
                guard occurrence.exerciseSnapshotEquipmentRaw == equipmentRaw else {
                    hasMixedEquipment = true
                    continue
                }
                guard let weight = WorkoutNumericInputPolicy.validatedWeight(entry.set.weight), weight > 0,
                      let reps = WorkoutNumericInputPolicy.validatedReps(entry.set.reps),
                      let kind = SetKind(rawValue: entry.set.kindRaw) else { continue }
                let record = ExerciseHistoryRecord(
                    setID: entry.set.id,
                    workoutID: group.id,
                    loggedExerciseID: entry.loggedExercise.id,
                    workoutTitle: group.title,
                    workoutDate: group.startedAt,
                    exerciseOrder: entry.loggedExercise.orderIndex,
                    setOrder: entry.set.orderIndex,
                    weight: weight,
                    reps: reps,
                    value: weight
                )
                if record.isPreferred(over: heaviest) {
                    heaviest = record
                }
                guard reps <= 10, kind == .working || kind == .failure else { continue }
                var estimate = record
                estimate.value = reps == 1 ? weight : weight * (1 + Double(reps) / 30)
                if estimate.isPreferred(over: estimated) {
                    estimated = estimate
                }
                if estimate.isPreferred(over: workoutEstimate) {
                    workoutEstimate = estimate
                }
            }
        }
        return ExerciseHistoryRecords(
            equipment: equipment,
            hasMixedEquipment: hasMixedEquipment,
            heaviestRep: heaviest,
            estimated1RM: estimated,
            estimateHistory: estimateHistory.sorted { $0.date < $1.date }
        )
    }
}

extension MeasurementUnit {
    /// "lb" or "kg", for weights beside a value.
    var shortUnitLabel: String {
        switch self {
        case .pounds: "lb"
        case .kilograms: "kg"
        }
    }

    /// The displayed number for a record. Recorded loads keep their logged
    /// precision; an estimate rounds to a whole pound or half kilogram so it
    /// never reads more exact than the inference behind it. Winners are
    /// chosen before this rounding.
    func recordNumber(fromCanonicalPounds pounds: Double, isEstimate: Bool) -> String {
        let display = displayWeight(fromCanonicalPounds: pounds) ?? 0
        guard isEstimate else { return WorkoutFormatters.groupedNumber(display) }
        let step = self == .kilograms ? 0.5 : 1
        return WorkoutFormatters.groupedNumber((display / step).rounded() * step)
    }
}
