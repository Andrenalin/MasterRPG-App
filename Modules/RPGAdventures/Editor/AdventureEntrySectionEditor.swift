// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureEntrySectionEditor: View {
    let editController: EditController
    
    @Environment(AdventureRoot.self) private var root
    @Environment(SelectionSheetLinkModel.self) private var selectionSheetLinkModel

    @State private var entrySectionEditorModel = EntrySectionEditorModel<AdventureModel>()

    var body: some View {
        @Bindable var model = editController.model

        EntrySectionEditor(editControllable: editController, entrySectionEditorModel: entrySectionEditorModel) { entryId in
            editContent(entryId: entryId)
        } contentView: { entryId in
            EntryRow(model: editController.model, item: ItemRowTreeModel(id: UUID(), model: ItemRowModel(itemId: editController.model.id, entryId: entryId, typeId: .adventure)), isEditing: true, cacheItemListModel: editController.cacheItemListModel)
        } showLinkView: {
            showLink()
        } swipeActionView: { entryId in
            swipeButtons(for: entryId, keypath: \.[entryId].content)
        } menuView: { entryId in
            contextMenu(for: entryId, keypath: nil)
        } linkActionView: {
            actionBarView()
        }
    }

    @ViewBuilder
    private func editContent(entryId: UUID) -> some View {
        @Bindable var model = editController.model
        Group {
            TextFieldEditor(editController: editController, model: $model[entryId].name, title: "Name", prompt: "Enter a name for the entry", bundle: .module)

            TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Content", prompt: "Enter some content for the entry", bundle: .module)
                .contextMenu {
                    contextMenu(for: entryId, keypath: \.[entryId].content)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    swipeButtons(for: entryId, keypath: \.[entryId].content)
                }
#endif
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
    private func swipeButtons(for entryId: UUID, keypath: WritableKeyPath<AdventureModel, String>) -> some View {
        @Bindable var entryModel = entrySectionEditorModel
        LinkSelectionButton(entryId: entryId, type: .adventure, keyPath: keypath, title: "Adventure", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keypath, title: "Audio", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .map, keyPath: keypath, title: "Map", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keypath, title: "Pdf", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .space, keyPath: keypath, title: "Space", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .value, keyPath: keypath, title: "Value", bundle: .module, showLink: $entryModel.showLink)

        LinkSelectionButton(entryId: entryId, type: .weather, keyPath: keypath, title: "Weather", bundle: .module, showLink: $entryModel.showLink)
    }

    @ViewBuilder
    private func contextMenu(for entryId: UUID?, keypath: WritableKeyPath<AdventureModel, String>?) -> some View {
        @Bindable var entryModel = entrySectionEditorModel
        if let entryId, let keypath {
            LinkSelectionButton(entryId: entryId, type: .adventure, keyPath: keypath, title: "Adventure", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .audio, keyPath: keypath, title: "Audio", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .dice, keyPath: keypath, title: "Dice", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .map, keyPath: keypath, title: "Map", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .pdf, keyPath: keypath, title: "Pdf", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .photo, keyPath: keypath, title: "Photo", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .space, keyPath: keypath, title: "Space", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .table, keyPath: keypath, title: "Table", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .value, keyPath: keypath, title: "Value", bundle: .module, showLink: $entryModel.showLink)

            LinkSelectionButton(entryId: entryId, type: .weather, keyPath: keypath, title: "Weather", bundle: .module, showLink: $entryModel.showLink)

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
        .environment(AdventureRoot.previewWithData)
        .environment(ListModel.preview)
}
