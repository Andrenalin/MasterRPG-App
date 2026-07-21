// @copyright André Trettin

import CoreRPG
import Foundation

struct SheetController: Sendable {
    let itemController: ItemController
}

extension SheetController: SheetControllable {
    @MainActor
    func sheet(
        root: RootManager,
        itemId: UUID,
        destination: ItemRowModel?,
        level: Int,
        isShown: Bool,
        moduleDepth: Int,
        isEditor: Bool
    ) -> SheetModel {
        let model = itemController.reviewAwareItemOrEmpty(root: root, for: itemId)
        let isFolded = moduleDepth >= 1 || (isEditor && level > 0)
        let sections = isFolded ? [] : sheetEntries(
            root: root,
            itemId: itemId,
            level: level,
            moduleDepth: moduleDepth,
            isEditor: isEditor
        )
        return SheetModel(
            source: ItemRowModel(itemId: itemId, typeId: .rule),
            destination: destination,
            level: level,
            isShown: isShown,
            isFolded: isFolded,
            name: model.name,
            description: model.description,
            entries: sections
        )
    }

    @MainActor
    func sheetEntries(
        root: RootManager,
        itemId: UUID,
        level: Int,
        moduleDepth: Int,
        isEditor: Bool
    ) -> [SheetModel] {
        itemController.reviewAwareItemOrEmpty(root: root, for: itemId).entries.map { entry in
            sheet(
                entry: entry,
                root: root,
                itemId: itemId,
                level: level,
                moduleDepth: moduleDepth,
                isEditor: isEditor
            )
        }
    }

    @MainActor
    private func sheet(
        entry: RuleEntryModel,
        root: RootManager,
        itemId: UUID,
        level: Int,
        moduleDepth: Int,
        isEditor: Bool
    ) -> SheetModel {
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: .rule)
        let links = LinkReplaceController.links(for: entry.content)
        let linkedSheets = links.compactMap { link -> SheetModel? in
            guard link.entryId == nil else { return nil }
            if link.module == .rule {
                return sheet(
                    root: root,
                    itemId: link.itemId,
                    destination: destination,
                    level: level + 1,
                    isShown: false,
                    moduleDepth: moduleDepth + 1,
                    isEditor: isEditor
                )
            }
            return root.rootModel(for: link.module)?.sheetControllable.sheet(
                root: root,
                itemId: link.itemId,
                destination: destination,
                level: level + 1,
                isShown: false,
                moduleDepth: 0,
                isEditor: isEditor
            )
        }
        return SheetModel(
            source: destination,
            level: level,
            name: entry.name,
            description: entry.content,
            entries: linkedSheets
        )
    }

    @MainActor
    func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool) {
        let model = itemController.reviewAwareItemOrEmpty(
            root: root,
            for: sheetModel.source.itemId
        )
        unequalSet(lhs: &sheetModel.name, rhs: model.name) { changed in
            sheetModel.hasChanged = changed
        }
        unequalSet(lhs: &sheetModel.description, rhs: model.description) { changed in
            sheetModel.hasChanged = sheetModel.hasChanged || changed
        }
        guard !sheetModel.isFolded else { return }

        let existing = Dictionary(
            uniqueKeysWithValues: sheetModel.entries.compactMap { entry in
                entry.source.entryId.map { ($0, entry) }
            }
        )
        sheetModel.entries = model.entries.map { entry in
            if let current = existing[entry.id] {
                var linksChanged = false
                unequalSet(lhs: &current.name, rhs: entry.name) { changed in
                    current.hasChanged = changed
                }
                unequalSet(lhs: &current.description, rhs: entry.content) { changed in
                    current.hasChanged = current.hasChanged || changed
                    linksChanged = changed
                }

                if linksChanged {
                    current.entries = sheet(
                        entry: entry,
                        root: root,
                        itemId: model.id,
                        level: sheetModel.level,
                        moduleDepth: 0,
                        isEditor: isEditor
                    ).entries
                } else {
                    current.entries.forEach { linked in
                        root.rootModel(for: linked.source.typeId)?.sheetControllable.update(
                            root: root,
                            sheetModel: linked,
                            isEditor: isEditor
                        )
                    }
                }
                return current
            }
            return sheet(
                entry: entry,
                root: root,
                itemId: model.id,
                level: sheetModel.level,
                moduleDepth: 0,
                isEditor: isEditor
            )
        }
    }
}
