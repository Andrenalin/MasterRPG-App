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

        let cyclicEntryIds = Self.cyclicEntryIds(in: indexedEntries)
        var resolvedParents: [UUID: UUID] = [:]
        for entry in entries {
            guard
                !cyclicEntryIds.contains(entry.id),
                let parentId = entry.parentId,
                let parent = indexedEntries[parentId],
                parent.kind == .group
            else {
                continue
            }
            resolvedParents[entry.id] = parentId
        }
        parentByEntryId = resolvedParents

        var groupedChildren: [UUID?: [RuleEntryModel]] = [:]
        for entry in entries {
            groupedChildren[resolvedParents[entry.id], default: []].append(entry)
        }
        childrenByParentId = groupedChildren
    }

    let entries: [RuleEntryModel]

    private let parentByEntryId: [UUID: UUID]
    /// `entries` grouped by resolved parent id (`nil` for roots), computed
    /// once here instead of `nodes(parentId:visited:)` re-scanning the full
    /// `entries` array at every level of every branch — O(n²) for a large
    /// imported rule/compendium hierarchy. See CODE_AUDIT_10 §7.3.
    private let childrenByParentId: [UUID?: [RuleEntryModel]]

    var roots: [Node] {
        nodes(parentId: nil, visited: [])
    }

    func parentId(for entryId: UUID) -> UUID? {
        parentByEntryId[entryId]
    }

    static func normalized(_ entries: [RuleEntryModel]) -> [RuleEntryModel] {
        let hierarchy = RuleEntryTree(entries: entries)
        return entries.map { entry in
            var normalizedEntry = entry
            normalizedEntry.parentId = hierarchy.parentId(for: entry.id)
            return normalizedEntry
        }
    }

    static func validParentGroups(
        for entryId: UUID,
        in entries: [RuleEntryModel]
    ) -> [RuleEntryModel] {
        ParentGroupLookup(entries: entries).validParentGroups(for: entryId)
    }

    /// The parent-group choices of every row of the quick editor from one pass over the entries.
    /// Each row used to rebuild the child map and walk the tree itself on every keystroke, which
    /// was quadratic for a rule with a few hundred entries. See CODE_AUDIT_26 §7.23.
    struct ParentGroupLookup: Sendable {
        init(entries: [RuleEntryModel]) {
            var indices: [UUID: Int] = [:]
            var children: [UUID: [UUID]] = [:]
            var groupEntries: [RuleEntryModel] = []
            for (index, entry) in entries.enumerated() {
                if indices[entry.id] == nil { indices[entry.id] = index }
                if let parentId = entry.parentId {
                    children[parentId, default: []].append(entry.id)
                }
                if entry.kind == .group { groupEntries.append(entry) }
            }
            indexById = indices
            childIdsByParent = children
            groups = groupEntries
        }

        private let indexById: [UUID: Int]
        private let childIdsByParent: [UUID: [UUID]]
        private let groups: [RuleEntryModel]

        /// The position of the first entry with `entryId`.
        func index(of entryId: UUID) -> Int? {
            indexById[entryId]
        }

        /// The groups `entryId` may be put into: not itself and not one of its descendants.
        func validParentGroups(for entryId: UUID) -> [RuleEntryModel] {
            var excludedIds: Set<UUID> = [entryId]
            var pending = childIdsByParent[entryId, default: []]
            while let currentId = pending.popLast() {
                guard currentId != entryId, excludedIds.insert(currentId).inserted else { continue }
                pending.append(contentsOf: childIdsByParent[currentId, default: []])
            }
            return groups.filter { !excludedIds.contains($0.id) }
        }
    }

    static func settingParent(
        _ parentId: UUID?,
        for entryId: UUID,
        in entries: [RuleEntryModel]
    ) -> [RuleEntryModel] {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else {
            return entries
        }

        if let parentId {
            let validIds = Set(validParentGroups(for: entryId, in: entries).map(\.id))
            guard validIds.contains(parentId) else { return entries }
        }

        var updated = entries
        updated[index].parentId = parentId
        return normalized(updated)
    }

    static func settingKind(
        _ kind: RuleEntryKind,
        for entryId: UUID,
        in entries: [RuleEntryModel]
    ) -> [RuleEntryModel] {
        guard let index = entries.firstIndex(where: { $0.id == entryId }) else {
            return entries
        }

        var updated = entries
        let current = updated[index]
        guard current.kind != kind else { return updated }

        let validParentIds = Set(validParentGroups(for: entryId, in: updated).map(\.id))
        let fallbackParentId = current.parentId.flatMap { parentId in
            validParentIds.contains(parentId) ? parentId : nil
        }

        updated[index].kind = kind
        if current.kind == .group && kind != .group {
            for childIndex in updated.indices
            where updated[childIndex].id != entryId
                && updated[childIndex].parentId == entryId {
                updated[childIndex].parentId = fallbackParentId
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
        var removedIds = Set(requestedEntries.map(\.id))
        for entry in requestedEntries where entry.kind == .group {
            removedIds.formUnion(descendantIds(of: entry.id, in: entries))
        }

        var remaining = entries.filter { !removedIds.contains($0.id) }
        for index in remaining.indices {
            if let parentId = remaining[index].parentId, removedIds.contains(parentId) {
                remaining[index].parentId = nil
            }
        }
        return normalized(remaining)
    }

    private func nodes(parentId: UUID?, visited: Set<UUID>) -> [Node] {
        let children = childrenByParentId[parentId] ?? []
        return children.compactMap { entry in
            guard !visited.contains(entry.id) else {
                return nil
            }
            let nextVisited = visited.union([entry.id])
            return Node(
                entry: entry,
                children: nodes(parentId: entry.id, visited: nextVisited)
            )
        }
    }

    private static func descendantIds(
        of entryId: UUID,
        in entries: [RuleEntryModel]
    ) -> Set<UUID> {
        var childIdsByParent: [UUID: [UUID]] = [:]
        for entry in entries {
            guard let parentId = entry.parentId else { continue }
            childIdsByParent[parentId, default: []].append(entry.id)
        }

        var descendants: Set<UUID> = []
        var pending = childIdsByParent[entryId, default: []]
        while let currentId = pending.popLast() {
            guard currentId != entryId, descendants.insert(currentId).inserted else {
                continue
            }
            pending.append(contentsOf: childIdsByParent[currentId, default: []])
        }
        return descendants
    }

    private static func cyclicEntryIds(
        in entriesById: [UUID: RuleEntryModel]
    ) -> Set<UUID> {
        var processed: Set<UUID> = []
        var cyclicEntryIds: Set<UUID> = []

        for startId in entriesById.keys where !processed.contains(startId) {
            var path: [UUID] = []
            var pathIndexById: [UUID: Int] = [:]
            var currentId: UUID? = startId

            while
                let candidateId = currentId,
                entriesById[candidateId] != nil,
                !processed.contains(candidateId)
            {
                if let cycleStartIndex = pathIndexById[candidateId] {
                    cyclicEntryIds.formUnion(path[cycleStartIndex...])
                    break
                }

                pathIndexById[candidateId] = path.count
                path.append(candidateId)
                currentId = entriesById[candidateId]?.parentId
            }
            processed.formUnion(path)
        }
        return cyclicEntryIds
    }
}
