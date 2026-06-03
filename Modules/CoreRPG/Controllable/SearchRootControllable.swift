// @copyright André Trettin

import Foundation

public protocol SearchRootControllable: Sendable  {
    var searchModel: SearchModel { get }
    /// Standard search — results stored on `searchModel.results`.
    func results(text: String) async -> [SearchResult]
    /// Child/entry expansion — called by `loadChildrenViaSearch` when the user taps a chevron.
    /// Returns flat entry/child results for the focusId item:
    ///   - `specialCategory` → folder children via folder-mode search.
    ///   - Regular item → flat entry list via `inspectorEntryResults`.
    /// Must never return the item itself — that would make the item its own child (infinite recursion).
    func results(text: String, focusId: UUID) async -> [SearchResult]
    /// Scoped view — called by `performDetailSearch` to build the detail list for a parent model.
    /// Returns a view-rooted result: character-as-root for the character inspector,
    /// collection children for `ListRootView` detail, etc.
    /// Semantically different from `results(text:, focusId:)` — may return the item itself as root.
    func scopedResults(text: String, focusId: UUID) async -> [SearchResult]
    /// Synchronous child/entry expansion for `loadChildrenViaSearch`.
    ///
    /// Called when the user taps a chevron. Data is already in memory (the item was visible),
    /// so this is a pure `itemSync` map — no async DB access. Replaces the old `async results`
    /// call that unnecessarily suspended the main actor.
    ///
    /// - `specialCategory` → direct folder/collection children; nested folders get `canOpen=true`.
    /// - Regular item → flat entry list (inspector expansion).
    @MainActor func syncExpandResults(focusId: UUID) -> [SearchResult]

    /// Returns a new independent copy bound to `listDisplayModel` with its own `SearchModel`.
    /// Used by `FolderListController.copy(listModel:)` so detail controllers do not share
    /// the same search state as the parent list controller.
    @MainActor func copy(listDisplayModel: ListDisplayModel) -> any SearchRootControllable
}

