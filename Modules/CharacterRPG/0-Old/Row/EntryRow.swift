// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI

struct EntryRow: View {
    let linkController: LinkController
    let model: ValueModel
    let item: ItemRowTreeModel
    let isEditing: Bool
    let hasQuickEditor: Bool
    let cacheItemListModel: CacheItemListModel

    @Environment(ListModel.self) private var listModel

    @Environment(\.navigator) private var navigator

    @Environment(\.gameModus) private var gameModus
    @Environment(\.itemListToggleAction) private var itemListToggleAction
    @Environment(\.networkActions) private var networkActions
    @Environment(\.routeActions) private var routeActions
    @Environment(\.showGame) private var showGame

    @State private var updateOtherValue: Bool = false

    var itemId: UUID {
        item.model.itemId
    }

    var entryId: UUID {
        item.model.entryId ?? UUID()
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 4) {
            Group {
                HStack {
                    LinkHighlightTextView(model: linkTextModel)
                        .lineLimit(256)
                    
                    if model[entryId].diceId == nil {
                        Spacer()
                        quickEditView
                    }
                }
                
                HStack {
                    EntryListDiceRow(itemId: itemId, entryId: entryId)
                    if model[entryId].diceId != nil {
                        Spacer()
                        quickEditView
                    }
                }
            }
        }
        .onChange(of: listModel.searchText) {
            withAnimation { linkTextModel.reset(highlightedText: listModel.searchText) }
        }
        .onChange(of: model[entryId], initial: false) {
            updateEntryValues()
        }
        .onChange(of: updateOtherValue, initial: false) {
            updateEntryValues()
            linkController.updateValueCalculation(itemId: model.id, entryId: entryId) {
                updateOtherValue.toggle()
            }
        }
        .onAppear {
            linkController.updateValueCalculation(itemId: model.id, entryId: entryId) {
                updateOtherValue.toggle()
            }
        }
    }

    private var linkTextModel: LinkHighlightTextModel {
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entryId) else {
            return updateEntryValues()
        }
//        let entryText = linkController.linkText(model: model, entryId: entryId)
//        if entryText != linkModel.text  {
//            linkModel.reset(text: entryText)
//        }
        return linkModel
    }
    
    @discardableResult
    private func updateEntryValues() -> LinkHighlightTextModel {
        let entryText = linkController.linkText(model: model, entryId: entryId)
        if let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entryId) {
            withAnimation { linkModel.reset(text: entryText) }
            return linkModel
        } else {
            let linkModel = LinkHighlightTextModel(linkControllable: linkController.root.rootControllable.linkControllable, text: entryText, highlightedText: listModel.searchText, toggler: toggler(itemId:module:), shareResult: shareResult, editAction: isEditing ? { _ in isEditing } : nil)
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entryId, linkModel: linkModel)
            return linkModel
        }
    }

    private var quickEditView: some View {
        Button {
            withAnimation {
                if model.quickEditEntries.contains(entryId) {
                    model.quickEditEntries.remove(entryId)
                } else {
                    model.quickEditEntries.insert(entryId)
                }
            }
        } label: {
            Image(systemName: model.quickEditEntries.contains(entryId) ? "square.and.pencil" : "pencil")
                .foregroundStyle(Color.accentColor)
                .contentTransition(.symbolEffect(.replace.wholeSymbol))
        }
#if os(iOS) || os(visionOS)
        .borderLessTVBottonStyle()
#endif
        .contentShape(Rectangle())
        .opacity(canQuickEdit ? 1 : 0)
    }
    
    private var canQuickEdit: Bool {
        hasQuickEditor && linkController.root.itemController.itemOrEmpty(for: itemId)[entryId].valueId == nil
    }

    private var shareResult: ShareValueResult {
        ShareValueResult(networkActions: networkActions, resultCategory: ResultCategory(id: itemId, childId: entryId, module: linkController.itemController.itemDataModel.networkModule), showGame: showGame, gameModus: gameModus)
    }
    
    private func toggler(itemId: UUID, module: NetworkModules) async {
        if isEditing {
            if module == .value {
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
    EntryRow(linkController: .preview, model: .preview, item: .preview, isEditing: false, hasQuickEditor: true, cacheItemListModel: .preview)
        .environment(CharacterRootModel.preview)
}
