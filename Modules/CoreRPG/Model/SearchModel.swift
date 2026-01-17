// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor @Observable
public final class SearchModel: Sendable {
    public init(tagController: TagController, module: NetworkModules, searchText: String = "", searchToken: ItemListCategory = .all, selectedTokens: [SearchTags] = [], categoryTags: [ItemListCategory] = [.adventure, .character, .photo, .weather]) {
        self.tagController = tagController
        self.module = module
        self.searchText = searchText
        self.searchToken = searchToken
        self.selectedTokens = selectedTokens
        self.categoryTags = categoryTags
    }
    
    let tagController: TagController
    let module: NetworkModules
    
    public var searchText: String
    public var searchToken: ItemListCategory
    public var selectedTokens: [SearchTags]
    var categoryTags: [ItemListCategory]
    var searchFieldText: String = ""
    
    public var searchTags: [SearchTags] = []
    
    func updateTagSuggestions() {
        guard searchFieldText.starts(with: "@") else {
            searchTags = []
            return
        }
        let tagSearch = searchFieldText.dropFirst()
        guard !tagSearch.isEmpty  else {
            searchTags = []
            return
        }
        Task.detached {
            await self.updateTagSuggestions(tagSearch: tagSearch)
        }
    }
    
    private func updateTagSuggestions(tagSearch: String.SubSequence) async {
        let tagController = TagController()
        let filteredSearchTags = tagController.sugguestionTags(module: module, search: String(tagSearch)).map { SearchTags(tag: $0) }

        Task { @MainActor in
            if searchTags != filteredSearchTags {
                searchTags = filteredSearchTags
            }
        }
    }
    
    public var newSearchModel: SearchModel {
        SearchModel(tagController: tagController, module: module, searchText: "", searchToken: searchToken, selectedTokens: [], categoryTags: categoryTags)
    }
}

public extension SearchModel {
    static func preview(tagController: TagController = .preview, module: NetworkModules = .photo, search: String = "") -> SearchModel {
        SearchModel(tagController: tagController, module: module, searchText: search)
    }
}

// MARK: - Search Tags

public struct SearchTags: Hashable, Equatable, Identifiable, Sendable {
    public let tag: String
    public var id: String { tag }

    static public let allCategory = SearchTags(tag: "All")
}
