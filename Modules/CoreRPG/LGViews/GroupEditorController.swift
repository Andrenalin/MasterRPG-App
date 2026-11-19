// @copyright André Trettin

import Foundation
import Observation

/// The state and the save rule of the group editor, kept apart from its views so both can be
/// tested. See CODE_AUDIT_TestGaps §8.5.
@Observable @MainActor
final class GroupEditorModel {
    internal init(namePlaceHolder: String, descriptionPlaceHolder: String, tags: [String], tagsPlaceHolder: String) {
        self.namePlaceHolder = namePlaceHolder
        self.descriptionPlaceHolder = descriptionPlaceHolder
        self.tags = tags
        self.originalTags = tags
        self.tagsPlaceHolder = tagsPlaceHolder
    }

    var name: String = ""
    var namePlaceHolder: String
    var description: String = ""
    var descriptionPlaceHolder: String
    // Seeded with the selected items' shared tags (when they all share the same set) so
    // `RemoveTagsEditor` actually shows what it's bound to remove, instead of starting
    // empty while the placeholder implies tags are already there. See CODE_AUDIT_EditItem §5.6.
    var tags: [String]
    // Immutable snapshot of the seeded value above, so `save()` can tell whether the user
    // actually changed anything even though `tags` may start non-empty now.
    let originalTags: [String]
    var tagsPlaceHolder: String
}

struct GroupEditorController {
    @MainActor init(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID]) {
        self.itemController = itemController
        self.editController = editController
        self.ids = ids
        self.model = GroupEditorController.processEditorModel(itemController: itemController, ids: ids)
    }
    
    /// With a model built earlier (see `GroupEditorRouteView`): the controller itself is a cheap
    /// value that can be rebuilt on every pass, the model is not.
    @MainActor init(itemController: any ItemControllable, editController: any EditControllable, ids: [UUID], model: GroupEditorModel) {
        self.itemController = itemController
        self.editController = editController
        self.ids = ids
        self.model = model
    }

    let itemController: any ItemControllable
    let editController: any EditControllable
    let ids: [UUID]
    
    let model: GroupEditorModel
    
    @MainActor static func processEditorModel(itemController: any ItemControllable, ids: [UUID]) -> GroupEditorModel {
        var name: String?
        var nameIsDifferent = false
        var description: String?
        var descriptionIsDifferent = false
        var tags: [String]?
        var tagsIsDifferent = false

        for itemId in ids {
            guard let model = itemController.itemSync(for: itemId) else { continue }
            if !nameIsDifferent && name == nil {
                name = model.name
            } else if !nameIsDifferent && name != model.name {
                nameIsDifferent = true
                name = nil
            }
            
            if !descriptionIsDifferent && description == nil {
                description = model.description
            } else if !descriptionIsDifferent && description != model.description {
                descriptionIsDifferent = true
                description = nil
            }

            if !tagsIsDifferent && tags == nil {
                tags = model.tags
            } else if !tagsIsDifferent && tags != model.tags {
                tagsIsDifferent = true
                tags = nil
            }
        }
        
        // Seed the editable `tags` with the shared set only when every selected item
        // actually agrees on it — if they differ, there's no single starting set to show
        // (matching the "Different Tags" placeholder), and starting from a mix would risk
        // silently introducing tags to items that never had them. See CODE_AUDIT_EditItem §5.6.
        let sharedTags = tagsIsDifferent ? [] : (tags ?? [])
        return GroupEditorModel(namePlaceHolder: name ?? String(localized: "Different Names", bundle: .module), descriptionPlaceHolder: description ?? String(localized: "Different Descriptions", bundle: .module), tags: sharedTags, tagsPlaceHolder: tags?.joined(separator: " ") ?? String(localized: "Different Tags", bundle: .module))
    }

    @MainActor func save() {
        // Only touch tags if the user actually changed them from what was loaded —
        // `reset(tags:)` fully replaces an item's tags, so saving unconditionally
        // whenever `model.tags` was merely non-empty (its old always-empty starting
        // value made "non-empty" and "changed" the same thing indistinguishable) used to
        // wipe out every selected item's original tags the moment the user added just one
        // new tag. See CODE_AUDIT_EditItem §5.6.
        let tagsChanged = model.tags != model.originalTags
        guard !model.name.isEmpty && model.name != model.namePlaceHolder ||
                !model.description.isEmpty && model.description != model.descriptionPlaceHolder ||
                tagsChanged else { return }
        for itemId in ids {
            // The standalone item editor always persists, even while a game is
            // running — unlike in-game quick-edit surfaces, which stay memory-only.
            if !model.name.isEmpty {
                editController.reset(name: model.name, itemId: itemId, forceSave: true)
            }

            if !model.description.isEmpty {
                editController.reset(description: model.description, itemId: itemId, forceSave: true)
            }

            if tagsChanged {
                editController.reset(tags: model.tags, itemId: itemId, forceSave: true)
            }
        }
    }
}
