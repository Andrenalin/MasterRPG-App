// @copyright André Trettin

import Foundation

public protocol SearchRootControllable: Sendable  {
    var searchModel: SearchModel { get }
    /// Standard search — results stored on `searchModel.results`.
    func results(text: String) async -> [SearchResult]
    /// Focused search scoped to `focusId` in folder mode — results stored on `searchModel.detailResults`.
    func results(text: String, focusId: UUID) async -> [SearchResult]
    /// Returns a new independent copy bound to `listDisplayModel` with its own `SearchModel`.
    /// Used by `FolderListController.copy(listModel:)` so detail controllers do not share
    /// the same search state as the parent list controller.
    @MainActor func copy(listDisplayModel: ListDisplayModel) -> any SearchRootControllable
}

