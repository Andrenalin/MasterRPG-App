// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: DiceRootModel
    let model: DiceModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailListView(root: root, model: model)
            .detailInspectorModifier(root: root.rootController)
            .folderNavigationResetTask(navigationModel: root.navigationModel, itemId: model.id)
            .onChange(of: root.navigationModel.triggerSpaceAction) {
                guard root.navigationModel.triggerSpaceAction else { return }
                root.navigationModel.triggerSpaceAction = false
                root.gameController.rollDice(itemId: model.id)
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? DiceModel.previewId))
            .preferredColorScheme(.dark)
    }
}
