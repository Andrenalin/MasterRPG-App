// @copyright André Trettin


import CoreRPG
import SwiftUI

struct EntryRow: View {
    let model: TableModel
    let item: ItemRowTreeModel
    let isEditing: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(TableRootModel.self) private var root
    @Environment(ListModel.self) private var itemListModel

    @Environment(\.navigator) private var navigator
    
    @Environment(\.gameModus) private var gameModus
    @Environment(\.itemListToggleAction) private var itemListToggleAction
    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions
    @Environment(\.valueActions) private var valueActions
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
            HStack {
                LinkHighlightTextView(model: linkTextModel)
                    .lineLimit(256)

                Spacer()

                if gameModus == .master {
                    if let diceResult = model.diceResult {
                        Text("\(diceResult) \(Image(systemName: NetworkModules.dice.icon))")
                            .rowDiceResultColor()
                    }
                    if showGame {
                        Button {
                            let result = valueActions.createEntryResult(model.name, model[entryId].content, ResultCategory(id: itemId, childId: entryId, module: root.itemController.itemDataModel.networkModule))
                            networkActions?.game(result, .valueResult)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .borderLessTVBottonStyle()
                        .padding(4)
                        .foregroundStyle(.white)
                        .background {
                            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let diceResultEntry = model[entryId].diceResult {
                HStack {
                    Button {
                        let result = valueActions.createEntryResult(model.name, model[entryId].content, ResultCategory(id: itemId, childId: entryId, module: root.itemController.itemDataModel.networkModule))
                        networkActions?.game(result, .valueResult)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .borderLessTVBottonStyle()
                    .padding(4)
                    .foregroundStyle(.white)
                    .background {
                        RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
                    }
                    
                    Text("\(diceResultEntry) \(Image(systemName: NetworkModules.dice.icon))")
                        .rowDiceResultColor()
                }
                Spacer()
            }
        }
        .environment(\.shareResult, shareResult)
        .onChange(of: model[entryId].textLinkContent, initial: false) {
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
        let entryText = model[entryId].textLinkContent
        if let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: root.rootControllable.linkControllable, text: entryText, highlightedText: itemListModel.searchText, toggler: nil, shareResult: shareResult, editAction: isEditing ? { _ in isEditing } : nil)
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }
    
    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: itemId, childId: entryId, module: root.itemController.itemDataModel.networkModule), showGame: showGame, gameModus: gameModus)
    }
}

#Preview {
    EntryRow(model: .preview, item: .preview, isEditing: false, cacheItemListModel: .preview)
        .environment(TableRootModel.preview)
}
