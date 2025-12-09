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
    
    @Environment(ItemRootController.self) private var itemRootController
    @Environment(LinkRootController.self) private var linkController
    @Environment(SearchModel.self) private var searchModel

    public var body: some View {
        VStack {
            if editController.thumbnailEntryViewType == .photo, let cacheController = itemRootController.cacheControllable {
                HStack {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: model, entryId: entry.id)
                    
                    if editController.additioanlEnrtryViewType == .custom {
                        editController.additionalRowView(for: entry.id)
                    }
                }
            } else {
                if editController.additioanlEnrtryViewType == .custom {
                    editController.additionalRowView(for: entry.id)
                }
            }
            
            LinkHighlightTextView(model: linkTextModel)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    var model: any ItemDataAccessable {
        editController.model
    }

    private var linkTextModel: LinkHighlightTextModel {
        editController.linkTextModel(for: entry, linkController: linkController, searchModel: searchModel)
    }
}
