// @copyright André Trettin

import SwiftUI

@MainActor
struct FakeSearchController: SearchControllable, SearchRootControllable {
    let searchModel: SearchModel = .preview()
    
    func results(text: String) async -> [SearchResult] {
        []
    }
    
    var itemControllable: any ItemControllable

    @MainActor
    static let fake = FakeSearchController(itemControllable: FakeItemController.fake)
}
