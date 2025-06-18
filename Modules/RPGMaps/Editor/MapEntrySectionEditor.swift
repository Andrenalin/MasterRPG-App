// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(MapRoot.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionModel
    @Environment(\.dismiss) private var dismiss

    @State private var entrySectionEditorModel = EntrySectionEditorModel<MapModel>()

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) {
            MapEntryEditContent(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } contentView: {
            MapEntryEditRow(editController: editController, entrySectionEditorModel: entrySectionEditorModel)
        } showLinkView: {
            showLink()
        } swipeActionView: {
            MapEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, actionType: .content)
        } menuView: {
            MapEntryMenuContext(editController: editController, entrySectionEditorModel: entrySectionEditorModel, menuType: .all)
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
                    editController.selectAudio(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionModel.selection = false }
                case .dice:
                    editController.selectDice(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionModel.selection = false }
                case .pdf:
                    editController.selectPdf(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionModel.selection = false }
                case .photo:
                    editController.selectPhoto(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionModel.selection = false }
                case .table:
                    editController.selectTable(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionModel.selection = false }
                case .value:
                    editController.selectValue(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionModel.selection = false }
                default:
                    editController.selectMap(for: linkValue.entryId, linkKeyPath: \.[linkValue.entryId].content) { selectionModel.selection = false }
            }
        }
    }

    @ViewBuilder
    private func actionBarView() -> some View {
        LinkWindowButton(type: .audio)
        LinkWindowButton(type: .dice)
        LinkWindowButton(type: .map)
        LinkWindowButton(type: .pdf)
        LinkWindowButton(type: .photo)
        LinkWindowButton(type: .table)
        LinkWindowButton(type: .value)
    }
}

#Preview {
    MapEntrySectionEditor(editController: .preview)
        .environment(MapRoot.previewWithData)
        .environment(ListModel.preview)
}
