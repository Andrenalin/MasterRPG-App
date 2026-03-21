// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: DiceModel
    var windowMode: Bool = false
    var dismissAction: (() -> Void)? = nil
    
    @Environment(DiceRootModel.self) private var root
    
    var body: some View {
        TableRootSheet(root: root.rootController, itemId: model.id, module: root.config.module, windowMode: windowMode, dismissAction: dismissAction)
            .safeAreaBar(edge: .bottom) {
#if os(visionOS)
                DiceViewer(model: model, isEditor: false)
                    .padding()
#else
                GlassEffectContainer {
                    DiceViewer(model: model, isEditor: false)
                        .padding()
                        .glassEffect(.clear)
                }
#endif
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(DiceRootModel.self) var root
    ManagedNavigationStack {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? DiceModel.previewId), dismissAction: nil)
    }
}
