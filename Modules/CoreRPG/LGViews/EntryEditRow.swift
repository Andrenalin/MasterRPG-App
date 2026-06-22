// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditRow: View {
    public init(root: any ItemRootControllable, editController: any EntryDataEditable, itemId: UUID, entry: any EntryDataAccessable, cacheItemListModel: CacheItemListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel) {
        self.root = root
        self.editController = editController
        self.itemId = itemId
        self.entry = entry
        self.cacheItemListModel = cacheItemListModel
        self.listDisplayModel = listDisplayModel
        self.searchModel = searchModel
    }

    let root: any ItemRootControllable
    let editController: any EntryDataEditable
    let itemId: UUID
    let entry: any EntryDataAccessable
    let cacheItemListModel: CacheItemListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel

    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        VStack {
            if hasThumbnail, let cacheController = root.cacheControllable {
                HStack {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: model, listDisplayModel: listDisplayModel, entryId: entry.id)
                    
                    if editController.additioanlEnrtryViewType == .custom {
                        editController.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: root.configurable.module), entry: entry, textModel: nil)
                    }
                }
            }
            
            if editController.additioanlEnrtryViewType == .inline {
                editController.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: root.configurable.module), entry: entry, textModel: linkTextModel)
            } else {
                LinkHighlightTextView(model: linkTextModel)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if !hasThumbnail {
                if editController.additioanlEnrtryViewType == .custom {
                    editController.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: root.configurable.module), entry: entry, textModel: nil)
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
        editController.linkTextModel(itemId: itemId, for: entry, linkController: root.linkControllable, cacheItemListModel: cacheItemListModel, searchModel: searchModel)
    }
    
    var hasThumbnail: Bool {
        editController.thumbnailEntryViewType == .photo && root.cacheControllable != nil
    }
}
