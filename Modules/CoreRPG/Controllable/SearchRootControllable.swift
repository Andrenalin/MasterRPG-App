// @copyright André Trettin

import Foundation

public protocol SearchRootControllable: Sendable  {
    var searchModel: SearchModel { get }
    
    // MARK: - Asynchronous Search (Database Access)
    
    /// Standard search — may load data from SwiftData if not cached.
    /// Results stored on `searchModel.results`.
    /// - Parameter text: The search query string
    /// - Returns: Array of search results matching the query
    /// - Note: Use `syncResults(text:)` instead when data is known to be in memory
    @MainActor func results(text: String) async -> [SearchResult]
    
    /// Child/entry expansion — called by `loadChildrenViaSearch` when the user taps a chevron.
    /// May load data from SwiftData if not cached.
    /// Returns flat entry/child results for the focusId item:
    ///   - `specialCategory` → folder children via folder-mode search.
    ///   - Regular item → flat entry list via `inspectorEntryResults`.
    /// - Warning: Must never return the item itself — that would make the item its own child (infinite recursion).
    /// - Note: This method is rarely used now that `syncExpandResults` handles most cases
    @MainActor func results(text: String, focusId: UUID) async -> [SearchResult]
    
    /// Scoped view — called by `performDetailSearch` to build the detail list for a parent model.
    /// May load data from SwiftData if not cached.
    /// Returns a view-rooted result: character-as-root for the character inspector,
    /// collection children for `ListRootView` detail, etc.
    /// - Note: Semantically different from `results(text:, focusId:)` — may return the item itself as root.
    @MainActor func scopedResults(text: String, focusId: UUID) async -> [SearchResult]
    
    // MARK: - Synchronous Search (In-Memory Only)
    
    /// Synchronous search using only in-memory data via `itemSync`.
    /// - Parameter text: The search query string
    /// - Returns: Array of search results matching the query
    /// - Note: Use this for updates when data is already loaded to avoid async suspension overhead.
    ///   Particularly important during observation stream updates where suspending the main actor
    ///   would cause unnecessary frame drops.
    @MainActor func syncResults(text: String) -> [SearchResult]
    
    /// Synchronous child/entry expansion for `loadChildrenViaSearch`.
    ///
    /// Called when the user taps a chevron. Data is already in memory (the item was visible),
    /// so this is a pure `itemSync` map — no async DB access.
    ///
    /// - Parameter focusId: The UUID of the item whose children should be expanded
    /// - Returns: Flat array of child/entry results
    /// - `specialCategory` → direct folder/collection children; nested folders get `canOpen=true`.
    /// - Regular item → flat entry list (inspector expansion).
    @MainActor func syncExpandResults(focusId: UUID) -> [SearchResult]
    
    /// Synchronous version of `scopedResults` using only in-memory data.
    /// - Parameters:
    ///   - text: The search query string
    ///   - focusId: The UUID of the parent item to scope the search to
    /// - Returns: View-rooted search results
    /// - Note: Use when switching between already-loaded items to avoid rendering stale data
    ///   while waiting for an async search to complete.
    @MainActor func syncScopedResults(text: String, focusId: UUID) -> [SearchResult]

    // MARK: - Factory
    
    /// Returns a new independent copy bound to `listDisplayModel` with its own `SearchModel`.
    /// - Parameter listDisplayModel: The display model to bind the new controller to
    /// - Returns: A new controller instance with isolated state
    /// - Note: Used by `FolderListController.copy(listModel:)` so detail controllers do not share
    ///   the same search state as the parent list controller.
    @MainActor func copy(listDisplayModel: ListDisplayModel) -> any SearchRootControllable
}

