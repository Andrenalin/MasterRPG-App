// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CoupEditor: View {
    let model: DiceModel

    @Environment(DiceRootModel.self) private var root

    var body: some View {
        SpecialValueEditor(
            model: model,
            values: model.coupValues,
            toggleKeyPath: \.coupOnlyOnFirstDie,
            toggleTitle: "Only first die can coup",
            toggleSaveMessage: String(localized: "change coup option", bundle: .module).localizedString,
            sectionHeader: Text("Coup Options", bundle: .module),
            valuesLabel: Text("Coup", bundle: .module),
            addLabel: Text("Add coup", bundle: .module),
            valueFieldTitle: "Coup Dice Value",
            valueFieldPrompt: "coup",
            removeAnimation: .default,
            addAnimation: .easeInOut,
            onRemove: { root.editController.remove(coup: $0, itemId: model.id) },
            onAdd: { value, isDiceValueCoup in
                root.editController.add(coup: value, isDiceValueCoup: isDiceValueCoup, itemId: model.id)
            }
        )
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root

    CoupEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}
