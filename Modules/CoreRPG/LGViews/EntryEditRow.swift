// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditRow: View {
    public init(editController: any EntryDataEditable, itemId: UUID, entry: any EntryDataAccessable, cacheItemListModel: CacheItemListModel) {
        self.editController = editController
        self.itemId = itemId
        self.entry = entry
        self.cacheItemListModel = cacheItemListModel
    }
    
    let editController: any EntryDataEditable
    let itemId: UUID
    let entry: any EntryDataAccessable
    let cacheItemListModel: CacheItemListModel
    
    @Environment(ItemRootController.self) private var itemRootController
    @Environment(SearchModel.self) private var searchModel
    @Environment(ItemRootController.self) private var root
    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        VStack {
            if hasThumbnail, let cacheController = itemRootController.cacheControllable {
                HStack {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: model, entryId: entry.id)
                    
                    if editController.additioanlEnrtryViewType == .custom {
                        editController.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemRootController.configurable.module), textModel: nil)
                    }
                }
            }
            
            if editController.additioanlEnrtryViewType == .inline {
                editController.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemRootController.configurable.module), textModel: linkTextModel)
            } else {
                LinkHighlightTextView(model: linkTextModel)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if !hasThumbnail {
                if editController.additioanlEnrtryViewType == .custom {
                    editController.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: itemRootController.configurable.module), textModel: nil)
                }
            }
        }
    }
}

private extension EntryEditRow {
    var model: any ItemDataAccessable {
        editController.itemControllable.itemOrEmpty(for: itemId)
    }
    
    var linkTextModel: LinkHighlightTextModel {
        editController.linkTextModel(itemId: itemId, for: entry, linkController: itemRootController.linkControllable, searchModel: searchModel) 
    }
    
    var hasThumbnail: Bool {
        editController.thumbnailEntryViewType == .photo && itemRootController.cacheControllable != nil
    }
}
