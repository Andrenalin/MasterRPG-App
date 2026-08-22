// @copyright André Trettin

import Foundation

/// Shared recursion-depth guard for the folder/collection tree walkers (`buildFolderTreeNode`,
/// `buildCharacterFolderNode`, `appendToFlat`, `flattenCachedChildren`, …).
///
/// `EditControllable.addItem(itemId:parentId:)` refuses to create a folder/collection cycle at
/// write time, so this limit should never actually bind in practice — it exists purely as
/// defense-in-depth so a cycle formed some other way (an import, a CloudKit merge conflict)
/// stops these recursive walks at a bounded depth instead of recursing until the stack
/// overflows. No real folder hierarchy in this app is expected to nest anywhere near this deep.
public enum FolderTreeDepthLimit {
    public static let max = 64
}
