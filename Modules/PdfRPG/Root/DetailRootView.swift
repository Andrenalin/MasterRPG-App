// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: PdfRootModel
    let model: PdfModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        DetailListView(root: root, model: model)
            .detailInspectorModifier(root: root.rootController)
            .folderNavigationResetTask(navigationModel: root.navigationModel, itemId: model.id)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(PdfRootModel.self) var root

    ManagedNavigationStack {
        DetailRootView(root: root, model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? PdfRootModel.previewSpaceId))
            .preferredColorScheme(.dark)
    }
}
