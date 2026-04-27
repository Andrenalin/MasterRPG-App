// @copyright André Trettin

import Foundation

public protocol SheetControllable: Sendable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int) -> SheetModel

    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int) -> [SheetModel]
    @MainActor func unfold(root: RootManager, sheetModel: SheetModel)
}

public extension SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool) -> SheetModel {
        sheet(root: root, itemId: itemId, destination: destination, level: level, isShown: isShown, moduleDepth: 0)
    }
    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int) -> [SheetModel] {
        []
    }

    @MainActor func unfold(root: RootManager, sheetModel: SheetModel) {
        guard sheetModel.isFolded else { return }
        sheetModel.isFolded = false
        sheetModel.entries = sheetEntries(root: root, itemId: sheetModel.source.itemId, level: sheetModel.level)
    }
}
