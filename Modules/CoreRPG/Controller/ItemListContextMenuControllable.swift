// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

@MainActor
public protocol ItemListContextMenuControllable {
    func itemName(currentSelected: UUID?) -> String
    var collectionIcon: String { get }
    
    func duplicateItem(currentSelected: UUID?)
    func deleteItem(currentSelected: UUID?)
    func exportItem(currentSelected: UUID?) -> any NavigationDestination
    func generateLink(currentSelected: UUID?)
    
    func folderItems(currentSelected: UUID?) -> [FolderRepresentable]
    func moveItem(currentSelected: UUID?, to folder: FolderRepresentable)
    func collectionItems(currentSelected: UUID?) -> [FolderRepresentable]
    func addItem(currentSelected: UUID?, to folder: FolderRepresentable)

}
