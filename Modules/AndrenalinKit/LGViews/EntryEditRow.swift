// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditRow<Controller: EntryEditControllable>: View {
    public init(entryEditController: Controller, entry: Controller.EditDataModel.DataModel, cacheItemListModel: CacheItemListModel) {
        self.entryEditController = entryEditController
        self.entry = entry
        self.cacheItemListModel = cacheItemListModel
    }

    let entryEditController: Controller
    let entry: Controller.EditDataModel.DataModel
    let cacheItemListModel: CacheItemListModel
    
    @Environment(LinkRootController.self) private var linkController
    @Environment(SearchModel.self) private var searchModel

    public var body: some View {
        LinkHighlightTextView(model: linkTextModel)
            .multilineTextAlignment(.leading)
    }

    private var linkTextModel: LinkHighlightTextModel {
        entryEditController.linkTextModel(for: entry, linkController: linkController, searchModel: searchModel)
    }
}

