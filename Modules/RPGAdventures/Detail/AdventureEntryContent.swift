// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureEntryContent: View {
    let root: AdventureRoot
    let editController: EditController
    let entryId: UUID

    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions
    @Environment(\.showGame) private var showGame

    var body: some View {
        @Bindable var model = model
        LinkHighlightTextView(model: linkTextModel)
            .lineLimit(25)
            .onChange(of: model[entryId].content, initial: false) {
                updateEntryValues()
            }
    }

    private var cacheItemListModel: CacheItemListModel {
        editController.cacheItemListModel
    }

    private var model: AdventureModel {
        editController.model
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .content, itemId: entryId) else {
            return updateEntryValues()
        }
        return linkModel
    }

    @discardableResult
    private func updateEntryValues() -> LinkHighlightTextModel {
        let entryText = model[entryId].content
        if let linkModel = cacheItemListModel.itemLink(cacheType: .content, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.linkControllable, text: entryText, highlightedText: editController.editorModel.searchText, toggler: toggler(itemId:module:), shareResult: shareResult, editAction: { _ in true })
            cacheItemListModel.setItemLink(cacheType: .content, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }

    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: model.id, childId: entryId, module: root.itemController.itemDataModel.networkModule), showGame: showGame, gameModus: gameModus)
    }
    
    private func toggler(itemId: UUID, module: NetworkModules) {
        routeActions.routePage(module, itemId, nil)
    }
}
