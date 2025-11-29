// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableContentColumn<Menu: View>: View {
    let root: PdfRootModel
    let editController: EditController
    let entryId: UUID
    let menuView: () -> Menu

    var body: some View {
        @Bindable var model = editController.model
        DisclosureGroupTV(isExpanded: editController.editorModel.isExpanded(for: entryId)) {
            TextFieldInlineEditor(editController: editController, model: $model[entryId].content, prompt: "Enter some content for the bookmark", bundle: .module)
        } label: {
            LinkHighlightTextView(model: linkTextModel)
                .lineLimit(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
                .contextMenu {
                    menuView()
                }
        }
    }
    
    private var cacheItemListModel: CacheItemListModel {
        editController.cacheItemListModel
    }
    
    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .content, itemId: entryId) else {
            return updateLinkText()
        }
        return linkModel
    }
    
    @discardableResult
    private func updateLinkText() -> LinkHighlightTextModel {
        let entryText = editController.model[entryId].content
        if let linkModel = cacheItemListModel.itemLink(cacheType: .content, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: editController.editorModel.searchText, toggler: nil, shareResult: nil, editAction: nil)
            cacheItemListModel.setItemLink(cacheType: .content, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }
}

#Preview {
    TableContentColumn(root: .preview, editController: .preview, entryId: PdfEntryModel.previewId) {
        Text("Menu")
    }
}
