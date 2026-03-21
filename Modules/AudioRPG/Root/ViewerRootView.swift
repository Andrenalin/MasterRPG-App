// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: AudioModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil
    
    @Environment(AudioRootModel.self) private var root
    
    var body: some View {
        TableRootSheet(root: root.rootController, itemId: model.id, module: root.config.module, configuration: configuration, dismissAction: dismissAction)
            .safeAreaBar(edge: .bottom) {
#if os(visionOS)
                AudioPlayerBarView()
                    .padding()
#else
                GlassEffectContainer {
                    AudioPlayerBarView()
                        .padding()
                }
#endif
            }
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(AudioRootModel.self) var root
    ManagedNavigationStack {
        ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items.first ?? AudioModel.previewId), configuration: ViewerConfiguration(closeButton: true), dismissAction: nil)
    }
}
