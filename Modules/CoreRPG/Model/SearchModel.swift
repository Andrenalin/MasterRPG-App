// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class SearchModel: Sendable {
    public init(searchText: String = "", isSearching: Bool = false, searchToken: ItemListCategory = .all, selectedTokens: [SearchTags] = [], categoryTags: [ItemListCategory] = [.adventure, .character, .photo, .weather], isHiddenItems: Bool = true) {
        self.searchText = searchText
        self.isSearching = isSearching
        self.searchToken = searchToken
        self.selectedTokens = selectedTokens
        self.categoryTags = categoryTags
        self.isHiddenItems = isHiddenItems
    }
    
    public var searchText: String
    public var isSearching: Bool
    public var searchToken: ItemListCategory
    public var selectedTokens: [SearchTags]

    public var categoryTags: [ItemListCategory]
    public var isHiddenItems: Bool = true
}

public extension SearchModel {
    static let preview = SearchModel()
    static func preview(search: String) -> SearchModel {
        SearchModel(searchText: search)
    }
}
