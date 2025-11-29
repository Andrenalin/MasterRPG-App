// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditRow: View {
    public init(editController: any EntryDataEditable, entry: any EntryDataAccessable , cacheItemListModel: CacheItemListModel) {
        self.editController = editController
        self.entry = entry
        self.cacheItemListModel = cacheItemListModel
    }

    let editController: any EntryDataEditable
    let entry: any EntryDataAccessable
    let cacheItemListModel: CacheItemListModel
    
    @Environment(LinkRootController.self) private var linkController
    @Environment(SearchModel.self) private var searchModel

    public var body: some View {
        LinkHighlightTextView(model: linkTextModel)
            .multilineTextAlignment(.leading)
    }

    private var linkTextModel: LinkHighlightTextModel {
        editController.linkTextModel(for: entry, linkController: linkController, searchModel: searchModel)
    }
}
