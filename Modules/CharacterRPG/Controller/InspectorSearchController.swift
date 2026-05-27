// @copyright André Trettin

import CoreRPG
import Foundation

/// Search controller for the character inspector.
///
/// Scoped to a single character: walks each entry whose `valueId` is set, loads the
/// linked sub-`ValueModel`, searches its name and all `ValueEntryModel` children, then
/// recurses into any further `valueId` links (up to 10 levels deep).
///
/// Only used in `FolderListController` when `listModel.parentModel` is a selected character.
struct InspectorSearchController: SearchControllable, Sendable {
    let itemController: ItemController
    let characterId: UUID

    var itemControllable: any ItemControllable { itemController }

    func searchItems(searchText: String) async -> [SearchResult] {
        await SearchController(itemController: itemController)
            .inspectorSearch(searchText: searchText, characterId: characterId)
    }
}
