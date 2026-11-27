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
        let entries = itemController.reviewAwareItemOrEmpty(root: root, for: itemId).entries
        return RuleEntryTree(entries: entries).roots.map { node in
            sheet(
                node: node,
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
        node: RuleEntryTree.Node,
        root: RootManager,
        itemId: UUID,
        level: Int,
        moduleDepth: Int,
        isEditor: Bool
    ) -> SheetModel {
        let entry = node.entry
        let destination = ItemRowModel(itemId: itemId, entryId: entry.id, typeId: .rule)
        let links = LinkReplaceController.links(for: entry.content)
        let linkedSheets = links.compactMap { link -> SheetModel? in
            guard link.entryId == nil, link.command == nil else { return nil }
            let linkedSheet: SheetModel?
            if link.module == .rule {
                linkedSheet = sheet(
                    root: root,
                    itemId: link.itemId,
                    destination: destination,
                    level: level + 1,
                    isShown: false,
                    moduleDepth: moduleDepth + 1,
                    isEditor: isEditor
                )
            } else {
                linkedSheet = SheetLinkGuard.linkedSheet(
                    root: root,
                    module: link.module,
                    itemId: link.itemId,
                    destination: destination,
                    level: level + 1,
                    isEditor: isEditor
                )
            }
            linkedSheet?.linkNumber = link.linkNumber
            return linkedSheet
        }
        let childSheets = node.children.map { child in
            sheet(
                node: child,
                root: root,
                itemId: itemId,
                level: level + 1,
                moduleDepth: moduleDepth,
                isEditor: isEditor
            )
        }
        return SheetModel(
            source: destination,
            level: level,
            type: entry.kind == .group ? .group : .item,
            name: entry.name,
            description: entry.content,
            entries: childSheets + linkedSheets
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

        let existingEntries = entrySheetsById(
            in: sheetModel.entries,
            ownerId: model.id
        )
        let projectedEntries = sheetEntries(
            root: root,
            itemId: model.id,
            level: sheetModel.level,
            moduleDepth: 0,
            isEditor: isEditor
        )
        sheetModel.entries = reconciledEntrySheets(
            projectedEntries,
            existingEntries: existingEntries,
            ownerId: model.id,
            root: root,
            isEditor: isEditor
        )
    }

    @MainActor
    private func reconciledEntrySheets(
        _ projectedEntries: [SheetModel],
        existingEntries: [UUID: SheetModel],
        ownerId: UUID,
        root: RootManager,
        isEditor: Bool
    ) -> [SheetModel] {
        projectedEntries.map { projected in
            guard
                let entryId = projected.source.entryId,
                let existing = existingEntries[entryId]
            else {
                return projected
            }

            let contentChanged = existing.description != projected.description
            existing.hasChanged = existing.name != projected.name || contentChanged
            existing.source = projected.source
            existing.destination = projected.destination
            existing.level = projected.level
            existing.sheetType = projected.sheetType
            existing.isFolded = projected.isFolded
            existing.name = projected.name
            existing.description = projected.description
            existing.inlineEntries = projected.inlineEntries
            existing.canAdd = projected.canAdd
            existing.showHeader = projected.showHeader

            let projectedChildren = projected.entries.filter {
                isEntrySheet($0, ownedBy: ownerId)
            }
            let projectedLinks = projected.entries.filter {
                !isEntrySheet($0, ownedBy: ownerId)
            }
            let existingLinks = existing.entries.filter {
                !isEntrySheet($0, ownedBy: ownerId)
            }
            let childSheets = reconciledEntrySheets(
                projectedChildren,
                existingEntries: existingEntries,
                ownerId: ownerId,
                root: root,
                isEditor: isEditor
            )
            let linkSheets = contentChanged
                ? projectedLinks
                : reconciledLinkSheets(
                    projectedLinks,
                    existingLinks: existingLinks,
                    root: root,
                    isEditor: isEditor
                )
            existing.entries = childSheets + linkSheets
            return existing
        }
    }

    @MainActor
    private func reconciledLinkSheets(
        _ projectedLinks: [SheetModel],
        existingLinks: [SheetModel],
        root: RootManager,
        isEditor: Bool
    ) -> [SheetModel] {
        var existingById: [UUID: SheetModel] = [:]
        for link in existingLinks where existingById[link.id] == nil {
            existingById[link.id] = link
        }

        return projectedLinks.map { projected in
            guard let existing = existingById[projected.id] else {
                return projected
            }
            root.rootModel(for: existing.source.typeId)?.sheetControllable.update(
                root: root,
                sheetModel: existing,
                isEditor: isEditor
            )
            return existing
        }
    }

    @MainActor
    private func entrySheetsById(
        in sheets: [SheetModel],
        ownerId: UUID
    ) -> [UUID: SheetModel] {
        var result: [UUID: SheetModel] = [:]
        var pending = sheets
        var visited: Set<ObjectIdentifier> = []

        while let sheet = pending.popLast() {
            guard visited.insert(ObjectIdentifier(sheet)).inserted else { continue }
            if
                isEntrySheet(sheet, ownedBy: ownerId),
                let entryId = sheet.source.entryId,
                result[entryId] == nil
            {
                result[entryId] = sheet
            }
            pending.append(contentsOf: sheet.entries)
        }
        return result
    }

    @MainActor
    private func isEntrySheet(_ sheet: SheetModel, ownedBy ownerId: UUID) -> Bool {
        sheet.source.typeId == .rule
            && sheet.source.itemId == ownerId
            && sheet.source.entryId != nil
    }
}
