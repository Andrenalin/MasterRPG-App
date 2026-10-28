// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class SearchModel: Sendable {
    public init(tagController: TagController, module: NetworkModules, searchText: String = "", selectedTokens: [SearchTags] = [], categoryTags: [ItemListCategory] = [.adventure, .character, .photo, .weather]) {
        self.tagController = tagController
        self.module = module
        self.searchText = searchText
        self.selectedTokens = selectedTokens
        self.categoryTags = categoryTags
    }

    public let tagController: TagController
    let module: NetworkModules

    public var searchText: String
    public var selectedTokens: [SearchTags]
    var categoryTags: [ItemListCategory]
    var searchFieldText: String = ""
    
    public var searchTags: [SearchTags] = []
    
    // new search properties
    var isSearching = false
    var results: [SearchResult] = []
    var detailResults: [SearchResult] = []

    /// True after a non-empty search completed with zero results.
    /// Drives `ContentUnavailableView.search` in list and inspector views.
    /// Distinct from `listModel.list.isEmpty` because `buildList` preserves the previous list
    /// when results are empty (prevents flickering), so `.list.isEmpty` would never be true.
    var searchReturnedNoResults: Bool = false
    
    var selection: SearchResult?
    public var filterId: UUID?

    /// Tracks the most-recently-scheduled background search task.
    /// Assigning a new task automatically cancels the previous one via `didSet`.
    /// 
    /// Alternative approach for future consideration: Use `AsyncStream` with debouncing
    /// to handle rapid search text changes more elegantly. Example:
    /// ```swift
    /// // In a view or controller:
    /// Task {
    ///     for await searchText in searchTextStream.debounce(for: .milliseconds(300)) {
    ///         await performSearch(text: searchText)
    ///     }
    /// }
    /// ```
    @ObservationIgnored public var currentTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    /// Token of the scoped detail search (`scheduleDetailSearch`). Separate from `currentTask`
    /// because a detail list can share this model with the root list (the module detail views
    /// receive the root's controller): both react to the same list-mode toggle, and with one
    /// token the later `scheduleDetailSearch` cancelled the root list's `scheduleSearch`, so the
    /// root list refreshed only after the next typed search.
    @ObservationIgnored public var detailTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    /// Incremented when a root search starts. A search that finishes after a newer one started
    /// discards its results instead of overwriting the newer ones; this also covers searches
    /// started outside `currentTask`, which cancel-and-replace does not reach.
    /// See CODE_AUDIT_Folder §3.19.
    @ObservationIgnored var searchGeneration = 0

    /// Separate token for tag-suggestion lookups so they never cancel — or get cancelled by —
    /// the main search running on `currentTask`.
    @ObservationIgnored var tagTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    deinit {
        currentTask?.cancel()
        detailTask?.cancel()
        tagTask?.cancel()
    }
    
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
        tagTask = Task {
            await self.updateTagSuggestions(tagSearch: tagSearch)
        }
    }
    
    @MainActor
    private func updateTagSuggestions(tagSearch: String.SubSequence) async {
        let filteredSearchTags = tagController.suggestionTags(module: module, search: String(tagSearch)).map { SearchTags(tag: $0) }

        if searchTags != filteredSearchTags {
            searchTags = filteredSearchTags
        }
    }
    
    public var newSearchModel: SearchModel {
        SearchModel(tagController: tagController, module: module, searchText: "", selectedTokens: [], categoryTags: categoryTags)
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
}
