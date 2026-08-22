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
    var results: [NetworkModules: [SearchResult]] = [:]
    var isSearching = false
    var selection: SearchResult?

    var playerMode: Bool = false

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
