// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DetailRootView: View {
    let root: GeneratorRootModel
    let model: GeneratorModel

    var body: some View {
        DetailListView(root: root, model: model)
            .detailInspectorModifier(root: root.rootController)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(GeneratorRootModel.self) var root

    if let model = root.itemController.itemSync(for: GeneratorModel.previewId) {
        DetailRootView(root: root, model: model)
    }
}
