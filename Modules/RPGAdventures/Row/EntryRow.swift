// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct EntryRow: View {
    let model: AdventureModel
    let item: ItemRowTreeModel
    let isEditing: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(AdventureRoot.self) private var root
    @Environment(ListModel.self) private var itemListModel

    @Environment(\.navigator) private var navigator

    @Environment(\.gameModus) private var gameModus
    @Environment(\.itemListToggleAction) private var itemListToggleAction
    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions
    @Environment(\.showGame) private var showGame

    var itemId: UUID {
        item.model.itemId
    }

    var entryId: AdventureEntryModel.ID {
        item.model.entryId ?? UUID()
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 4) {
            LinkHighlightTextView(model: linkTextModel)
                .lineLimit(256)
                .multilineTextAlignment(.leading)
        }
        .onChange(of: model[entryId].entryLinkText(), initial: false) {
            updateLinkText()
        }
    }
    
    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entryId) else {
            return updateLinkText()
        }
        return linkModel
    }
    
    @discardableResult
    private func updateLinkText() -> LinkHighlightTextModel {
        let entryText = model[entryId].entryLinkText()
        if let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.linkController, text: entryText, highlightedText: itemListModel.searchText, toggler: toggler(itemId:module:), shareResult: shareResult, editAction: isEditing ? { _ in isEditing } : nil)
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }

    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: itemId, childId: entryId, module: root.itemController.itemDataModel.networkModule), showGame: showGame, gameModus: gameModus)
    }
    
    private func toggler(itemId: UUID, module: NetworkModules) async {
        if isEditing {
            if module == .adventure {
                navigator.navigate(to: InternalRoute.editDetail(itemId))
            } else {
                routeActions.routePage(module, itemId, nil)
            }
        } else {
            itemListToggleAction.toggler(itemId, module)
        }
    }
}
