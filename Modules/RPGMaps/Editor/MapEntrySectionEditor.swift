// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(MapRoot.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionModel
    @Environment(\.dismiss) private var dismiss

    @State private var showMapEditor = false
    @State private var entrySectionEditorModel = EntrySectionEditorModel<MapModel>()

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) { entryId in
            editContent(entryId: entryId)
        } contentView: { entryId in
            EntryRow(model: editController.model, item: ItemRowTreeModel(id: UUID(), model: ItemRowModel(itemId: editController.model.id, entryId: entryId, typeId: .map)), isEditing: true, cacheItemListModel: editController.cacheItemListModel)
        } showLinkView: {
            showLink()
        } swipeActionView: { entryId in
            swipeButtons(for: entryId, keypath: \.[entryId].content)
        } menuView: { entryId, selection in
            contextMenu(for: entryId, selection: selection, keypath: nil)
        } linkActionView: { entryId in
            actionBarView(selection: entryId)
        }
        .onChange(of: showMapEditor) {
            if showMapEditor {
                selectionModel.selectionFullView = AnyView(mapEditView)
                selectionModel.idealSize = model.mapIdealSize
                showMapEditor = false
                withAnimation { selectionModel.selectionFullScreen = true }
            }
        }
    }

    @ViewBuilder
    private func editContent(entryId: UUID) -> some View {
        @Bindable var model = editController.model
        Group {
            TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the entry", bundle: .module)

            TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Content", prompt: "Enter some content for the entry", bundle: .module)
                .contextMenu {
                    contextMenu(for: entryId, selection: [], keypath: \.[entryId].content)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    swipeButtons(for: entryId, keypath: \.[entryId].content)
                }
#endif

            ToggleEditor(editController: editController, model: $model[entryId].isShown, title: "Shown", bundle: .module, icon: "eyes")

            UpdateMapPinEditor(editController: editController, entryId: entryId, pinId: nil)

            editEntryButtonView(entryId: entryId)
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
    private func swipeButtons(for entryId: UUID, keypath: WritableKeyPath<MapModel, String>) -> some View {
        @Bindable var entryModel = entrySectionEditorModel
        LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keypath, title: "Audio", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .map, keyPath: keypath, title: "Map", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keypath, title: "Pdf", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .value, keyPath: keypath, title: "Value", bundle: .module, showLink: $entryModel.showLink)
    }

    @ViewBuilder
    private func contextMenu(for entryId: UUID?, selection: [UUID], keypath: WritableKeyPath<MapModel, String>?) -> some View {

        @Bindable var entryModel = entrySectionEditorModel
        if let entryId {
            editEntryButtonView(entryId: entryId)

            if keypath != nil {
                Divider()

                LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keypath, title: "Audio", bundle: .module, showLink: $entryModel.showLink)

                LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

                LinkSelectionButton(entryId: entryId, type: .map, keyPath: keypath, title: "Map", bundle: .module, showLink: $entryModel.showLink)

                LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keypath, title: "Pdf", bundle: .module, showLink: $entryModel.showLink)

                LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: $entryModel.showLink)

                LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: $entryModel.showLink)

                LinkSelectionButton(entryId: entryId, type: .value, keyPath: keypath, title: "Value", bundle: .module, showLink: $entryModel.showLink)
            }
        }
    }

    @ViewBuilder
    private func actionBarView(selection: UUID?) -> some View {
        LinkWindowButton(type: .audio)
        LinkWindowButton(type: .dice)
        LinkWindowButton(type: .map)
        LinkWindowButton(type: .pdf)
        LinkWindowButton(type: .photo)
        LinkWindowButton(type: .table)
        LinkWindowButton(type: .value)
    }

    private func editEntryButtonView(entryId: MapEntryModel.ID) -> some View {
        Button {
            withAnimation {
                editController.editorModel.currentEntryId = entryId
                showMapEditor.toggle()
            }
        } label: {
            Label { Text("Edit Entry Map", bundle: .module) } icon: { Image(systemName: "pencil") }
        }
    }

    private var mapEditView: some View {
        RootEditCanvasMap(editController: editController)
            .environment(root)
#if os(iOS)
            .statusBar(hidden: true)
#endif
    }
}

#Preview {
    MapEntrySectionEditor(editController: .preview)
        .environment(MapRoot.previewWithData)
        .environment(ListModel.preview)
}
