// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceDetailEditor: View {
    let editController: EditController
    let model: DiceModel

    @Environment(DiceRoot.self) private var root

    var body: some View {
        @Bindable var model = model

        DetailEditor(editController: editController) {
//#if os(visionOS)
//            ShowDiceSpace(root: root, itemId: model.id, viewModel: root.diceSpaceModel)
//#endif

            HeaderEditor(editController: editController)
            
            DiceEditor(editController: editController)

            DiceOptionEditor(editController: editController)

            CoupEditor(editController: editController)

            FumbleEditor(editController: editController)

            RerollEditor(editController: editController)

            SpecialOptionEditor(editController: editController)
        } headerView: { size, safeTopMargin, isInline in
            DiceHeader(editController: editController, size: size, topMargin: safeTopMargin, inline: isInline)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(model.id)
        } heightCalculator: { size in
            let height = max(root.viewController.height(for: root.gameController.gameItem(for: model.id), minResult: 0, maxResult: 4) + valueFor(iOS: 16, macOS: 0, tvOS: 16, visionOS: 48), 64)
            return (height, height)
        }
        .focusedSceneValue(\.selectedDice, $model.id)
    }
}

#Preview {
    DiceDetailEditor(editController: .preview, model: .preview)
        .environment(DiceRoot.preview)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
}
