// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: Table Generation Preview Fixtures

extension TableGenerationController {
    @MainActor static var preview: TableGenerationController {
        TableRootModel.preview.generationController
    }
}

extension TableGenerationSessionStore {
    @MainActor static var preview: TableGenerationSessionStore {
        TableRootModel.preview.generationSessionStore
    }
}

extension TableGenerationModel {
    /// A dice table ("Beutetabelle B") with nothing chosen yet.
    @MainActor static var preview: TableGenerationModel {
        TableGenerationController.preview.makeModel(itemId: TableModel.previewId)
    }

    /// The same dice table with its first entry already resolved, so
    /// previews can show a "selected"/confirmable state.
    @MainActor static var previewResolved: TableGenerationModel {
        let controller = TableGenerationController.preview
        let model = controller.makeModel(itemId: TableModel.previewId)
        if let entry = model.root.entries.first {
            controller.select(entryId: entry.id, in: model.root, model: model)
        }
        return model
    }

    /// The dice table with a roll applied, so previews can show the
    /// "Rolled N" state (`select` alone clears `lastRoll`, so this needs
    /// `apply`/`roll` instead of `previewResolved`).
    @MainActor static var previewRolled: TableGenerationModel {
        let controller = TableGenerationController.preview
        let model = controller.makeModel(itemId: TableModel.previewId)
        controller.apply(result: 1, to: model.root, model: model)
        return model
    }

    /// A multi-select "list" table ("Roadside Encounters") with nothing
    /// chosen yet.
    @MainActor static var previewList: TableGenerationModel {
        TableGenerationController.preview.makeModel(itemId: TableModel.previewShortListId)
    }

    /// The list table with its linked entry selected, producing a nested
    /// child occurrence directly underneath that entry.
    @MainActor static var previewNested: TableGenerationModel {
        let controller = TableGenerationController.preview
        let model = controller.makeModel(itemId: TableModel.previewShortListId)
        if let linkedEntry = model.root.entries.last {
            controller.select(entryId: linkedEntry.id, in: model.root, model: model)
        }
        return model
    }

    /// A table with no entries, producing the empty-state error message.
    @MainActor static var previewEmpty: TableGenerationModel {
        TableGenerationController.preview.makeModel(itemId: TableModel.previewEmptyId)
    }
}
