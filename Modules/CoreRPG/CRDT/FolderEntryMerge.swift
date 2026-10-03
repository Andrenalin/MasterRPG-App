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
            switch name(lhs).localizedCompare(name(rhs)) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: id(lhs).uuidString < id(rhs).uuidString
            }
        }
        guard let childId else { return sorted }
        var seenChildren: Set<UUID> = []
        return sorted.filter { seenChildren.insert(childId($0)).inserted }
    }
}
