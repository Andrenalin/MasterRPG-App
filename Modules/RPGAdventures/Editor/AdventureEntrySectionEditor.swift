// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(AdventureRootModel.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    @State private var entrySectionEditorModel = EntrySectionEditorModel<AdventureModel>()

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) {
            AdventureEntryEditContent(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } contentView: {
            AdventureEntryEditRow(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } showLinkView: {
            showLink()
        } swipeActionView: {
            AdventureEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, actionType: .content)
        } menuView: {
            AdventureEntryMenuContext(editController: editController, entrySectionEditorModel: entrySectionEditorModel,menuType: .all)
        } linkActionView: {
            actionBarView()
        }
    }

    @ViewBuilder
    private func showLink() -> some View {
        @Bindable var entryModel = entrySectionEditorModel
        if let linkValue = entryModel.showLink {
            switch linkValue.type {
                case .audio:
                    editController.selectAudio(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
                case .dice:
                    editController.selectDice(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
                case .map:
                    editController.selectMap(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
                case .pdf:
                    editController.selectPdf(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
                case .photo:
                    editController.selectPhoto(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
                case .space:
                    editController.selectSpace(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
                case .table:
                    editController.selectTable(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
                case .value:
                    editController.selectValue(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
                case .weather:
                    editController.selectWeather(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
                default:
                    editController.selectAdventure(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionSheetLinkModel.selection = false }
            }
        }
    }

    @ViewBuilder
    private func actionBarView() -> some View {
        LinkWindowButton(type: .adventure)
        LinkWindowButton(type: .audio)
        LinkWindowButton(type: .dice)
        LinkWindowButton(type: .map)
        LinkWindowButton(type: .pdf)
        LinkWindowButton(type: .photo)
        LinkWindowButton(type: .space)
        LinkWindowButton(type: .table)
        LinkWindowButton(type: .value)
        LinkWindowButton(type: .weather)
    }
}

#Preview {
    AdventureEntrySectionEditor(editController: .preview)
        .environment(AdventureRootModel.previewWithData)
        .environment(ListModel.preview)
}
