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
            SheetModel(source: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemController.config.module), level: level, name: entry.name, description: entry.content, entries: [])
        }
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
                updatedEntries.append(existing)
            } else {
                updatedEntries.append(SheetModel(source: ItemRowModel(itemId: model.id, entryId: entry.id, typeId: itemController.config.module), level: sheetModel.level, name: entry.name, description: entry.content, entries: []))
            }
        }
        sheetModel.entries = updatedEntries
    }
}
