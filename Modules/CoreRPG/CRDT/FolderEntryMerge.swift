// @copyright André Trettin

import Foundation

/// Merges the entry lists of two replicas of a folder item: the union by id, where an id on
/// both sides is combined with `combine` (the local entry by default), in a deterministic
/// order (name, then id). Copied into nine item models before, where eight sorted by name only:
/// entries with equal names kept the `Set`'s random iteration order, so two devices could end
/// up with different orders for the same merge. See CODE_AUDIT_18 §9.9.
public enum FolderEntryMerge {
    /// - Parameter childId: the member an entry points at. When given, a member listed by
    ///   two entries with different ids (Photo, Audio and Space mint a new entry id on every
    ///   move) is kept once — the first in the deterministic order. See CODE_AUDIT_Folder §5.18.
    public static func merged<Entry>(
        local: [Entry],
        remote: [Entry],
        id: (Entry) -> UUID,
        name: (Entry) -> String,
        childId: ((Entry) -> UUID)? = nil,
        combine: (_ local: Entry, _ remote: Entry) -> Entry = { local, _ in local }
    ) -> [Entry] {
        var byId: [UUID: Entry] = [:]
        byId.reserveCapacity(local.count + remote.count)
        for entry in local where byId[id(entry)] == nil {
            byId[id(entry)] = entry
        }
        for entry in remote {
            let entryId = id(entry)
            if let existing = byId[entryId] {
                byId[entryId] = combine(existing, entry)
            } else {
                byId[entryId] = entry
            }
        }
        let sorted = byId.values.sorted { lhs, rhs in
            // Locale-independent, so every device orders a merged folder alike (a localized
            // compare would differ per device language). See CODE_AUDIT_26 §5.53.
            let lhsName = name(lhs)
            let rhsName = name(rhs)
            if lhsName == rhsName { return id(lhs).uuidString < id(rhs).uuidString }
            return lhsName.compare(rhsName, options: [.literal]) == .orderedAscending
        }
        guard let childId else { return sorted }
        var seenChildren: Set<UUID> = []
        return sorted.filter { seenChildren.insert(childId($0)).inserted }
    }
}

public extension FolderEntryMerge {
    /// The entries-merge rule every item model uses. A folder keeps the union of both sides'
    /// members; which of them stay is then decided by each child's own `parentId`, once the
    /// import that merged them is applied (`EditControllable.repairFolders(itemIds:)`), so a
    /// member removed on one device does not come back. Every other category merges its entry
    /// list as one last-writer-wins value.
    ///
    /// Nine models carried their own copy of this choice, Adventure used last-writer-wins for
    /// folders, Dice had no folder case and Pdf unioned every category. See CODE_AUDIT_Folder §9.8.
    static func mergedEntries<Entry: Equatable>(
        category: ItemListCategory,
        local: CRDTDataUpdate<[Entry]>,
        remote: CRDTDataUpdate<[Entry]>,
        id: (Entry) -> UUID,
        name: (Entry) -> String,
        childId: @escaping (Entry) -> UUID,
        combine: (_ local: Entry, _ remote: Entry) -> Entry = { local, _ in local }
    ) -> CRDTDataUpdate<[Entry]> {
        guard category == .folder else { return local.merged(other: remote) }
        let members = merged(
            local: local.wrappedValue,
            remote: remote.wrappedValue,
            id: id,
            name: name,
            childId: childId,
            combine: combine
        )
        // The merged update marker, not a fresh one: merging two equal folders stays idempotent.
        return CRDTDataUpdate(wrappedValue: members, update: local.$update.merged(other: remote.$update))
    }
}

public extension FolderEntryMerge {
    /// `entries` with every member listed once, or `nil` when none is listed twice. A folder
    /// holds a member once, but Photo, Audio and Space mint a new entry id on every add, so two
    /// devices adding the same member (or one device adding it twice) leave two entries that
    /// CloudKit unions into two rows. The entry with the smallest id string stays: every device
    /// picks the same one, so their repairs agree instead of removing each other's survivor.
    /// The order of the remaining entries is kept.
    static func deduplicated<Entry>(
        _ entries: [Entry],
        id: (Entry) -> UUID,
        childId: (Entry) -> UUID
    ) -> [Entry]? {
        var winners: [UUID: UUID] = [:]
        for entry in entries {
            let child = childId(entry)
            let entryId = id(entry)
            if let winner = winners[child], winner.uuidString <= entryId.uuidString { continue }
            winners[child] = entryId
        }
        guard winners.count < entries.count else { return nil }
        var seen: Set<UUID> = []
        return entries.filter { winners[childId($0)] == id($0) && seen.insert(childId($0)).inserted }
    }
}
