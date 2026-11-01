// @copyright André Trettin

import CoreData
import Foundation
import os.log

/// The `uuid` of a managed object. A nil one is expected transiently under CloudKit sync
/// (attributes must be optional) but must never be re-randomized on every mapping call: that
/// makes one managed object resolve to a different domain id on each pass, which duplicates or
/// orphans items and entries and breaks file lookup by `fileId`. A new id is assigned once and
/// persisted with the object. See CODE_AUDIT_Pdf §5.4, CODE_AUDIT_23 §5.10.
public func repairedUuid<Object: NSManagedObject>(of object: Object, at keyPath: ReferenceWritableKeyPath<Object, UUID?>) -> UUID {
    if let uuid = object[keyPath: keyPath] { return uuid }
    let id = UUID()
    Logger.itemController.error("\(Object.self, privacy: .public) managed object had a nil uuid; assigning and persisting \(id, privacy: .public) to repair identity.")
    object[keyPath: keyPath] = id
    return id
}
