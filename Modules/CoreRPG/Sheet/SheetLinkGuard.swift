// @copyright André Trettin

import Foundation

/// Builds the sheet of an item another module's entry links to, and refuses a link that leads back
/// into a sheet that is already being built.
///
/// Every module's sheet controller embeds the sheets of the items its entries link to, and each
/// hop restarts with `moduleDepth: 0`, so a Character entry linking a Map whose room links the
/// same Character recursed until the stack overflowed. Sheet building is synchronous on the main
/// actor, so the (module, item) pairs being built right now form a stack that is entered and
/// left around each hop. The same item in two different branches is not a cycle and is built
/// both times. See CODE_AUDIT_22 §5.1.
///
/// Precondition: every module's `sheet(...)` is synchronous. The stack is shared state, so a
/// builder that suspends would let two builds interleave and refuse a legitimate link as a cycle;
/// such a builder has to carry the stack as a parameter instead. The item at the top of a build is
/// not registered, so a link cycle is expanded once more than needed (its second copy is the one
/// that stops). See CODE_AUDIT_22a §3.1, §5.8.
@MainActor
public enum SheetLinkGuard {
    private struct Key: Hashable {
        let module: NetworkModules
        let itemId: UUID
    }

    private static var building: Set<Key> = []

    /// The linked item's sheet, or `nil` when the module is unknown or the item is already being
    /// built further up (a link cycle).
    public static func linkedSheet(
        root: RootManager,
        module: NetworkModules,
        itemId: UUID,
        destination: ItemRowModel?,
        level: Int,
        moduleDepth: Int = 0,
        isEditor: Bool
    ) -> SheetModel? {
        guard let rootModel = root.rootModel(for: module) else { return nil }
        let key = Key(module: module, itemId: itemId)
        guard building.insert(key).inserted else { return nil }
        defer { building.remove(key) }
        return rootModel.sheetControllable.sheet(
            root: root,
            itemId: itemId,
            destination: destination,
            level: level,
            isShown: false,
            moduleDepth: moduleDepth,
            isEditor: isEditor
        )
    }
}
