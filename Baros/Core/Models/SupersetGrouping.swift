import Foundation

/// A superset is a run of two or more neighboring exercises that share a
/// group id. Readers only trust runs: a lone exercise with an id, or a group
/// split by a reorder elsewhere, displays as ungrouped or as separate runs.
/// Writers keep stored ids in that shape with `normalized(_:)`.
enum SupersetGrouping {
    struct Block<Member: Identifiable>: Identifiable where Member.ID == UUID {
        let members: [Member]

        var id: UUID { members[0].id }
        var isSuperset: Bool { members.count > 1 }
    }

    /// Splits exercises, in display order, into supersets and single exercises.
    static func blocks<Member: Identifiable>(
        _ members: [Member],
        groupID: (Member) -> UUID?
    ) -> [Block<Member>] where Member.ID == UUID {
        runRanges(members.map(groupID)).map { Block(members: Array(members[$0])) }
    }

    /// Whether the exercises at two neighboring positions are in one superset.
    static func areGrouped(_ groupIDs: [UUID?], _ index: Int, _ neighbor: Int) -> Bool {
        guard groupIDs.indices.contains(index), groupIDs.indices.contains(neighbor),
              abs(index - neighbor) == 1, let group = groupIDs[index] else { return false }
        return groupIDs[neighbor] == group
    }

    static func isGrouped(_ groupIDs: [UUID?], at index: Int) -> Bool {
        areGrouped(groupIDs, index, index - 1) || areGrouped(groupIDs, index, index + 1)
    }

    /// Clears ids that no run of two or more shares, and gives each later run
    /// of a repeated id its own fresh id.
    static func normalized(_ groupIDs: [UUID?], makeID: () -> UUID = UUID.init) -> [UUID?] {
        var result = groupIDs
        var seen: Set<UUID> = []
        for range in runRanges(groupIDs) {
            guard let group = groupIDs[range.lowerBound] else { continue }
            if range.count < 2 {
                result[range.lowerBound] = nil
            } else if !seen.insert(group).inserted {
                let fresh = makeID()
                for index in range { result[index] = fresh }
            }
        }
        return result
    }

    /// Links an exercise with the one above or below it. It pairs two single
    /// exercises, adds one to its neighbor's superset, or merges two supersets.
    /// The upper superset keeps its id, so its members don't change.
    static func linking(
        _ groupIDs: [UUID?],
        _ index: Int,
        with neighbor: Int,
        makeID: () -> UUID = UUID.init
    ) -> [UUID?] {
        let current = normalized(groupIDs, makeID: makeID)
        guard current.indices.contains(index), current.indices.contains(neighbor),
              abs(index - neighbor) == 1, !areGrouped(current, index, neighbor) else { return current }
        let ranges = runRanges(current)
        guard let upper = ranges.first(where: { $0.contains(min(index, neighbor)) }),
              let lower = ranges.first(where: { $0.contains(max(index, neighbor)) }) else { return current }
        let group = current[upper.lowerBound] ?? current[lower.lowerBound] ?? makeID()
        var result = current
        for position in upper.lowerBound..<lower.upperBound { result[position] = group }
        return result
    }

    /// Ungroups one exercise. A side left with one exercise is ungrouped too,
    /// and removing a middle exercise leaves the two sides as separate supersets.
    static func removing(_ groupIDs: [UUID?], at index: Int, makeID: () -> UUID = UUID.init) -> [UUID?] {
        guard groupIDs.indices.contains(index) else { return groupIDs }
        var result = normalized(groupIDs, makeID: makeID)
        result[index] = nil
        return normalized(result, makeID: makeID)
    }

    /// Fresh ids for a copied workout, so it never shares a group with its source.
    static func copied(_ groupIDs: [UUID?], makeID: () -> UUID = UUID.init) -> [UUID?] {
        var fresh: [UUID: UUID] = [:]
        return normalized(groupIDs, makeID: makeID).map { group in
            group.map { id in
                if let copy = fresh[id] { return copy }
                let copy = makeID()
                fresh[id] = copy
                return copy
            }
        }
    }

    /// Ranges of contiguous equal non-nil ids; every nil is its own range.
    private static func runRanges(_ groupIDs: [UUID?]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for index in groupIDs.indices.dropFirst() {
            if groupIDs[index] == nil || groupIDs[index] != groupIDs[index - 1] {
                ranges.append(start..<index)
                start = index
            }
        }
        if !groupIDs.isEmpty { ranges.append(start..<groupIDs.count) }
        return ranges
    }
}
