import Foundation

public enum SupersetGrouping {
    public struct Block<Member: Identifiable>: Identifiable where Member.ID == UUID {
        public let members: [Member]

        public var id: UUID { members[0].id }
        public var isSuperset: Bool { members.count > 1 }
    }

    public static func blocks<Member: Identifiable>(
        _ members: [Member],
        groupID: (Member) -> UUID?
    ) -> [Block<Member>] where Member.ID == UUID {
        runRanges(members.map(groupID)).map { Block(members: Array(members[$0])) }
    }

    public static func areGrouped(_ groupIDs: [UUID?], _ index: Int, _ neighbor: Int) -> Bool {
        guard groupIDs.indices.contains(index), groupIDs.indices.contains(neighbor),
              abs(index - neighbor) == 1, let group = groupIDs[index] else { return false }
        return groupIDs[neighbor] == group
    }

    public static func isGrouped(_ groupIDs: [UUID?], at index: Int) -> Bool {
        areGrouped(groupIDs, index, index - 1) || areGrouped(groupIDs, index, index + 1)
    }

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

    public static func togglingLink(
        _ groupIDs: [UUID?],
        below upper: Int,
        makeID: () -> UUID = UUID.init
    ) -> [UUID?] {
        let lower = upper + 1
        var result = normalized(groupIDs, makeID: makeID)
        guard areGrouped(result, upper, lower) else {
            return linking(result, upper, with: lower, makeID: makeID)
        }
        guard let run = runRanges(result).first(where: { $0.contains(lower) }) else { return result }
        let fresh = makeID()
        for position in lower..<run.upperBound { result[position] = fresh }
        return normalized(result, makeID: makeID)
    }

    static func removing(_ groupIDs: [UUID?], at index: Int, makeID: () -> UUID = UUID.init) -> [UUID?] {
        guard groupIDs.indices.contains(index) else { return groupIDs }
        var result = normalized(groupIDs, makeID: makeID)
        result[index] = nil
        return normalized(result, makeID: makeID)
    }

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
