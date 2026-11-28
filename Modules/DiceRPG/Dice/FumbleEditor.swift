// @copyright André Trettin

import CoreRPG
import SwiftUI

struct FumbleEditor: View {
    let model: DiceModel

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        SpecialValueEditor(
            model: model,
            values: model.fumbleValues,
            toggleKeyPath: \.fumbleOnlyOnFirstDie,
            toggleTitle: "Only first die can fumble",
            toggleSaveMessage: String(localized: "change fumble option", bundle: .module),
            sectionHeader: Text("Fumble Options", bundle: .module),
            valuesLabel: Text("Fumble", bundle: .module),
            addLabel: Text("Add fumble", bundle: .module),
            valueFieldTitle: "Fumble Dice Value",
            valueFieldPrompt: "fumble",
            removeAnimation: .easeInOut,
            addAnimation: .easeInOut,
            onRemove: { root.editController.remove(fumble: $0, itemId: model.id, forceSave: true) },
            onAdd: { value, isDiceValueFumble in
                root.editController.add(fumble: value, isDiceValueFumble: isDiceValueFumble, itemId: model.id, forceSave: true)
            }
        )
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    FumbleEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
