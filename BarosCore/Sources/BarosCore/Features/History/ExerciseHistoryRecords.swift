import Foundation

public enum ExerciseHistoryRecordKind: String, CaseIterable {
    case heaviestRep
    case estimated1RM

    public var title: String {
        switch self {
        case .heaviestRep: "Heaviest Rep"
        case .estimated1RM: "Estimated 1RM"
        }
    }

    public var badgeTitle: String {
        switch self {
        case .heaviestRep: "Heaviest rep"
        case .estimated1RM: "Est. 1RM"
        }
    }
}

public struct ExerciseHistoryRecord {
    let setID: UUID
    public let workoutID: UUID
    let loggedExerciseID: UUID
    public let workoutTitle: String
    public let workoutDate: Date
    let exerciseOrder: Int
    let setOrder: Int
    public let weight: Double
    public let reps: Int
    public var value: Double

    public var displaySetNumber: Int { setOrder + 1 }

    fileprivate func isPreferred(over other: Self?) -> Bool {
        guard let other else { return true }
        if value != other.value { return value > other.value }
        // More reps at the same value is the better performance, and estimates
        // tie often because sets past the counted-rep cap share one value.
        if reps != other.reps { return reps > other.reps }
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
public struct ExerciseHistoryEstimatePoint: Identifiable {
    public let record: ExerciseHistoryRecord
    public var id: UUID { record.workoutID }
    public var date: Date { record.workoutDate }
    public var value: Double { record.value }
}

public struct ExerciseHistoryRecords {
    public let equipment: ExerciseEquipment
    public let hasMixedEquipment: Bool
    public let heaviestRep: ExerciseHistoryRecord?
    public let estimated1RM: ExerciseHistoryRecord?
    /// The most reps an estimate counts from one set.
    static let maximumEstimateReps = 10
    /// Chronological, one point per workout that has an eligible estimate set.
    public var estimateHistory: [ExerciseHistoryEstimatePoint] = []

    /// True when one set is the source of both records.
    public var recordsShareSource: Bool {
        guard let heaviestRep, let estimated1RM else { return false }
        return heaviestRep.setID == estimated1RM.setID
    }

    public func kinds(for setID: UUID) -> [ExerciseHistoryRecordKind] {
        var kinds: [ExerciseHistoryRecordKind] = []
        if heaviestRep?.setID == setID { kinds.append(.heaviestRep) }
        if estimated1RM?.setID == setID { kinds.append(.estimated1RM) }
        return kinds
    }

    /// Uses the same owner-scoped, identity-resolved full history as the detail screen.
    public static func make(
        from groups: [ExerciseHistorySessionGroup],
        equipmentRaw: String?
    ) -> ExerciseHistoryRecords? {
        guard let equipmentRaw, let equipment = ExerciseEquipment(rawValue: equipmentRaw),
              equipment != .bodyweight, equipment != .resistanceBand else { return nil }
        // Both records are measured in reps, so an exercise now logged by time has none.
        guard groups.first?.setEntries.first?.set.trackingMethod != .duration else { return nil }

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
                guard kind == .working || kind == .failure else { continue }
                // Epley loses accuracy past ten reps, so a longer set counts as
                // the ten reps it proves. Dropping it instead would let a much
                // heavier high-rep set lose to a light ten-rep set.
                let countedReps = min(reps, Self.maximumEstimateReps)
                var estimate = record
                estimate.value = countedReps == 1 ? weight : weight * (1 + Double(countedReps) / 30)
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
    public var shortUnitLabel: String {
        switch self {
        case .pounds: "lb"
        case .kilograms: "kg"
        }
    }

    /// The displayed number for a record. Recorded loads keep their logged
    /// precision; an estimate rounds to a whole pound or half kilogram so it
    /// never reads more exact than the inference behind it. Winners are
    /// chosen before this rounding.
    public func recordNumber(fromCanonicalPounds pounds: Double, isEstimate: Bool) -> String {
        let display = displayWeight(fromCanonicalPounds: pounds) ?? 0
        guard isEstimate else { return WorkoutFormatters.groupedNumber(display) }
        let step = self == .kilograms ? 0.5 : 1
        return WorkoutFormatters.groupedNumber((display / step).rounded() * step)
    }
}
