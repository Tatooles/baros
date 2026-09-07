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

struct ExerciseHistoryRecords {
    let equipment: ExerciseEquipment
    let hasMixedEquipment: Bool
    let heaviestRep: ExerciseHistoryRecord?
    let estimated1RM: ExerciseHistoryRecord?

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
        for group in groups {
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
            }
        }
        return ExerciseHistoryRecords(
            equipment: equipment,
            hasMixedEquipment: hasMixedEquipment,
            heaviestRep: heaviest,
            estimated1RM: estimated
        )
    }
}
