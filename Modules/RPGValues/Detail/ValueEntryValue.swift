// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ValueEntryValue: View {
    let root: ValueRoot
    let editController: EditController
    let itemId: UUID
    let entryId: UUID

    @Environment(\.gameModus) private var gameModus
    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions
    @Environment(\.showGame) private var showGame
    
    @State private var updateOtherValue: Bool = false

    var body: some View {
        //let _ = Self._printChanges()
        LinkHighlightTextView(model: linkTextModel)
            .lineLimit(25)
            .onChange(of: editController.model[entryId], initial: false) {
                updateEntryValues()
            }
            .onChange(of: updateOtherValue, initial: false) {
                updateEntryValues()
                root.linkController.updateValueCalculation(itemId: itemId, entryId: entryId) {
                    updateOtherValue.toggle()
                }
            }
            .onAppear {
                root.linkController.updateValueCalculation(itemId: itemId, entryId: entryId) {
                    updateOtherValue.toggle()
                }
            }
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = editController.cacheItemListModel.itemLink(cacheType: .content, itemId: entryId) else {
            return updateEntryValues()
        }
        let entryText = root.linkController.linkText(model: editController.model, entryId: entryId, withoutName: true)
        if entryText != linkModel.text  {
            linkModel.reset(text: entryText)
        }
        return linkModel
    }

    @discardableResult
    private func updateEntryValues() -> LinkHighlightTextModel {
        let entryText = root.linkController.linkText(model: editController.model, entryId: entryId, withoutName: true)
        if let linkModel = editController.cacheItemListModel.itemLink(cacheType: .content, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: editController.editorModel.searchText, toggler: toggler(itemId:module:), shareResult: shareResult, editAction: { _ in true })
            editController.cacheItemListModel.setItemLink(cacheType: .content, itemId: entryId, linkModel: linkModel)
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
