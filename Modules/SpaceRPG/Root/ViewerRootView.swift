// @copyright André Trettin

import CoreRPG
import SwiftUI

struct ViewerRootView: View {
    let model: SpaceModel
    let configuration: ViewerConfiguration
    var dismissAction: (() -> Void)? = nil

    @Environment(SpaceRootModel.self) private var root
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
#if !os(tvOS)
            SpaceViewer(root: root, id: model.id, isModal: configuration.addToolbar)
                .id(model.id)
#endif
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .applyIf(configuration.addToolbar) {
            $0.toolbar {
                toolbarContent
            }
            .navigationTitle(Text(model.name))
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
#if !os(visionOS)
        .background(.black.gradient)
#endif
        .environment(CacheItemListModel())
    }
}

private extension ViewerRootView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        if configuration.closeButton {
            ToolbarItem(placement: .cancellationAction) {
                closeButton
            }
        }
    }

    var closeButton: some View {
        Button {
            if let dismissAction {
                dismissAction()
            } else {
                dismiss()
            }
        } label: {
            Image(systemName: "xmark.circle")
        }
        .foregroundStyle(root.config.module.tint)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(SpaceRootModel.self) var root

    ViewerRootView(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]), configuration: ViewerConfiguration())
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
}
