// @copyright André Trettin

import Foundation

/// Merges the entry lists of two replicas of a folder item: the union by id, where an id on
/// both sides is combined with `combine` (the local entry by default), in a deterministic
/// order (name, then id). Copied into nine item models before, where eight sorted by name only:
/// entries with equal names kept the `Set`'s random iteration order, so two devices could end
/// up with different orders for the same merge. See CODE_AUDIT_18 §9.9.
public enum FolderEntryMerge {
    public static func merged<Entry>(
        local: [Entry],
        remote: [Entry],
        id: (Entry) -> UUID,
        name: (Entry) -> String,
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
        return byId.values.sorted { lhs, rhs in
            switch name(lhs).localizedCompare(name(rhs)) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: id(lhs).uuidString < id(rhs).uuidString
            }
        }
    }
}
