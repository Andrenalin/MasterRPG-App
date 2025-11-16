// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapEntryValue: View {
    let root: MapRootModel
    let editController: EditController
    let entryId: UUID

    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions
    @Environment(\.showGame) private var showGame

    var body: some View {
        @Bindable var model = editController.model
        LinkHighlightTextView(model: linkTextModel)
            .lineLimit(25)
            .onChange(of: editController.model[entryId].content, initial: false) {
                updateEntryValues()
            }
    }

    private var cacheItemListModel: CacheItemListModel {
        editController.editorModel.cacheItemListModel
    }
    
    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .content, itemId: entryId) else {
            return updateEntryValues()
        }
        let entryText = editController.model[entryId].content
        if entryText != linkModel.text {
            linkModel.reset(text: entryText)
        }
        return linkModel
    }

    @discardableResult
    private func updateEntryValues() -> LinkHighlightTextModel {
        let entryText = editController.model[entryId].content
        if let linkModel = cacheItemListModel.itemLink(cacheType: .content, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: editController.editorModel.searchText, toggler: toggler(itemId:module:), shareResult: shareResult, editAction: { _ in true })
            cacheItemListModel.setItemLink(cacheType: .content, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }

    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: editController.model.id, childId: entryId, module: root.itemController.itemDataModel.networkModule), showGame: showGame, gameModus: gameModus)
    }
    
    private func toggler(itemId: UUID, module: NetworkModules) {
        routeActions.routePage(module, itemId, nil)
    }
}
