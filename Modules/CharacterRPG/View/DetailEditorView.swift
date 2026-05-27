// @copyright André Trettin

import CoreRPG
import DiceRPG
import PhotoRPG
import SwiftUI

struct DetailEditorView: View {
    let root: CharacterRootModel
    let model: ValueModel

    // Fix #2: DetailEditorView now owns SheetRootModel.
    // It is created inside .task(id: model.id) — an async closure that runs
    // outside DetailEditorView.body's @Observable tracking window — so none of
    // the @Observable reads inside SheetRootModel.init are registered as
    // dependencies of this view. Previously those reads caused DetailEditorView
    // to observe \LinkHighLightLocations.locations and \ItemDataModel.itemData,
    // which looped every time text rendered.
    @State private var sheetRootModel: SheetRootModel?

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DetailSelectionEditorView(root: root, model: model)
            .task(id: model.id) {
                // Existing per-item setup kept here.
                root.editorLinkModel.characterSelectionModel.onlyChildrenFrom <=> model.id
                // SheetRootModel is rebuilt whenever the selected item changes.
                sheetRootModel = SheetRootModel(
                    linkControllable: root.linkControllable,
                    sheetControllable: root.sheetControllable,
                    itemId: model.id,
                    isEditor: true,
                    editorModel: root.editController.sheetEditorModel
                )
            }

        if let sheetRootModel {
            SheetRootEditorView(
                root: root.rootController,
                sheetRootModel: sheetRootModel,
                headerTitle: String(localized: "Values", bundle: .module).localizedString,
                linkTypes: LinkCharacterModuleTransferable.self
            )
        }
    }
}

struct DetailSelectionEditorView: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DiceDropSection(root: root, model: model)
        PhotoDropSection(root: root, model: model)
    }
}

private struct DiceDropSection: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        root.diceRoot.viewController.dropChooseView(model: root.editController.valueEditModel.selectionDice)
            .onChange(of: root.editController.valueEditModel.selectionDice.selection) {
                withAnimation(.easeInOut) {
                    root.editController.add(diceId: root.editController.valueEditModel.selectionDice.itemId, itemId: model.id)
                }
            }
            .task(id: model.diceId) {
                root.editController.valueEditModel.selectionDice.resetSelection(itemId: model.diceId, entryId: nil)
            }
    }
}

private struct PhotoDropSection: View {
    let root: CharacterRootModel
    let model: ValueModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        root.photoRoot.viewController.carouselPhotos(root: root.photoRoot, photoSelection: root.editController.valueEditModel.selectionPhoto)
            .onChange(of: root.editController.valueEditModel.selectionPhoto.selection) {
                withAnimation(.easeInOut) {
                    root.editController.add(selection: root.editController.valueEditModel.selectionPhoto.selection, itemId: model.id)
                }
            }
            .task(id: model.photoId) {
                root.editController.valueEditModel.selectionPhoto.resetSelection(selectionIds: model.photos)
            }
    }
}
