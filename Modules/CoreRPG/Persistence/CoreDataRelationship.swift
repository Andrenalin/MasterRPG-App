// @copyright André Trettin

import CoreData

/// Generic CoreData relationship-accessor helpers. Replaces the identical
/// `NSSortDescriptor` → `sortedArray(using:)` → `compactMap`-cast pattern and
/// the identical "find-by-uuid-or-create" pattern that were duplicated,
/// nearly verbatim (differing only by entity type), across every module's
/// own `Model/DataModel+Extensions.swift`. See CODE_AUDIT §9.9.
public extension NSManagedObject {
    /// Sorts a to-many Core Data relationship — as read from a `@NSManaged`
    /// property, typed `Any?` at this generic boundary — by `sortKey`, cast
    /// to `T`. Returns `[]` when `set` isn't a `Set<T>` (e.g. the
    /// relationship hasn't been populated yet).
    static func sortedArray<T: NSManagedObject>(from set: Any?, sortKey: String = "index") -> [T] {
        guard let items = set as? Set<T> else { return [] }
        let sortDescriptor = NSSortDescriptor(key: sortKey, ascending: true)
        return (items as NSSet).sortedArray(using: [sortDescriptor]).compactMap { $0 as? T }
    }

    /// Syncs a to-many Core Data relationship from an incoming list of snapshot entries: maps
    /// each entry onto a found-or-new managed `Child` (keyed by `childId`),
    /// then deletes any previously-held `current` children that didn't survive the sync.
    ///
    /// The relationship's inverse rule is `Nullify` in every conforming model, so entries
    /// dropped from the relationship would otherwise remain as orphaned rows — locally and in
    /// CloudKit — if not explicitly deleted here. This exact ~15-line block (diff/map/delete)
    /// was duplicated verbatim across 10 modules' `DataController.applySnapshot(_:into:)`.
    /// See CODE_AUDIT §9.1.
    @discardableResult
    func syncEntries<Entry, Child: NSManagedObject & CoreDataId>(
        incoming: [Entry],
        current: [Child],
        childId: (Entry) -> UUID,
        map: (Entry, Child, Int) -> Void
    ) -> [Child] {
        // One dictionary per call instead of a linear search per entry: O(n) rather than O(n²)
        // for items with thousands of entries. First wins for a repeated uuid, as the search did.
        // See CODE_AUDIT_29 §7.2.
        var currentByUUID: [UUID: Child] = [:]
        for child in current {
            guard let uuid = child.uuid, currentByUUID[uuid] == nil else { continue }
            currentByUUID[uuid] = child
        }
        let newChildren = incoming.enumerated().map { index, entry -> Child in
            let uuid = childId(entry)
            let child: Child
            if let found = currentByUUID[uuid] {
                child = found
            } else if let managedObjectContext {
                child = Child(context: managedObjectContext)
            } else {
                preconditionFailure("\(Self.self) must belong to a managed object context before adding \(Child.self).")
            }
            map(entry, child, index)
            return child
        }
        let kept = Set(newChildren.map(ObjectIdentifier.init))
        for child in current where !kept.contains(ObjectIdentifier(child)) {
            managedObjectContext?.delete(child)
        }
        return newChildren
    }
}
