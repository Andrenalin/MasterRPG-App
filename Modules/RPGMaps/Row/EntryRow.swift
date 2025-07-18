// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI

struct EntryRow: View {
    let model: MapModel
    let item: ItemRowTreeModel
    let isEditing: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(MapRoot.self) private var root
    @Environment(ListModel.self) private var listModel

    @Environment(\.navigator) private var navigator

    @Environment(\.gameModus) private var gameModus
    @Environment(\.itemListToggleAction) private var itemListToggleAction
    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions
    @Environment(\.showGame) private var showGame

    var itemId: UUID {
        item.model.itemId
    }

    var entryId: UUID {
        item.model.entryId ?? UUID()
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                EntryThumbnail(root: root, item: model, entryId: entryId)

                Text(model[entryId].name.markDown(asBold: true))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .showListItem(isActive: showGame, isShown: root.gameController.gameItem(for: itemId)[entryId].isShown) {
                withAnimation(.bouncy) {
                    root.gameController.gameItem(for: itemId).toggle(entryId)
                    networkActions?.game(root.gameController.networkMapUpdate(for: itemId), .mapState)
                }
            }

            VStack(alignment: .leading) {
                LinkHighlightTextView(model: linkTextModel)
                    .lineLimit(256)
            }
        }
        .onChange(of: model[entryId].textLinkContent, initial: false) {
            updateLinkText()
        }
        .onChange(of: listModel.searchText) {
            withAnimation { linkTextModel.reset(highlightedText: listModel.searchText) }
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
        let entryText = model[entryId].textLinkContent
        if let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: listModel.searchText, toggler: toggler(itemId:module:), shareResult: shareResult, editAction: isEditing ? { _ in isEditing } : nil)
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }

    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: itemId, childId: entryId, module: root.itemController.itemDataModel.networkModule), showGame: showGame, gameModus: gameModus)
    }
    
    private func toggler(itemId: UUID, module: NetworkModules) async {
        if isEditing {
            if module == .map {
                navigator.navigate(to: InternalRoute.editDetail(itemId))
            } else {
                routeActions.routePage(module, itemId, nil)
            }
        } else {
            itemListToggleAction.toggler(itemId, module)
        }
    }
}

#Preview {
    EntryRow(model: .preview, item: .preview, isEditing: false, cacheItemListModel: .preview)
        .padding()
        .environment(MapRoot.preview)
        .environment(\.gameModus, .master)
        .environment(\.showGame, true)
}
