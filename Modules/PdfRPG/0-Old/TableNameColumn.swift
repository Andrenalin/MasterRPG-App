// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableNameColumn<Menu: View>: View {
    let root: PdfRootModel
    let editController: EditController
    let entryId: UUID
    let menuView: () -> Menu

    var body: some View {
        @Bindable var model = editController.model
        DisclosureGroupTV(isExpanded: editController.editorModel.isExpanded(for: entryId)) {
            TextFieldInlineEditor(editController: editController, model: $model[entryId].name, prompt: "Enter a name for the bookmark", bundle: .module)
        } label: {
            LinkHighlightTextView(model: linkTextModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    menuView()
                }
        }
    }
    
    private var cacheItemListModel: CacheItemListModel {
        editController.cacheItemListModel
    }
    
    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .entryName, itemId: entryId) else {
            return updateLinkText()
        }
        return linkModel
    }
    
    @discardableResult
    private func updateLinkText() -> LinkHighlightTextModel {
        let entryText = editController.model[entryId].name
        if let linkModel = cacheItemListModel.itemLink(cacheType: .entryName, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: editController.editorModel.searchText, toggler: nil, shareResult: nil, editAction: nil)
            cacheItemListModel.setItemLink(cacheType: .entryName, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }
}
