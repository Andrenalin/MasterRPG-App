// @copyright André Trettin

import SwiftUI

@MainActor
struct FakeSearchController: SearchControllable, SearchRootControllable {
    init(
        searchModel: SearchModel = .preview(),
        itemControllable: any ItemControllable = FakeItemController.fake
    ) {
        self.searchModel = searchModel
        self.itemControllable = itemControllable
    }

    let searchModel: SearchModel

    func results(text: String) async -> [SearchResult] { [] }

    func scopedResults(text: String, focusId: UUID) async -> [SearchResult] { [] }
    func syncExpandResults(focusId: UUID) -> [SearchResult] { [] }

    func copy(listDisplayModel: ListDisplayModel) -> any SearchRootControllable { self }

    var itemControllable: any ItemControllable

    @MainActor
    static let fake = FakeSearchController()
}
