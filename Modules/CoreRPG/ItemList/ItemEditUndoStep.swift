// @copyright André Trettin

import Foundation

/// Where an item edit was written, and so where undoing or redoing it writes.
public enum ItemEditUndoScope: Sendable {
    /// The item readers see: game memory during a game, the library outside one.
    case current
    /// The library and a loaded game copy: an editor-window edit during a game (`forceSave`).
    case forced
    /// Only the library, with the membership fields mirrored into a game copy: a folder edit
    /// made in the library UI. See CODE_AUDIT_Folder §5.21.
    case library
}

/// One user action: the changes it made to one or more items. A change keeps the item's value
/// before and after it, so undo reverts only what the action changed (a three-way merge onto the
/// item as it is now) instead of restoring a snapshot that also reverted every later sync merge
/// or game change. A step belongs to the game generation it was made in: after a game starts or
/// ends it no longer applies, because its scope would write into the wrong place.
/// See CODE_AUDIT_Edit_Save §5.1, §5.2, §5.5.
public struct ItemEditUndoStep {
    public struct Change {
        public let itemId: UUID
        public let before: any ModelType
        public let after: any ModelType
        public let scope: ItemEditUndoScope
    }

    public var changes: [Change]
    public let gameGeneration: Int

    public func contains(itemId: UUID) -> Bool {
        changes.contains { $0.itemId == itemId }
    }
}

/// Lengths of user text quoted in undo titles. See CODE_AUDIT_Edit_Save §9.9.
enum UndoTitleLimits {
    /// The characters of an entry name an undo title quotes ("Copy entry <name>").
    static let entryNameLength = 16
}
