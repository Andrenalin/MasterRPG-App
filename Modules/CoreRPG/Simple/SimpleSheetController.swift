// @copyright André Trettin

import Foundation

/// A `SheetControllable` conformer for ``SimpleSheetEditingSession`` that
/// actually reconciles the live `SheetModel` tree with the underlying
/// `SimpleModel` — unlike `Modules/CoreRPG/Fake/FakeSheetController.swift`
/// (a hollow `.empty`/no-op stub only usable because CoreRPG's preview
/// fixtures inject a pre-built, static `SheetModel` tree directly and never
/// call `sheet(...)`/`update(...)` for real). Mirrors the shape of
/// `Modules/TableRPG/Controller/SheetController.swift`'s real, working
/// implementation, minus the TableRPG-specific dice-inline row and
/// cross-module link embedding — a `SimpleModel` entry has nothing to link
/// to.
///
/// One addition beyond a plain flat item: an entry whose `childId` resolves
/// to another real, registered item (see `SimpleSheetEditingSession`'s
/// wrapping-root/result-item pair) gets that item's own sheet nested as its
/// single child — mirroring `Modules/CharacterRPG/Controller/SheetController.swift`'s
/// `entry.valueId`-linked "group" pattern. This is how a session gives the
/// user something genuinely editable to serve as the whole outcome's title:
/// the root item's own header can never be edited in place, but an *entry*
/// can, so the actual content lives one level down, wrapped by one entry
/// whose name stands in for the root.
public struct SimpleSheetController: SheetControllable {
    public init(itemController: SimpleItemController) {
        self.itemController = itemController
    }

    let itemController: SimpleItemController

    @MainActor public func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let model = itemController.itemOrEmpty(for: itemId)
        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        let entries: [SheetModel] = isFolded ? [] : sheetEntries(root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        return SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.config.module), destination: destination, level: level, isShown: isShown, isFolded: isFolded, name: model.name, description: model.description, entries: entries)
    }

    @MainActor public func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> [SheetModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries.map { entry in
            sheet(entry: entry, root: root, itemId: itemId, level: level, moduleDepth: moduleDepth, isEditor: isEditor)
        }
    }

    @MainActor private func sheet(entry: SimpleEntryModel, root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> SheetModel {
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module)
        var nested: [SheetModel] = []
        if let child = itemController.itemSync(for: entry.childId) {
            // Built directly rather than through `sheet(root:itemId:...)`:
            // that method's `isFolded`/`isShown` defaults assume the usual
            // multi-module link-recursion case, which would leave this
            // single level of nesting collapsed and hidden — requiring an
            // extra manual "unfold" tap just to see the entries it exists
            // to hold. There's no reason for that here, so it's always
            // shown, always expanded.
            nested = [
                SheetModel(
                    source: ItemRowModel(itemId: entry.childId, typeId: itemController.config.module),
                    destination: destination,
                    level: level + 1,
                    isShown: true,
                    isFolded: false,
                    name: child.name,
                    description: child.description,
                    entries: sheetEntries(root: root, itemId: entry.childId, level: level + 1, moduleDepth: 0, isEditor: isEditor)
                )
            ]
        }
        return SheetModel(source: destination, level: level, name: entry.name, description: entry.content, entries: nested)
    }

    @MainActor public func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool) {
        let model = itemController.itemOrEmpty(for: sheetModel.source.itemId)

        unequalSet(lhs: &sheetModel.name, rhs: model.name) { changed in
            sheetModel.hasChanged = changed
        }
        unequalSet(lhs: &sheetModel.description, rhs: model.description) { changed in
            sheetModel.hasChanged = sheetModel.hasChanged || changed
        }

        guard !sheetModel.isFolded else { return }

        let entryIds = model.entries.map(\.id)
        sheetModel.entries.removeAll { entry in
            guard let entryId = entry.source.entryId else { return false }
            return !entryIds.contains(entryId)
        }

        var updatedEntries: [SheetModel] = []
        for entry in model.entries {
            if let existing = sheetModel.entries.first(where: { $0.source.entryId == entry.id }) {
                unequalSet(lhs: &existing.name, rhs: entry.name) { changed in
                    existing.hasChanged = changed
                }
                unequalSet(lhs: &existing.description, rhs: entry.content) { changed in
                    existing.hasChanged = existing.hasChanged || changed
                }
                // Cascade the reconcile into the nested child sheet (if
                // this entry links to a real item) so edits made to the
                // linked item's own entries refresh too.
                if let childSheet = existing.entries.first, itemController.itemSync(for: entry.childId) != nil {
                    update(root: root, sheetModel: childSheet, isEditor: isEditor)
                }
                updatedEntries.append(existing)
            } else {
                updatedEntries.append(sheet(entry: entry, root: root, itemId: model.id, level: sheetModel.level, moduleDepth: 0, isEditor: isEditor))
            }
        }
        sheetModel.entries = updatedEntries
    }
}
