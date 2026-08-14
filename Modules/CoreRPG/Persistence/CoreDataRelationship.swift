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

    /// Finds `existing`'s member matching `uuid`, or creates a fresh `Child`
    /// in `self`'s own managed object context — the "entryOrNew"/"photoOrNew"
    /// pattern every module's to-many relationship accessor hand-wrote.
    func childOrNew<Child: NSManagedObject & CoreDataId>(_ uuid: UUID, in existing: [Child]) -> Child {
        if let found = existing.first(where: { $0.uuid == uuid }) {
            return found
        }
        guard let managedObjectContext else {
            preconditionFailure("\(Self.self) must belong to a managed object context before adding \(Child.self).")
        }
        return Child(context: managedObjectContext)
    }
}
