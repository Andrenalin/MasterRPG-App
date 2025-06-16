// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct DiceDetailEditor: View {
    let editController: EditController
    let model: DiceModel

    @Environment(DiceRoot.self) private var root
    
    @State private var detailHeaderModel = DetailHeaderModel()
    @State private var externalHeaderModel = ExternalHeaderModel()

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
        } headerView: {
            DiceHeader(editController: editController)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
                .id(model.id)
        }
        .focusedSceneValue(\.selectedDice, $model.id)
        .environment(detailHeaderModel)
        .environment(externalHeaderModel)
        .onChange(of: model, initial: true) {
            let height = max(root.viewController.height(for: root.gameController.gameItem(for: model.id), minResult: 0, maxResult: 4) + valueFor(iOS: 16, macOS: 0, tvOS: 16, visionOS: 48), 64)
            detailHeaderModel.minHeight <=> height
            detailHeaderModel.maxHeight <=> height
        }
    }
}

#Preview {
    DiceDetailEditor(editController: .preview, model: .preview)
        .environment(DiceRoot.preview)
        .environment(ListModel.preview)
        .environment(SelectionSheetLinkModel())
}
