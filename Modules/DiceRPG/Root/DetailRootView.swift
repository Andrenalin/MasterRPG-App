// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: DiceRootModel
    let model: DiceModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailListView(root: root, model: model, folderListController: root.folderListController)
            .detailInspectorModifier(root: root.rootController)
            .onChange(of: root.navigationModel.triggerSpaceAction) {
                guard root.navigationModel.triggerSpaceAction else { return }
                root.navigationModel.triggerSpaceAction = false
                root.gameController.rollDice(itemId: model.id)
#if !os(tvOS)
                root.donateRoll(of: model.id)
#endif
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
