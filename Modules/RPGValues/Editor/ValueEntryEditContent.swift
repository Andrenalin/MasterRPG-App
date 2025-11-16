// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct ValueEntryEditContent: View {
    let editController: EditController
    let entrySectionEditorModel: EntrySectionEditorModel<ValueModel>

    @Environment(CharacterRootModel.self) private var root
    @Environment(EntrySectionSelectionModel.self) private var entrySectionSelectionModel

    var body: some View {
        @Bindable var model = editController.model
        Group {
            TextFieldControllerEditor(editController: editController, linkReplaceController: editController.nameEditLink(for: entryId), title: "Name", prompt: "Enter a name for the entry", bundle: .module)
                .id(entryId)
                .contextMenu {
                    ValueEntryMenuContext(editController: editController, entrySectionEditorModel: entrySectionEditorModel, menuType: .name)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    ValueEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, actionType: .name)
                }
#endif

            ValueTypeEditor(editController: editController, model: model, entryId: entryId)
                .id(entryId)

            Group {
                if model[entryId].type == .selection {
                    ToggleEditor(editController: editController, model: $model[entryId].isSelectedToggle, canToggle: model[entryId].canSelection, title: "Selection", bundle: .module, icon: "checkmark")
                        .id(entryId)
                } else {
                    TextFieldControllerEditor(editController: editController, linkReplaceController: editController.contentEditLink(for: entryId), title: "Value", prompt: "Enter a value for the entry", bundle: .module)
                        .id(entryId)
                        .contextMenu {
                            ValueEntryMenuContext(editController: editController, entrySectionEditorModel: entrySectionEditorModel, menuType: .value)
                        }
#if !os(tvOS)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            ValueEntrySwipeAction(editController: editController, entrySectionEditorModel: entrySectionEditorModel, actionType: .value)
                        }
#endif
                }
            }
            .transition(.move(edge: .leading))
            .animation(.bouncy, value: model[entryId].type)

            diceRowEditor(for: model, entryId: entryId)
                .id(entryId)

            valueRowEditor(for: model, entryId: entryId)
                .id(entryId)
        }
    }
}

private extension ValueEntryEditContent {
    var entryId: UUID {
        entrySectionSelectionModel.id
    }

    func diceRowEditor(for model: ValueModel, entryId: UUID) -> some View {
        HStack {
            Label { Text("Dice", bundle: .module) } icon: { Image(systemName: NetworkModules.dice.icon) }

            if model[entryId].diceId != nil {
                EntryListDiceRow(itemId: model.id, entryId: entryId)
                    .removeItemImage(isLeading: true) {
                        editController.removeDice(from: entryId)
                    }
            }

            Spacer()

            Button {
                entrySectionEditorModel.showLink = ShowLinkEntryAction(id: UUID(), entryId: entryId, type: .dice, keyPath: nil)
            } label: {
                Text(model[entryId].diceId == nil ? "Add" : "Change", bundle: .module)
            }
        }
    }

    func valueGroupTitle(entryId: UUID) -> String {
        guard let valueId =  editController.model[entryId].valueId else { return "" }
        return root.itemController.itemOrEmpty(for: valueId).name
    }

    func valueRowEditor(for model: ValueModel, entryId: UUID) -> some View {
        HStack {
            Label { Text("Group", bundle: .module) } icon: { Image(systemName: NetworkModules.value.icon) }

            if let childId = model[entryId].valueId {
                Text(valueGroupTitle(entryId: entryId))
                    .removeItemImage(isLeading: true) {
                        editController.removeChild(childId: childId)
                    }
            }

            Spacer()

            Button {
                entrySectionEditorModel.showLink = ShowLinkEntryAction(id: UUID(), entryId: entryId, type: .value, keyPath: nil)
            } label: {
                Text(model[entryId].valueId == nil ? "Add" : "Change", bundle: .module)
            }
        }
    }
}
