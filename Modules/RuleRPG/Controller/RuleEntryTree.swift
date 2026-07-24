// @copyright André Trettin

import Foundation

/// Projects the persisted flat rule-entry collection into a safe hierarchy.
///
/// Invalid parents, parents that are not groups, and members of a parent cycle
/// are treated as roots. Children of a malformed cyclic group can still be
/// presented beneath that now-root group.
struct RuleEntryTree: Sendable {
    struct Node: Identifiable, Equatable, Sendable {
        let entry: RuleEntryModel
        let children: [Node]

        var id: UUID { entry.id }
    }

    init(entries: [RuleEntryModel]) {
        self.entries = entries

        var indexedEntries: [UUID: RuleEntryModel] = [:]
        for entry in entries where indexedEntries[entry.id] == nil {
            indexedEntries[entry.id] = entry
        }

        let cyclicEntryIDs = Self.cyclicEntryIDs(in: indexedEntries)
        var resolvedParents: [UUID: UUID] = [:]
        for entry in entries {
            guard
                !cyclicEntryIDs.contains(entry.id),
                let parentID = entry.parentId,
                let parent = indexedEntries[parentID],
                parent.kind == .group
            else {
                continue
            }
            resolvedParents[entry.id] = parentID
        }
        parentByEntryID = resolvedParents
    }

    let entries: [RuleEntryModel]

    private let parentByEntryID: [UUID: UUID]

    var roots: [Node] {
        nodes(parentID: nil, visited: [])
    }

    func parentID(for entryID: UUID) -> UUID? {
        parentByEntryID[entryID]
    }

    static func normalized(_ entries: [RuleEntryModel]) -> [RuleEntryModel] {
        let hierarchy = RuleEntryTree(entries: entries)
        return entries.map { entry in
            var normalizedEntry = entry
            normalizedEntry.parentId = hierarchy.parentID(for: entry.id)
            return normalizedEntry
        }
    }

    static func validParentGroups(
        for entryID: UUID,
        in entries: [RuleEntryModel]
    ) -> [RuleEntryModel] {
        let excludedIDs = descendantIDs(of: entryID, in: entries).union([entryID])
        return entries.filter { entry in
            entry.kind == .group && !excludedIDs.contains(entry.id)
        }
    }

    static func settingParent(
        _ parentID: UUID?,
        for entryID: UUID,
        in entries: [RuleEntryModel]
    ) -> [RuleEntryModel] {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return entries
        }

        if let parentID {
            let validIDs = Set(validParentGroups(for: entryID, in: entries).map(\.id))
            guard validIDs.contains(parentID) else { return entries }
        }

        var updated = entries
        updated[index].parentId = parentID
        return normalized(updated)
    }

    static func settingKind(
        _ kind: RuleEntryKind,
        for entryID: UUID,
        in entries: [RuleEntryModel]
    ) -> [RuleEntryModel] {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return entries
        }

        var updated = entries
        let current = updated[index]
        guard current.kind != kind else { return updated }

        let validParentIDs = Set(validParentGroups(for: entryID, in: updated).map(\.id))
        let fallbackParentID = current.parentId.flatMap { parentID in
            validParentIDs.contains(parentID) ? parentID : nil
        }

        updated[index].kind = kind
        if current.kind == .group && kind != .group {
            for childIndex in updated.indices
            where updated[childIndex].id != entryID
                && updated[childIndex].parentId == entryID {
                updated[childIndex].parentId = fallbackParentID
            }
        }

        return normalized(updated)
    }

    static func removingEntries(
        at offsets: IndexSet,
        from entries: [RuleEntryModel]
    ) -> [RuleEntryModel] {
        let requestedEntries = offsets.compactMap { offset in
            entries.indices.contains(offset) ? entries[offset] : nil
        }
        var removedIDs = Set(requestedEntries.map(\.id))
        for entry in requestedEntries where entry.kind == .group {
            removedIDs.formUnion(descendantIDs(of: entry.id, in: entries))
        }

        var remaining = entries.filter { !removedIDs.contains($0.id) }
        for index in remaining.indices {
            if let parentID = remaining[index].parentId, removedIDs.contains(parentID) {
                remaining[index].parentId = nil
            }
        }
        return normalized(remaining)
    }

    private func nodes(parentID: UUID?, visited: Set<UUID>) -> [Node] {
        entries.compactMap { entry in
            guard parentByEntryID[entry.id] == parentID, !visited.contains(entry.id) else {
                return nil
            }
            let nextVisited = visited.union([entry.id])
            return Node(
                entry: entry,
                children: nodes(parentID: entry.id, visited: nextVisited)
            )
        }
    }

    private static func descendantIDs(
        of entryID: UUID,
        in entries: [RuleEntryModel]
    ) -> Set<UUID> {
        var childIDsByParent: [UUID: [UUID]] = [:]
        for entry in entries {
            guard let parentID = entry.parentId else { continue }
            childIDsByParent[parentID, default: []].append(entry.id)
        }

        var descendants: Set<UUID> = []
        var pending = childIDsByParent[entryID, default: []]
        while let currentID = pending.popLast() {
            guard currentID != entryID, descendants.insert(currentID).inserted else {
                continue
            }
            pending.append(contentsOf: childIDsByParent[currentID, default: []])
        }
        return descendants
    }

    private static func cyclicEntryIDs(
        in entriesByID: [UUID: RuleEntryModel]
    ) -> Set<UUID> {
        var processed: Set<UUID> = []
        var cyclicEntryIDs: Set<UUID> = []

        for startID in entriesByID.keys where !processed.contains(startID) {
            var path: [UUID] = []
            var pathIndexByID: [UUID: Int] = [:]
            var currentID: UUID? = startID

            while
                let candidateID = currentID,
                entriesByID[candidateID] != nil,
                !processed.contains(candidateID)
            {
                if let cycleStartIndex = pathIndexByID[candidateID] {
                    cyclicEntryIDs.formUnion(path[cycleStartIndex...])
                    break
                }

                pathIndexByID[candidateID] = path.count
                path.append(candidateID)
                currentID = entriesByID[candidateID]?.parentId
            }
            processed.formUnion(path)
        }
        return cyclicEntryIDs
    }
}
