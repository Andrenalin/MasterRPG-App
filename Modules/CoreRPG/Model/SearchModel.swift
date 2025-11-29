// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor @Observable
public final class SearchModel: Sendable {
    public init(modelContainer: ModelContainer, module: NetworkModules, searchText: String = "", searchToken: ItemListCategory = .all, selectedTokens: [SearchTags] = [], categoryTags: [ItemListCategory] = [.adventure, .character, .photo, .weather]) {
        self.modelContainer = modelContainer
        self.module = module
        self.searchText = searchText
        self.searchToken = searchToken
        self.selectedTokens = selectedTokens
        self.categoryTags = categoryTags
    }
    
    let modelContainer: ModelContainer
    let module: NetworkModules
    
    public var searchText: String
    internal(set) public var searchToken: ItemListCategory
    internal(set) public var selectedTokens: [SearchTags]
    var categoryTags: [ItemListCategory]
    var searchFieldText: String = ""
    
    internal(set) public var searchTags: [SearchTags] = []
    
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
    
    nonisolated private func updateTagSuggestions(tagSearch: String.SubSequence) async {
        let modelContext = ModelContext(modelContainer)
        let predicate = #Predicate<TagDataModel>{ tag in tag.module == module.rawValue }
        let fetchDesc = FetchDescriptor<TagDataModel>(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        let tags = try? modelContext.fetch(fetchDesc)
        let filteredSearchTags = tags?.filter { $0.name.localizedCaseInsensitiveContains(tagSearch) }.map { SearchTags(tag: $0.name) } ?? []
        Task { @MainActor in
            if searchTags != filteredSearchTags {
                searchTags = filteredSearchTags
            }
        }
    }
    
    public var newSearchModel: SearchModel {
        SearchModel(modelContainer: modelContainer, module: module, searchText: "", searchToken: searchToken, selectedTokens: [], categoryTags: categoryTags)
    }
}

public extension SearchModel {
    static func preview(search: String = "") -> SearchModel {
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return SearchModel(modelContainer: modelContainer, module: .photo, searchText: search)
    }

    static func preview(modelContainer: ModelContainer, module: NetworkModules, search: String = "") -> SearchModel {
        SearchModel(modelContainer: modelContainer, module: module, searchText: search)
    }
}
