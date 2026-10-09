// @copyright André Trettin

import Foundation
import SwiftUI

public struct EntryEditRow: View {
    public init(root: any ItemRootControllable, editController: any EntryDataEditable, itemId: UUID, entry: any EntryDataAccessible, cacheItemListModel: CacheItemListModel, listDisplayModel: ListDisplayModel, searchModel: SearchModel, resolvedModel: (any ModelType)? = nil) {
        self.root = root
        self.editController = editController
        self.itemId = itemId
        self.entry = entry
        self.cacheItemListModel = cacheItemListModel
        self.listDisplayModel = listDisplayModel
        self.searchModel = searchModel
        self.resolvedModel = resolvedModel
    }

    let root: any ItemRootControllable
    let editController: any EntryDataEditable
    let itemId: UUID
    let entry: any EntryDataAccessible
    let cacheItemListModel: CacheItemListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    /// Pre-resolved by the caller where available — see `ViewControllable`'s
    /// doc comment / CODE_AUDIT_10 §8.1. Falls back to `itemOrEmpty` when
    /// nil, so this stays correct for any call site not yet updated.
    let resolvedModel: (any ModelType)?

    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        VStack {
            if hasThumbnail, let cacheController = root.cacheControllable {
                HStack {
                    ThumbnailRowPhotoView(cacheController: cacheController, model: model, listDisplayModel: listDisplayModel, entryId: entry.id)
                    
                    if editController.additionalEntryViewType == .custom {
                        editController.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: root.configurable.module), entry: entry, textModel: nil)
                    }
                }
            }
            
            if editController.additionalEntryViewType == .inline {
                editController.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: root.configurable.module), entry: entry, textModel: linkTextModel)
            } else {
                LinkHighlightTextView(model: linkTextModel)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if !hasThumbnail {
                if editController.additionalEntryViewType == .custom {
                    editController.additionalRowView(for: ItemRowModel(itemId: itemId, entryId: entry.id, typeId: root.configurable.module), entry: entry, textModel: nil)
                }
            }
        }
    }
}

private extension EntryEditRow {
    var model: any ItemDataAccessible {
        (resolvedModel as? any ItemDataAccessible) ?? editController.itemControllable.itemOrEmpty(for: itemId)
    }
    
    var linkTextModel: LinkHighlightTextModel {
        editController.linkTextModel(itemId: itemId, for: entry, linkController: root.rootManager?.adventureRoot.linkControllable ?? root.linkControllable, cacheItemListModel: cacheItemListModel, searchModel: searchModel)
    }
    
    var hasThumbnail: Bool {
        editController.thumbnailEntryViewType == .photo && root.cacheControllable != nil
    }
}

#Preview {
    let fixture = FakeItemRootControllerFixture()
    EntryEditRow(
        root: fixture.root,
        editController: fixture.editController,
        itemId: .fixture1,
        entry: FakeEntryModel.empty,
        cacheItemListModel: CacheItemListModel(),
        listDisplayModel: ListDisplayModel(),
        searchModel: fixture.searchController.searchModel
    )
    .padding()
}
