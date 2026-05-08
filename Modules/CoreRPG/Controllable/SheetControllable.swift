// @copyright André Trettin

import Foundation

public protocol SheetControllable: Sendable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, moduleDepth: Int, isEditor: Bool) -> SheetModel
    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> [SheetModel]
    
    @MainActor func unfold(root: RootManager, sheetModel: SheetModel)    
    @MainActor func update(root: RootManager, sheetModel: SheetModel, isEditor: Bool)
}

public extension SheetControllable {
    @MainActor func sheet(root: RootManager, itemId: UUID, destination: ItemRowModel?, level: Int, isShown: Bool, isEditor: Bool) -> SheetModel {
        sheet(root: root, itemId: itemId, destination: destination, level: level, isShown: isShown, moduleDepth: -3, isEditor: isEditor)
    }
    @MainActor func sheetEntries(root: RootManager, itemId: UUID, level: Int, moduleDepth: Int, isEditor: Bool) -> [SheetModel] {
        []
    }

    @MainActor func unfold(root: RootManager, sheetModel: SheetModel) {
        guard sheetModel.isFolded else { return }
        sheetModel.isFolded = false
        sheetModel.entries = sheetEntries(root: root, itemId: sheetModel.source.itemId, level: sheetModel.level, moduleDepth: 1, isEditor: true)
    }
}
