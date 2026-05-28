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
    //
    // Fix #3: SheetRootModel is reused across item switches via reset(itemId:).
    // Previously, every item switch created a NEW SheetRootModel instance and
    // assigned it to @State sheetRootModel. That @State change re-ran
    // DetailEditorView.body (creating a new SheetRootEditorView struct with a
    // different sheetRootModel reference), which printed "@self changed" in
    // SheetRootEditorView. The user perceived this as "updates while scrolling"
    // because the async task completed while scrolling after an item switch.
    // Now only the first item creates the model; subsequent items call reset().
    @State private var sheetRootModel: SheetRootModel?

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        DetailSelectionEditorView(root: root, model: model)
            // task is swallowing the updates later, this causes a 2 double creation on start / that is acceptable
            .onChange(of: model.id, initial: true) {
                root.editorLinkModel.characterSelectionModel.onlyChildrenFrom <=> model.id
                if sheetRootModel == nil {
                    // First appearance: create the model once (one-time @State assignment).
                    sheetRootModel = SheetRootModel(
                        linkControllable: root.linkControllable,
                        sheetControllable: root.sheetControllable,
                        itemId: model.id,
                        isEditor: true,
                        editorModel: root.editController.sheetEditorModel
                    )
                } else {
                    // Subsequent item switches: update the model in-place.
                    // No @State change → DetailEditorView.body does NOT re-run
                    // → SheetRootEditorView.body does NOT re-run.
                    sheetRootModel?.reset(itemId: model.id)
                }
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
