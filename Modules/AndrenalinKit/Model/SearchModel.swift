// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor @Observable
public final class SearchModel: Sendable {
    public init(modelContext: ModelContext, module: NetworkModules, searchText: String = "", searchToken: ItemListCategory = .all, selectedTokens: [SearchTags] = [], categoryTags: [ItemListCategory] = [.adventure, .character, .photo, .weather]) {
        self.modelContext = modelContext
        self.module = module
        self.searchText = searchText
        self.searchToken = searchToken
        self.selectedTokens = selectedTokens
        self.categoryTags = categoryTags
    }
    
    let modelContext: ModelContext
    let module: NetworkModules
    
    public var searchText: String
    internal(set) public var searchToken: ItemListCategory
    internal(set) public var selectedTokens: [SearchTags]
    var categoryTags: [ItemListCategory]

    var searchFieldText: String = ""
    
    var filteredTagSuggestions: [SearchTags] {
        guard searchFieldText.starts(with: "@") else { return [] }
        let tagSearch = searchFieldText.dropFirst()
        if !tagSearch.isEmpty {
            let predicate = #Predicate<TagDataModel>{ tag in tag.module == module.rawValue }
            let fetchDesc = FetchDescriptor<TagDataModel>(predicate: predicate, sortBy: [SortDescriptor(\.name)])
            let tags = try? modelContext.fetch(fetchDesc)
            return tags?.filter { $0.name.localizedCaseInsensitiveContains(tagSearch) }.map { SearchTags(tag: $0.name) } ?? []
        }
        return []
    }
    
    public var newSearchModel: SearchModel {
        SearchModel(modelContext: modelContext, module: module, searchText: "", searchToken: searchToken, selectedTokens: [], categoryTags: categoryTags)
    }
}

public extension SearchModel {
    static func preview(search: String = "") -> SearchModel {
        let modelContext = ModelContext(try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        return SearchModel(modelContext: modelContext, module: .photo, searchText: search)
    }

    static func preview(modelContext: ModelContext, module: NetworkModules, search: String = "") -> SearchModel {
        SearchModel(modelContext: modelContext, module: module, searchText: search)
    }
}
