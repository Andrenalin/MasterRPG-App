// @copyright André Trettin

import CoreRPG
import Foundation

/// Drives the cross-module game search (`SearchGlobalController`/`SearchRootView`).
///
/// Named `GlobalSearchModel` — not `SearchModel` — to avoid colliding with `CoreRPG.SearchModel`,
/// the much more widely-used type of the same shape that drives `ListRootView`/`LinkItem*`'s
/// per-module list/inspector search. Both are `@Observable` and both are named "search model" for
/// what they do, but they are unrelated types with different shapes (this one keys `results` by
/// `NetworkModules` across every module at once; `CoreRPG.SearchModel` is scoped to one module and
/// carries `tagController`/`searchToken`/`filterId`). Since `GameRPG` also `import`s `CoreRPG`,
/// keeping the two names distinct avoids same-module shadowing silently resolving a bare
/// `SearchModel` reference to whichever type happens to be local to the file being edited.
@MainActor
@Observable
final class GlobalSearchModel {
    init(searchText: String = "") {
        self.searchText = searchText
        self.results = [:]
        self.isSearching = false
    }

    var searchText: String
    /// The level filter shown as a token in the search field ("Level 4 Adventures"). Holds at most
    /// one filter; set by Siri and the Find by Level intent, removed by the user.
    var levelTokens: [LevelSearchFilter] = []
    var results: [NetworkModules: [SearchResult]] = [:]
    var isSearching = false
    var selection: SearchResult?

    var playerMode: Bool = false

    /// What the list searches for; a change starts a new search.
    var request: GlobalSearchRequest {
        GlobalSearchRequest(text: searchText, levelTokens: levelTokens)
    }

    var hasSearch: Bool {
        !searchText.isEmpty || !levelTokens.isEmpty
    }

    /// `results` keeps an entry for every searched module, empty ones too.
    var hasResults: Bool {
        results.values.contains { !$0.isEmpty }
    }

    /// The level search the token or the typed text asks for: with a token the whole text narrows
    /// it, without one the text itself may be a level search ("level 4 adventures").
    var levelQuery: LevelSearchQuery? {
        if let token = levelTokens.first {
            return LevelSearchQuery(filter: token, text: searchText)
        }
        return LevelSearchQuery(parsing: searchText)
    }

    /// Shows the search for `term` from outside the list (Siri): a level search becomes the level
    /// token and its leftover words the text, any other term the text alone.
    func show(term: String) {
        if let query = LevelSearchQuery(parsing: term) {
            show(levelQuery: query)
        } else {
            levelTokens = []
            searchText = term
        }
    }

    func show(levelQuery: LevelSearchQuery) {
        levelTokens = [levelQuery.filter]
        searchText = levelQuery.text
    }

    /// Tracks the most-recently-started search task. Assigning a new task automatically
    /// cancels the previous one via `didSet` — mirrors `CoreRPG.SearchModel.currentTask` so
    /// correctness doesn't depend on callers manually cancelling before assigning.
    @ObservationIgnored var currentTask: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    deinit {
        currentTask?.cancel()
    }
}

/// The text and tokens of one search, the identity of the list's search task.
struct GlobalSearchRequest: Hashable {
    var text: String
    var levelTokens: [LevelSearchFilter]
}
