// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ValueEntryName: View {
    let root: CharacterRootModel
    let editController: EditController
    let itemId: UUID
    let entryId: UUID

    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions
    @Environment(\.showGame) private var showGame
    
    var body: some View {
        //let _ = Self._printChanges()
        
        LinkHighlightTextView(model: linkTextModel)
            .lineLimit(25)
            .onChange(of: editController.model[entryId].name, initial: false) {
                updateEntryValues()
            }
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = editController.cacheItemListModel.itemLink(cacheType: .entryName, itemId: entryId) else {
            return updateEntryValues()
        }
        let entryText = editController.model[entryId].name
        if entryText != linkModel.text {
            linkModel.reset(text: entryText)
        }
        return linkModel
    }

    @discardableResult
    private func updateEntryValues() -> LinkHighlightTextModel {
        let entryText = editController.model[entryId].name
        if let linkModel = editController.cacheItemListModel.itemLink(cacheType: .entryName, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: editController.editorModel.searchText, toggler: toggler(itemId:module:), shareResult: shareResult, editAction: { _ in true })
            editController.cacheItemListModel.setItemLink(cacheType: .entryName, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }

    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: itemId, childId: entryId, module: root.itemController.itemDataModel.networkModule), showGame: showGame, gameModus: gameModus)
    }
    
    private func toggler(itemId: UUID, module: NetworkModules) {
        routeActions.routePage(module, itemId, nil)
    }
}
