// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableNameColumn<Menu: View>: View {
    let root: TableRootModel
    let editController: EditController
    let entryId: UUID
    let menuView: () -> Menu

    @Environment(\.routeActions) private var routeActions
    
    @State private var isExpanded = false
    
    var body: some View {
        //let _ = Self._printChanges()
        @Bindable var model = editController.model
        DisclosureGroupTV(isExpanded: $isExpanded) {
            TextFieldInlineEditor(editController: editController, model: $model[entryId].name, prompt: "Enter a name for the entry", bundle: .module)
        } label: {
            LinkHighlightTextView(model: linkTextModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    menuView()
                }
        }
        .onChange(of: editController.editorModel.expandedEntries) {
            let currentExpanded = editController.editorModel.expandedEntries[entryId, default: false]
            guard isExpanded != currentExpanded else { return }
            withAnimation { isExpanded = currentExpanded }
        }
    }
    
    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = editController.cacheItemListModel.itemLink(cacheType: .name, itemId: entryId) else {
            return updateEntryValues()
        }
        return linkModel
    }

    @discardableResult
    private func updateEntryValues() -> LinkHighlightTextModel {
        let entryText = editController.model[entryId].nameLinkText
        if let linkModel = editController.cacheItemListModel.itemLink(cacheType: .name, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: editController.editorModel.searchText, toggler: toggler(itemId:module:), shareResult: nil, editAction: { _ in true })
            editController.cacheItemListModel.setItemLink(cacheType: .name, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }
    
    private func toggler(itemId: UUID, module: NetworkModules) {
        routeActions.routePage(module, itemId, nil)
    }
}
