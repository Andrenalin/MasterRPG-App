// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct MapEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(MapRoot.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionModel
    @Environment(\.dismiss) private var dismiss

    @State private var showMapEditor = false

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController) { entryId, showLink in
            editContent(entryId: entryId, showLink: showLink)
        } contentView: { entryId, showLink in
            EntryRow(model: editController.model, item: ItemRowTreeModel(id: UUID(), model: ItemRowModel(itemId: editController.model.id, entryId: entryId, typeId: .map)), isEditing: true, cacheItemListModel: editController.cacheItemListModel)
        } showLinkView: { linkValue in
            showLink(linkValue: linkValue)
        } swipeActionView: { entryId, showLink in
            swipeButtons(for: entryId, keypath: \.[entryId].content, showLink: showLink)
        } menuView: { entryId, selection, showLink in
            contextMenu(for: entryId, selection: selection, showLink: showLink, keypath: nil)
        } linkActionView: { entryId, showLink in
            actionBarView(selection: entryId, showLink: showLink)
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
    private func editContent(entryId: UUID, showLink: Binding<ShowLinkEntryAction<MapModel>?>) -> some View {
        @Bindable var model = editController.model
        Group {
            TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the entry", bundle: .module)

            TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Content", prompt: "Enter some content for the entry", bundle: .module)
                .contextMenu {
                    contextMenu(for: entryId, selection: [], showLink: showLink, keypath: \.[entryId].content)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    swipeButtons(for: entryId, keypath: \.[entryId].content, showLink: showLink)
                }
#endif

            ToggleEditor(editController: editController, model: $model[entryId].isShown, title: "Shown", bundle: .module, icon: "eyes")

            UpdateMapPinEditor(editController: editController, entryId: entryId, pinId: nil)

            editEntryButtonView(entryId: entryId)
        }
    }

    @ViewBuilder
    private func showLink(linkValue: ShowLinkEntryAction<MapModel>) -> some View {
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

    @ViewBuilder
    private func swipeButtons(for entryId: UUID, keypath: WritableKeyPath<MapModel, String>, showLink: Binding<ShowLinkEntryAction<MapModel>?>) -> some View {
        LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keypath, title: "Audio", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .map, keyPath: keypath, title: "Map", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keypath, title: "Pdf", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .value, keyPath: keypath, title: "Value", bundle: .module, showLink: showLink)
    }

    @ViewBuilder
    private func contextMenu(for entryId: UUID?, selection: [UUID], showLink: Binding<ShowLinkEntryAction<MapModel>?>, keypath: WritableKeyPath<MapModel, String>?) -> some View {

        if let entryId {
            editEntryButtonView(entryId: entryId)

            if keypath != nil {
                Divider()

                LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keypath, title: "Audio", bundle: .module, showLink: showLink)

                LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: showLink)

                LinkSelectionButton(entryId: entryId, type: .map, keyPath: keypath, title: "Map", bundle: .module, showLink: showLink)

                LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keypath, title: "Pdf", bundle: .module, showLink: showLink)

                LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: showLink)

                LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: showLink)

                LinkSelectionButton(entryId: entryId, type: .value, keyPath: keypath, title: "Value", bundle: .module, showLink: showLink)
            }
        }
    }

    @ViewBuilder
    private func actionBarView(selection: UUID?, showLink: Binding<ShowLinkEntryAction<MapModel>?>) -> some View {
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
