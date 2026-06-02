// @copyright André Trettin

import Foundation

public struct SearchResult: Identifiable, Equatable, Hashable, Sendable {
    public init(itemId: UUID, itemName: String, module: NetworkModules, category: ItemListCategory, entryId: UUID? = nil, entryName: String? = nil, matchedContent: String? = nil, relevanceScore: Int) {
        self.itemId = itemId
        self.itemName = itemName
        self.module = module
        self.category = category
        self.entryId = entryId
        self.entryName = entryName
        self.matchedContent = matchedContent
        self.relevanceScore = relevanceScore
    }
    
    public let itemId: UUID
    public let itemName: String
    public let module: NetworkModules
    public let category: ItemListCategory
    public let entryId: UUID?
    public let entryName: String?
    public let matchedContent: String?
    public let relevanceScore: Int

    public var id: String {
        if let entryId {
            return "\(itemId.uuidString)-\(entryId.uuidString)"
        }
        return itemId.uuidString
    }

    // Folder-mode tree structure: direct children of this result node.
    // Populated by listSearchResults / inspectorSearchResults in folder mode
    // and mapped to FolderListItemModel.children by buildFolder().
    public var children: [SearchResult] = []

    // True when this item has expandable children that were NOT included in this result
    // (lazy-loaded folder/collection, or an inspector entry-group with sub-values).
    // Mapped to FolderListItemModel.canOpen so the UI can render the chevron and
    // toggleFolder / canOpenFolder can act without an extra itemSync call.
    public var canOpen: Bool = false

    // True when this item should start expanded regardless of searchText or lastIsOpen.
    // Used by focusedCharacterInspector to show all entries on first appear without
    // requiring the user to manually tap the chevron.
    public var shouldOpen: Bool = false

    // When set, loadChildrenViaSearch uses this UUID as the focusId instead of itemId.
    // Used for group entries in the character inspector: itemId = characterId (for navigation)
    // but childFocusId = entry.valueId (the sub-value item whose entries should be loaded).
    public var childFocusId: UUID? = nil
}
