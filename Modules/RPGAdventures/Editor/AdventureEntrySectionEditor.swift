// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(AdventureRoot.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController) { entryId, showLink in
            editContent(entryId: entryId, showLink: showLink)
        } contentView: { entryId, showLink in
            EntryRow(model: editController.model, item: ItemRowTreeModel(id: UUID(), model: ItemRowModel(itemId: editController.model.id, entryId: entryId, typeId: .adventure)), isEditing: true, cacheItemListModel: editController.cacheItemListModel)
        } showLinkView: { linkValue in
            showLink(linkValue: linkValue)
        } swipeActionView: { entryId, showLink in
            swipeButtons(for: entryId, keypath: \.[entryId].content, showLink: showLink)
        } menuView: { entryId, selection, showLink in
            contextMenu(for: entryId, selection: selection, showLink: showLink, keypath: nil)
        } linkActionView: { entryId, showLink in
            actionBarView(selection: entryId, showLink: showLink)
        }
    }

    @ViewBuilder
    private func editContent(entryId: UUID, showLink: Binding<ShowLinkEntryAction<AdventureModel>?>) -> some View {
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
        }
    }

    @ViewBuilder
    private func showLink(linkValue: ShowLinkEntryAction<AdventureModel>) -> some View {
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

    @ViewBuilder
    private func swipeButtons(for entryId: UUID, keypath: WritableKeyPath<AdventureModel, String>, showLink: Binding<ShowLinkEntryAction<AdventureModel>?>) -> some View {
        LinkSelectionButton(entryId: entryId, type: .adventure, keyPath: keypath, title: "Adventure", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keypath, title: "Audio", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .map, keyPath: keypath, title: "Map", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keypath, title: "Pdf", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .space, keyPath: keypath, title: "Space", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .value, keyPath: keypath, title: "Value", bundle: .module, showLink: showLink)

        LinkSelectionButton(entryId: entryId, type: .weather, keyPath: keypath, title: "Weather", bundle: .module, showLink: showLink)
    }

    @ViewBuilder
    private func contextMenu(for entryId: UUID?, selection: [UUID], showLink: Binding<ShowLinkEntryAction<AdventureModel>?>, keypath: WritableKeyPath<AdventureModel, String>?) -> some View {

        if let entryId, let keypath {
            LinkSelectionButton(entryId: entryId, type: .adventure, keyPath: keypath, title: "Adventure", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keypath, title: "Audio", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .map, keyPath: keypath, title: "Map", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keypath, title: "Pdf", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .space, keyPath: keypath, title: "Space", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .value, keyPath: keypath, title: "Value", bundle: .module, showLink: showLink)

            LinkSelectionButton(entryId: entryId, type: .weather, keyPath: keypath, title: "Weather", bundle: .module, showLink: showLink)
            
            Button {
                withAnimation { editController.collectPhotos(entryId: entryId) }
            } label: {
                Label {
                    Text("Collect Photo Links", bundle: .module)
                } icon: {
                    Image(systemName: "photo.stack.fill")
                }
            }
        }
    }

    @ViewBuilder
    private func actionBarView(selection: UUID?, showLink: Binding<ShowLinkEntryAction<AdventureModel>?>) -> some View {
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
        .environment(AdventureRoot.previewWithData)
        .environment(ListModel.preview)
}
