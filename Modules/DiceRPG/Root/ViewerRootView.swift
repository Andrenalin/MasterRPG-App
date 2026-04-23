// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: DiceModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        TableRootSheet(root: root.rootController, itemId: model.id, module: root.config.module, configuration: configuration, dismissAction: dismissAction)
            .id(model.id)
            .safeAreaBar(edge: .bottom) {
                GlassEffectContainerAll {
                    DiceViewer(model: model, isEditor: false)
                        .padding()
#if !os(visionOS)
                        .glassEffectAll(.clear)
#endif
                }
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    ManagedNavigationStack {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? DiceModel.previewId), configuration: ViewerConfiguration(closeButton: true), dismissAction: nil)
    }
}
