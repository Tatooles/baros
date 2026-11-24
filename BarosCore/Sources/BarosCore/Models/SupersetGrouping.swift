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

    /// The one rule every add path follows: adding as a superset groups the new exercises together,
    /// but only when there are at least two of them.
    static func groupForAdding(_ count: Int, asSuperset: Bool) -> UUID? {
        asSuperset && count > 1 ? UUID() : nil
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

    /// A new order, as indices into the old one, with the superset ids in that order.
    public struct Arrangement: Equatable {
        public let order: [Int]
        public let groupIDs: [UUID?]
    }

    /// Moves one exercise so it ends up at `destination`, and works out its superset
    /// there. Between two members of one superset it joins that superset; beside the
    /// superset it came from it stays in it, so members can reorder; anywhere else it
    /// stands alone. Dragging a member clear of its superset is how it leaves, and
    /// `leavesSuperset` says it was dragged past the superset's end with nothing beyond.
    public static func movingExercise(
        _ groupIDs: [UUID?],
        from source: Int,
        to destination: Int,
        leavesSuperset: Bool = false,
        makeID: () -> UUID = UUID.init
    ) -> Arrangement {
        let current = normalized(groupIDs, makeID: makeID)
        guard current.indices.contains(source), current.indices.contains(destination) else {
            return Arrangement(order: Array(current.indices), groupIDs: current)
        }
        var order = Array(current.indices)
        order.insert(order.remove(at: source), at: destination)
        var groups = order.map { current[$0] }
        let above = destination > 0 ? groups[destination - 1] : nil
        let below = destination < groups.count - 1 ? groups[destination + 1] : nil
        let own = current[source]
        if let above, above == below {
            groups[destination] = above
        } else if let own, !leavesSuperset, own == above || own == below {
            groups[destination] = own
        } else {
            groups[destination] = nil
        }
        return Arrangement(order: order, groupIDs: normalized(groups, makeID: makeID))
    }

    /// Moves a whole block, a superset or a single exercise, so it becomes block
    /// `destination`. Supersets keep their members and never merge with a neighbor.
    public static func movingBlock(
        _ groupIDs: [UUID?],
        from source: Int,
        to destination: Int,
        makeID: () -> UUID = UUID.init
    ) -> Arrangement {
        let current = normalized(groupIDs, makeID: makeID)
        var ranges = runRanges(current)
        guard ranges.indices.contains(source), ranges.indices.contains(destination) else {
            return Arrangement(order: Array(current.indices), groupIDs: current)
        }
        ranges.insert(ranges.remove(at: source), at: destination)
        let order = ranges.flatMap { Array($0) }
        return Arrangement(order: order, groupIDs: order.map { current[$0] })
    }

    /// Whether two lists of ids, in the same exercise order, form the same supersets,
    /// whatever the ids themselves are.
    public static func sameSupersets(_ lhs: [UUID?], _ rhs: [UUID?]) -> Bool {
        // Normalized, a single is a run of one and a superset a run of two or more.
        lhs.count == rhs.count && runRanges(normalized(lhs)) == runRanges(normalized(rhs))
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
