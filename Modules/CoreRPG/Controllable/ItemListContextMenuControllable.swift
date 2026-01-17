// @copyright André Trettin

import SwiftUI

@MainActor
public protocol ItemListContextMenuControllable {
    func itemName(currentSelected: UUID?) -> String
    var collectionIcon: String { get }
    
    func duplicateItem(currentSelected: UUID?) async
    func deleteItem(currentSelected: UUID?) -> [ItemRowModel]
    func exportItem(currentSelected: UUID?) -> any NavigationDestination
    func generateLink(currentSelected: UUID?)
    func groupEditor(currentSelected: UUID?) -> any NavigationDestination
    
    func folderItems(currentSelected: UUID?) -> [FolderRepresentable]
    func moveItem(currentSelected: UUID?, to folder: FolderRepresentable)
    func collectionItems(currentSelected: UUID?) -> [FolderRepresentable]
    func addItem(currentSelected: UUID?, to folder: FolderRepresentable)

}
